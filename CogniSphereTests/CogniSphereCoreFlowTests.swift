import XCTest
import SwiftData
import UIKit
@testable import CogniSphere

@MainActor
final class CogniSphereCoreFlowTests: XCTestCase {
    private var retainedObjects: [AnyObject] = []

    override func setUp() async throws {
        try await super.setUp()
        RegionUIStore().setRegionOverride(nil)
        SubscriptionQuotaStore.shared.saveState(dayStart: currentDayStart(), usedCount: 0)
    }

    override func tearDown() async throws {
        RegionUIStore().setRegionOverride(nil)
        SubscriptionQuotaStore.shared.saveState(dayStart: currentDayStart(), usedCount: 0)
        try await super.tearDown()
    }

    func testDefaultLibraryDisplayNameLocalizesForEachRegion() {
        let createdAt = Date()
        let library = KnowledgeLibraryRecord(
            id: UUID().uuidString,
            name: RegionUIStore.copy(for: .taiwan).defaultActiveLibraryName,
            createdAt: createdAt,
            archivedAt: nil
        )

        XCTAssertEqual(
            KnowledgeLibraryStore.displayName(for: library, region: .taiwan),
            "目前知識庫"
        )
        XCTAssertEqual(
            KnowledgeLibraryStore.displayName(for: library, region: .unitedStates),
            "Active Library"
        )
        XCTAssertEqual(
            KnowledgeLibraryStore.displayName(for: library, region: .japan),
            "現在の知識ライブラリ"
        )
    }

    func testPrepareActiveLibraryForNextInsertionArchivesAtLimit() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container

        let store = retain(KnowledgeLibraryStore())
        try store.bootstrapIfNeeded(modelContext: context, libraries: [])

        let initialLibraries = try fetchLibraries(in: context)
        store.sync(with: initialLibraries)

        let insertionTarget = try store.prepareActiveLibraryForNextInsertion(
            currentNodeCount: KnowledgeLibraryStore.autoArchiveNodeLimit,
            modelContext: context
        )

        XCTAssertTrue(insertionTarget.didArchive)

        let libraries = try fetchLibraries(in: context)
        XCTAssertEqual(libraries.count, 2)

        let archivedLibraries = libraries.filter { $0.archivedAt != nil }
        let activeLibraries = libraries.filter { $0.archivedAt == nil }
        XCTAssertEqual(archivedLibraries.count, 1)
        XCTAssertEqual(activeLibraries.count, 1)
        XCTAssertEqual(activeLibraries.first?.id, insertionTarget.library.id)
    }

    func testExportPackageUsesLocalizedDefaultFolderStem() throws {
        let nodes = [makeNode(title: "測試節點", content: "內容")]

        let taiwanPackage = try withRegionOverride(.taiwan) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(taiwanPackage.directoryURL.lastPathComponent.contains("知識匯出"))

        let usPackage = try withRegionOverride(.unitedStates) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(usPackage.directoryURL.lastPathComponent.contains("Export"))

        let japanPackage = try withRegionOverride(.japan) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(japanPackage.directoryURL.lastPathComponent.contains("書き出し"))
    }

    func testExportPackageCreatesLocalizedAttachmentFolder() throws {
        let nodes = [makeNode(title: "Export Node", content: "Knowledge content")]

        let taiwanPackage = try withRegionOverride(.taiwan) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: taiwanPackage.directoryURL.appendingPathComponent("附件").path))

        let usPackage = try withRegionOverride(.unitedStates) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: usPackage.directoryURL.appendingPathComponent("attachments").path))

        let japanPackage = try withRegionOverride(.japan) {
            try KnowledgeExportService.buildExportPackage(for: nodes)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: japanPackage.directoryURL.appendingPathComponent("添付").path))
    }

    func testAuthorizeConsumesFreeQuotaAndPresentsPaywallAtLimit() {
        SubscriptionQuotaStore.shared.saveState(dayStart: currentDayStart(), usedCount: 0)
        let controller = retain(SubscriptionAccessController())

        XCTAssertTrue(controller.authorize(.smartScan))
        XCTAssertEqual(controller.remainingFreeUses, 2)
        XCTAssertNil(controller.presentedPaywall)

        XCTAssertTrue(controller.authorize(.smartScan))
        XCTAssertTrue(controller.authorize(.smartScan))
        XCTAssertEqual(controller.remainingFreeUses, 0)

        XCTAssertFalse(controller.authorize(.smartScan))
        XCTAssertEqual(controller.remainingFreeUses, 0)
        XCTAssertEqual(controller.presentedPaywall?.feature, .smartScan)
    }

    func testOCRDisplayFormatterRemovesUnnaturalEastAsianSpaces() {
        let normalized = OCRDisplayTextFormatter.normalize(
            "現 在 の 知 識 ラ イ ブ ラ リ\n妳 一 生 的 預 言"
        )

        XCTAssertEqual(normalized, "現在の知識ライブラリ\n妳一生的預言")
    }

    func testOCRDisplayFormatterCompactsSummaryAcrossLines() {
        let summary = OCRDisplayTextFormatter.compactSummary(
            "現 在 の\n知 識 ラ イ ブ ラ リ",
            maxLength: 40
        )

        XCTAssertEqual(summary, "現在の知識ライブラリ")
    }

    func testPublicationFallbackDraftPrefersLongDocumentTitleOverMetadata() {
        let text = """
        Designing Knowledge Workflows for Multilingual Study Systems
        A Practical Guide for OCR, Notes, and Review
        DOI 10.1234/example
        Published by Example Press
        """

        let draft = KnowledgeImportFallbackBuilder.makeDraft(from: text)

        XCTAssertEqual(
            draft.title,
            "Designing Knowledge Workflows for Multilingual Study Systems"
        )
    }

    func testPublicationFallbackDraftCombinesSplitCJKTitleLines() {
        let text = """
        程式設計新手指南
        從概念到實作
        第2版
        出版社：測試出版
        """

        let draft = KnowledgeImportFallbackBuilder.makeDraft(from: text)

        XCTAssertEqual(draft.title, "程式設計新手指南從概念到實作")
    }

    func testPublicationFallbackDraftCompletesGenericChineseGuideTitleWithSubject() {
        let text = """
        程式設計
        學習指南
        新手也能快速上手
        出版社：測試出版
        """

        let draft = KnowledgeImportFallbackBuilder.makeDraft(from: text)

        XCTAssertEqual(draft.title, "程式設計學習指南", "actual title: \(draft.title)")
    }

    func testPublicationFallbackDraftCompletesGenericEnglishGuideTitleWithSubject() {
        let text = """
        Probability and Statistics
        Study Guide
        For self-paced review
        Published by Example Press
        """

        let draft = KnowledgeImportFallbackBuilder.makeDraft(from: text)

        XCTAssertEqual(draft.title, "Probability and Statistics Study Guide")
    }

    func testPublicationFallbackDraftCompletesGenericJapaneseGuideTitleWithSubject() {
        let text = """
        プログラミング
        学習ガイド
        基礎から実践まで
        発行：テスト出版
        """

        let draft = KnowledgeImportFallbackBuilder.makeDraft(from: text)

        XCTAssertEqual(draft.title, "プログラミング学習ガイド")
    }

    func testEducationalCoverProfilePrefersConcreteBookTitleOverAudienceCopy() {
        let service = KnowledgeExtractionService.shared
        let text = """
        Python
        超入門
        知識ゼロの新手也能安心學會的操作超基礎全圖解
        """

        let profile = service.educationalCoverProfile(from: text)

        XCTAssertEqual(profile?.title, "Python 超入門", "actual title: \(String(describing: profile?.title))")
        XCTAssertEqual(
            profile?.audienceHint,
            "知識ゼロの新手也能安心學會的操作超基礎全圖解",
            "actual audienceHint: \(String(describing: profile?.audienceHint))"
        )
    }

    func testEducationalCoverProfileKeepsSubtitleNearSpecificTitle() {
        let service = KnowledgeExtractionService.shared
        let text = """
        混合系統
        Super Hybrid System
        技術與教師手冊
        """

        let profile = service.educationalCoverProfile(from: text)

        XCTAssertEqual(
            profile?.title,
            "混合系統 Super Hybrid System",
            "actual title: \(String(describing: profile?.title))"
        )
        XCTAssertEqual(
            profile?.subtitle,
            "技術與教師手冊",
            "actual subtitle: \(String(describing: profile?.subtitle))"
        )
    }

    func testExportedMarkdownUsesLocalizedAttachmentFolderLinks() throws {
        let image = makeSyntheticImage(size: CGSize(width: 600, height: 400))
        let attachment = try AttachmentStorageController.saveImage(image)
        defer {
            AttachmentStorageController.deleteStoredFileIfPresent(named: attachment.fileName)
        }

        let reference = KnowledgeReference(
            title: "圖像附件",
            type: .image,
            payload: attachment.fileName,
            attachmentData: attachment.data,
            attachmentOriginalFileName: attachment.originalFileName,
            attachmentMimeType: attachment.mimeType
        )
        let node = makeNode(title: "含附件節點", content: "這是一筆含附件的知識點。")
        node.references = [reference]

        let package = try withRegionOverride(.japan) {
            try KnowledgeExportService.buildExportPackage(for: [node], libraryName: "現在の知識ライブラリ")
        }

        let exportedFiles = try FileManager.default.contentsOfDirectory(
            at: package.directoryURL,
            includingPropertiesForKeys: nil
        )
        let nodeMarkdownURL = try XCTUnwrap(
            exportedFiles.first(where: { $0.pathExtension == "md" && $0.lastPathComponent != "index.md" })
        )
        let markdown = try String(contentsOf: nodeMarkdownURL, encoding: .utf8)

        XCTAssertTrue(markdown.contains("添付/"))
        XCTAssertFalse(markdown.contains("attachments/"))
    }

    func testGraphLayoutEngineClearsStateWhenNoNodes() {
        let engine = GraphLayoutEngine()
        engine.sync(with: [makeNode(title: "A", content: "topic graph", category: .thinkingScience)], mode: .constellation, newestNodeID: nil)

        XCTAssertFalse(engine.visNodes.isEmpty)

        engine.sync(with: [], mode: .constellation, newestNodeID: nil)

        XCTAssertTrue(engine.visNodes.isEmpty)
        XCTAssertTrue(engine.edges.isEmpty)
        XCTAssertTrue(engine.categoryAnchors.isEmpty)
    }

    func testGraphLayoutEngineInfersCrossDomainEdgesForRelatedNodes() {
        let engine = GraphLayoutEngine()
        let nodes = [
            makeNode(
                title: "演算法思維",
                content: "graph optimization inference bridge topic shared concept",
                category: .thinkingScience
            ),
            makeNode(
                title: "圖論模型",
                content: "graph optimization inference bridge topic shared concept",
                category: .mathematicalScience
            ),
            makeNode(
                title: "系統分析",
                content: "graph optimization inference bridge topic shared concept",
                category: .systemicScience
            )
        ]

        engine.sync(with: nodes, mode: .pathway, newestNodeID: nodes.last?.id)

        XCTAssertEqual(engine.visNodes.count, nodes.count)
        XCTAssertFalse(engine.edges.isEmpty)
        XCTAssertTrue(engine.edges.contains(where: { $0.isCrossDomain }))
    }

    private func makeInMemoryContainer() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            KnowledgeLibrary.self,
            KnowledgeNode.self,
            KnowledgeReference.self
        ])
        let configuration = ModelConfiguration(
            "test",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, ModelContext(container))
    }

    private func fetchLibraries(in context: ModelContext) throws -> [KnowledgeLibrary] {
        let descriptor = FetchDescriptor<KnowledgeLibrary>(
            sortBy: [SortDescriptor(\KnowledgeLibrary.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    private func makeNode(
        title: String,
        content: String,
        category: KnowledgeCategory = .thinkingScience
    ) -> KnowledgeNode {
        KnowledgeNode(
            title: title,
            content: content,
            category: category,
            x: 0,
            y: 0,
            z: 0
        )
    }

    private func makeSyntheticImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .semibold),
                .foregroundColor: UIColor.black
            ]
            "CogniSphere attachment test".draw(
                in: CGRect(x: 24, y: 40, width: size.width - 48, height: size.height - 80),
                withAttributes: attributes
            )
        }
    }

    private func currentDayStart() -> TimeInterval {
        Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
    }

    private func withRegionOverride<T>(
        _ region: SupportedRegionUI,
        operation: () throws -> T
    ) throws -> T {
        let store = retain(RegionUIStore())
        store.setRegionOverride(region)
        defer {
            store.setRegionOverride(nil)
        }
        return try operation()
    }

    private func retain<T: AnyObject>(_ object: T) -> T {
        retainedObjects.append(object)
        return object
    }
}
