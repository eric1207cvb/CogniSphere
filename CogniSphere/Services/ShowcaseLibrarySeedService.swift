import Foundation
import SwiftData
import UIKit

@MainActor
enum ShowcaseLibrarySeedService {
    private enum ShowcaseLanguage {
        case zhHant
        case en
        case ja
    }

    private struct ShowcaseReferenceSpec {
        let title: String
        let type: ReferenceType
        let payload: String
        let attachmentData: Data?
        let attachmentOriginalFileName: String?
        let attachmentMimeType: String?
    }

    private struct ShowcaseNodeSpec {
        let category: KnowledgeCategory
        let language: ShowcaseLanguage
        let title: String
        let content: String
        let webTitle: String
        let webURL: String
        let noteTitle: String
        let noteBody: String
        let fileKind: ReferenceType
        let attachmentTitle: String
        let attachmentBody: String
        let accentColor: UIColor
        let bullets: [String]
    }

    static func createShowcaseLibrary(
        modelContext: ModelContext,
        libraryStore: KnowledgeLibraryStore,
        libraries: [KnowledgeLibrary],
        nodes: [KnowledgeNode],
        region: SupportedRegionUI
    ) throws -> KnowledgeLibraryRecord {
        let targetLibrary = try prepareTargetLibrary(
            modelContext: modelContext,
            libraryStore: libraryStore,
            libraries: libraries,
            nodes: nodes,
            region: region
        )

        for spec in showcaseNodeSpecs {
            let node = try buildNode(from: spec, library: targetLibrary)
            modelContext.insert(node)
        }

        try modelContext.save()
        libraryStore.selectLibrary(id: targetLibrary.id)
        return KnowledgeLibraryRecord(
            id: targetLibrary.id,
            name: targetLibrary.name,
            createdAt: targetLibrary.createdAt,
            archivedAt: targetLibrary.archivedAt
        )
    }

    private static func prepareTargetLibrary(
        modelContext: ModelContext,
        libraryStore: KnowledgeLibraryStore,
        libraries: [KnowledgeLibrary],
        nodes: [KnowledgeNode],
        region: SupportedRegionUI
    ) throws -> KnowledgeLibrary {
        let resolvedLibraries = libraries.isEmpty ? try fetchLibraries(using: modelContext) : libraries
        let activeLibrary = resolvedLibraries.first(where: { $0.id == libraryStore.activeLibraryID })
            ?? resolvedLibraries.first(where: { $0.archivedAt == nil })
            ?? resolvedLibraries.first

        if let activeLibrary {
            let activeCount = nodes.filter { effectiveLibraryID(for: $0, fallback: libraryStore.activeLibraryID) == activeLibrary.id }.count
            if activeCount == 0 {
                activeLibrary.name = showcaseLibraryName(for: region)
                activeLibrary.archivedAt = nil
                try modelContext.save()
                return activeLibrary
            }
        }

        _ = try libraryStore.archiveCurrentLibraryAndCreateNew(modelContext: modelContext, libraries: resolvedLibraries)
        let refreshedLibraries = try fetchLibraries(using: modelContext)
        guard let newActiveLibrary = refreshedLibraries.first(where: { $0.id == libraryStore.activeLibraryID }) else {
            throw KnowledgeLibraryStoreError.activeLibraryUnavailable
        }
        newActiveLibrary.name = showcaseLibraryName(for: region)
        try modelContext.save()
        return newActiveLibrary
    }

    private static func buildNode(from spec: ShowcaseNodeSpec, library: KnowledgeLibrary) throws -> KnowledgeNode {
        let node = KnowledgeNode(
            title: spec.title,
            content: spec.content,
            category: spec.category,
            x: 0,
            y: 0,
            z: 0,
            libraryID: library.id,
            libraryName: library.name
        )

        let attachmentReference = try buildAttachmentReference(for: spec)
        node.references = [
            KnowledgeReference(
                title: spec.noteTitle,
                type: .text,
                payload: spec.noteBody
            ),
            KnowledgeReference(
                title: spec.webTitle,
                type: .web,
                payload: spec.webURL
            ),
            attachmentReference
        ]
        return node
    }

    private static func buildAttachmentReference(for spec: ShowcaseNodeSpec) throws -> KnowledgeReference {
        let storedAttachment: StoredAttachment
        switch spec.fileKind {
        case .image:
            storedAttachment = try AttachmentStorageController.saveImage(
                generateShowcaseImage(
                    title: spec.title,
                    subtitle: spec.attachmentBody,
                    color: spec.accentColor
                )
            )
        case .pdf:
            storedAttachment = try AttachmentStorageController.storeGeneratedFile(
                data: generateShowcasePDF(
                    title: spec.title,
                    summary: spec.attachmentBody,
                    bullets: spec.bullets,
                    color: spec.accentColor
                ),
                preferredFileName: pdfFileName(for: spec),
                explicitMimeType: "application/pdf"
            )
        case .web, .text, .audio:
            fatalError("Unsupported showcase attachment type")
        }

        return KnowledgeReference(
            title: spec.attachmentTitle,
            type: spec.fileKind,
            payload: storedAttachment.fileName,
            attachmentData: storedAttachment.data,
            attachmentOriginalFileName: storedAttachment.originalFileName,
            attachmentMimeType: storedAttachment.mimeType
        )
    }

    private static func generateShowcaseImage(title: String, subtitle: String, color: UIColor) -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let cgContext = context.cgContext
            let backgroundColors = [color.withAlphaComponent(0.94).cgColor, color.withAlphaComponent(0.34).cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: backgroundColors, locations: [0, 1])!

            cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )

            UIColor.white.withAlphaComponent(0.18).setFill()
            UIBezierPath(roundedRect: CGRect(x: 88, y: 88, width: size.width - 176, height: size.height - 176), cornerRadius: 42).fill()

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .left
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 70, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: titleStyle
            ]
            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .paragraphStyle: titleStyle
            ]
            let brandAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.9)
            ]

            NSString(string: "CogniSphere Showcase").draw(in: CGRect(x: 132, y: 138, width: size.width - 264, height: 42), withAttributes: brandAttributes)
            NSString(string: title).draw(with: CGRect(x: 132, y: 248, width: size.width - 264, height: 320), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: titleAttributes, context: nil)
            NSString(string: subtitle).draw(with: CGRect(x: 132, y: 650, width: size.width - 264, height: 240), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: subtitleAttributes, context: nil)
        }
    }

    private static func generateShowcasePDF(
        title: String,
        summary: String,
        bullets: [String],
        color: UIColor
    ) -> Data {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            context.beginPage()
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .bold),
                .foregroundColor: UIColor.black
            ]
            let headingAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: color
            ]
            let bodyStyle = NSMutableParagraphStyle()
            bodyStyle.lineSpacing = 4
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 15, weight: .regular),
                .foregroundColor: UIColor.darkText,
                .paragraphStyle: bodyStyle
            ]

            color.setFill()
            UIBezierPath(roundedRect: CGRect(x: 36, y: 36, width: bounds.width - 72, height: 12), cornerRadius: 6).fill()
            NSString(string: title).draw(in: CGRect(x: 36, y: 72, width: bounds.width - 72, height: 40), withAttributes: titleAttributes)
            NSString(string: "One-page reference").draw(in: CGRect(x: 36, y: 120, width: bounds.width - 72, height: 22), withAttributes: headingAttributes)
            NSString(string: summary).draw(
                with: CGRect(x: 36, y: 154, width: bounds.width - 72, height: 170),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: bodyAttributes,
                context: nil
            )

            NSString(string: "Highlights").draw(in: CGRect(x: 36, y: 344, width: bounds.width - 72, height: 22), withAttributes: headingAttributes)
            var yOffset: CGFloat = 378
            for bullet in bullets {
                NSString(string: "• \(bullet)").draw(
                    with: CGRect(x: 48, y: yOffset, width: bounds.width - 96, height: 56),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: bodyAttributes,
                    context: nil
                )
                yOffset += 62
            }

            NSString(string: "Generated for App Store showcase screenshots").draw(
                in: CGRect(x: 36, y: bounds.height - 54, width: bounds.width - 72, height: 20),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: UIColor.gray
                ]
            )
        }
    }

    private static func showcaseLibraryName(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "上架示範知識庫"
        case .unitedStates:
            return "App Store Showcase"
        case .japan:
            return "審査用サンプル"
        }
    }

    private static func pdfFileName(for spec: ShowcaseNodeSpec) -> String {
        let stem = spec.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return stem.isEmpty ? "showcase-brief.pdf" : "\(stem)-brief.pdf"
    }

    private static func effectiveLibraryID(for node: KnowledgeNode, fallback: String) -> String {
        let rawID = node.libraryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return rawID.isEmpty ? fallback : rawID
    }

    private static func fetchLibraries(using modelContext: ModelContext) throws -> [KnowledgeLibrary] {
        try modelContext.fetch(
            FetchDescriptor<KnowledgeLibrary>(
                sortBy: [SortDescriptor(\KnowledgeLibrary.createdAt, order: .reverse)]
            )
        )
    }

    private static let showcaseNodeSpecs: [ShowcaseNodeSpec] = [
        ShowcaseNodeSpec(
            category: .naturalScience,
            language: .zhHant,
            title: "海洋塑膠降解路徑",
            content: "整理海洋環境中塑膠碎片的物理風化、紫外線脆化與微生物參與降解流程，並比較不同聚合物在鹽度、溫度與流速條件下的分解速度。",
            webTitle: "UNEP Marine Litter",
            webURL: "https://www.unep.org/interactives/beat-plastic-pollution/",
            noteTitle: "觀察筆記",
            noteBody: "可作為環境科學與材料科學交叉案例，適合展示圖譜中的自然科學節點。",
            fileKind: .image,
            attachmentTitle: "現場觀測圖卡",
            attachmentBody: "從污染來源、風化條件到微生物作用，一張圖整理塑膠降解路徑。",
            accentColor: UIColor(red: 0.21, green: 0.67, blue: 0.49, alpha: 1),
            bullets: ["紫外線與磨損會先造成脆化。", "微塑膠更容易被生態系統攝入。", "降解速度受材質與環境條件影響。"]
        ),
        ShowcaseNodeSpec(
            category: .naturalScience,
            language: .en,
            title: "CRISPR Gene Editing Workflow",
            content: "Maps the practical workflow of CRISPR-based editing from guide RNA design to delivery, target cleavage, repair pathways, and validation. Highlights where off-target screening changes the reliability of a result.",
            webTitle: "NIH Gene Editing Overview",
            webURL: "https://www.genome.gov/about-genomics/policy-issues/Genome-Editing/what-is-Genome-Editing",
            noteTitle: "Lab note",
            noteBody: "Useful for screenshots because the topic reads clearly in English and fits a science-oriented graph cluster.",
            fileKind: .pdf,
            attachmentTitle: "Workflow Brief",
            attachmentBody: "A one-page brief covering target design, delivery, cleavage, and repair verification.",
            accentColor: UIColor(red: 0.16, green: 0.56, blue: 0.76, alpha: 1),
            bullets: ["Guide RNA specificity shapes off-target risk.", "Repair choice changes the final edit outcome.", "Validation requires sequencing or phenotype checks."]
        ),
        ShowcaseNodeSpec(
            category: .naturalScience,
            language: .ja,
            title: "火山灰の粒径と拡散",
            content: "噴火後に火山灰がどのように粒径ごとに分離され、風向・高度・湿度の違いによって拡散範囲が変わるかを整理した知識点。航空運用や防災判断への影響も含める。",
            webTitle: "気象庁 火山情報",
            webURL: "https://www.jma.go.jp/jma/kishou/know/volcano/",
            noteTitle: "補足ノート",
            noteBody: "防災と自然科学をつなぐ題材として、スクリーンショットでも意味が伝わりやすい。",
            fileKind: .image,
            attachmentTitle: "観測整理カード",
            attachmentBody: "粒径、高度、風向の三要素から火山灰拡散の見方を整理。",
            accentColor: UIColor(red: 0.39, green: 0.48, blue: 0.73, alpha: 1),
            bullets: ["粒径が小さいほど遠方へ届きやすい。", "上空風の向きで分布が大きく変わる。", "湿度は沈降と凝集に影響する。"]
        ),
        ShowcaseNodeSpec(
            category: .mathematicalScience,
            language: .zhHant,
            title: "貝氏更新與先驗直覺",
            content: "用醫療檢測與產品實驗的例子，說明先驗機率、似然比與後驗機率之間的關係，並指出 base rate 忽略會如何扭曲解讀。",
            webTitle: "Bayes' theorem",
            webURL: "https://en.wikipedia.org/wiki/Bayes%27_theorem",
            noteTitle: "教學筆記",
            noteBody: "這筆資料適合搭配圖譜展示數學科學中的推論方法。",
            fileKind: .pdf,
            attachmentTitle: "條件機率摘要",
            attachmentBody: "用醫療檢測範例快速理解先驗、似然與後驗的更新順序。",
            accentColor: UIColor(red: 0.21, green: 0.58, blue: 0.89, alpha: 1),
            bullets: ["後驗機率取決於先驗與證據強度。", "罕見事件即使測試準確仍可能誤判。", "用 odds 形式更容易理解連續更新。"]
        ),
        ShowcaseNodeSpec(
            category: .mathematicalScience,
            language: .en,
            title: "Eigenvectors in Dimensionality Reduction",
            content: "Explains why eigenvectors reveal dominant directions of variance in a dataset, and how that principle supports PCA for compression, visualization, and denoising tasks.",
            webTitle: "Principal component analysis",
            webURL: "https://en.wikipedia.org/wiki/Principal_component_analysis",
            noteTitle: "Summary note",
            noteBody: "Good screenshot example because it reads as a classic math-and-data topic without being too niche.",
            fileKind: .image,
            attachmentTitle: "PCA Concept Card",
            attachmentBody: "A visual summary of covariance, principal axes, and the meaning of reduced dimensions.",
            accentColor: UIColor(red: 0.17, green: 0.66, blue: 0.83, alpha: 1),
            bullets: ["Principal components maximize projected variance.", "Orthogonality prevents duplicated information.", "Lower dimensions can preserve structure surprisingly well."]
        ),
        ShowcaseNodeSpec(
            category: .mathematicalScience,
            language: .ja,
            title: "グラフ彩色と制約最適化",
            content: "隣接ノードが同じ色にならない条件から、試験日程、周波数割当、資源競合の回避までを一つの制約最適化問題として捉える知識点。",
            webTitle: "Graph coloring",
            webURL: "https://en.wikipedia.org/wiki/Graph_coloring",
            noteTitle: "要点メモ",
            noteBody: "制約条件が明確で、知識グラフ上でも構造が見えやすい数学テーマ。",
            fileKind: .pdf,
            attachmentTitle: "彩色問題メモ",
            attachmentBody: "彩色数の意味と、現実問題への対応づけを一枚に整理。",
            accentColor: UIColor(red: 0.41, green: 0.57, blue: 0.94, alpha: 1),
            bullets: ["衝突回避を色の違いとして表現できる。", "制約が増えるほど最適化は難しくなる。", "日程・通信・配置問題へ応用できる。"]
        ),
        ShowcaseNodeSpec(
            category: .systemicScience,
            language: .zhHant,
            title: "零信任網路分段",
            content: "說明零信任架構如何將身分驗證、最小權限與網路分段結合，降低橫向移動風險，並比較傳統內網信任模型的弱點。",
            webTitle: "NIST Zero Trust",
            webURL: "https://www.nist.gov/publications/zero-trust-architecture",
            noteTitle: "架構備忘",
            noteBody: "適合用來展示系統科學類中偏資訊安全的節點。",
            fileKind: .image,
            attachmentTitle: "架構示意卡",
            attachmentBody: "從身分、政策、分段到監控，一張圖看零信任核心流程。",
            accentColor: UIColor(red: 0.96, green: 0.55, blue: 0.35, alpha: 1),
            bullets: ["不預設內網即可信任。", "每次請求都需要驗證與授權。", "分段能降低橫向移動衝擊面。"]
        ),
        ShowcaseNodeSpec(
            category: .systemicScience,
            language: .en,
            title: "Event-Driven System Design",
            content: "Summarizes how producers, brokers, and consumers coordinate through events, and where idempotency, ordering, and eventual consistency become the major design tradeoffs.",
            webTitle: "Event-driven architecture",
            webURL: "https://learn.microsoft.com/azure/architecture/guide/architecture-styles/event-driven",
            noteTitle: "Design note",
            noteBody: "Shows a recognizable systems topic for app screenshots with English UI.",
            fileKind: .pdf,
            attachmentTitle: "EDA Brief",
            attachmentBody: "A practical guide to producers, brokers, consumers, and consistency tradeoffs.",
            accentColor: UIColor(red: 0.98, green: 0.64, blue: 0.31, alpha: 1),
            bullets: ["Events decouple services in time and ownership.", "Idempotency protects repeated delivery.", "Ordering guarantees are expensive and contextual."]
        ),
        ShowcaseNodeSpec(
            category: .systemicScience,
            language: .ja,
            title: "分散システムの合意形成",
            content: "ノード障害や通信遅延がある環境で、なぜ合意形成アルゴリズムが必要なのかを整理し、可用性と整合性のトレードオフを例で説明する。",
            webTitle: "Consensus algorithm",
            webURL: "https://en.wikipedia.org/wiki/Consensus_(computer_science)",
            noteTitle: "設計メモ",
            noteBody: "システム科学の中でも、分散設計の基礎として見せやすい題材。",
            fileKind: .image,
            attachmentTitle: "合意形成カード",
            attachmentBody: "障害時の整合性維持とリーダー選出の考え方を整理。",
            accentColor: UIColor(red: 0.89, green: 0.47, blue: 0.28, alpha: 1),
            bullets: ["障害下でも状態を揃える必要がある。", "選出と複製の設計が中核になる。", "可用性と整合性は同時に最大化しづらい。"]
        ),
        ShowcaseNodeSpec(
            category: .thinkingScience,
            language: .zhHant,
            title: "批判思考中的證據階層",
            content: "整理傳聞、專家意見、觀察研究、隨機對照試驗與系統性回顧之間的證據強弱差異，幫助判讀論證品質。",
            webTitle: "Critical thinking",
            webURL: "https://en.wikipedia.org/wiki/Critical_thinking",
            noteTitle: "判讀提醒",
            noteBody: "適合在思維科學類別中展示『如何判斷資訊可信度』。",
            fileKind: .pdf,
            attachmentTitle: "證據階層摘要",
            attachmentBody: "從逸聞到系統性回顧，快速辨識主張背後的證據力。",
            accentColor: UIColor(red: 0.64, green: 0.50, blue: 0.84, alpha: 1),
            bullets: ["資訊來源不同，可信度也不同。", "研究設計決定推論強度。", "引用數量不等於證據品質。"]
        ),
        ShowcaseNodeSpec(
            category: .thinkingScience,
            language: .en,
            title: "Analogy vs Causation",
            content: "Distinguishes surface similarity from causal explanation and shows why analogies are useful for learning but dangerous when treated as proof.",
            webTitle: "Causality",
            webURL: "https://en.wikipedia.org/wiki/Causality",
            noteTitle: "Reasoning note",
            noteBody: "Good for screenshots because the title is short, readable, and clearly about thinking skills.",
            fileKind: .image,
            attachmentTitle: "Reasoning Card",
            attachmentBody: "A compact contrast between comparison-based explanation and true causal inference.",
            accentColor: UIColor(red: 0.54, green: 0.43, blue: 0.83, alpha: 1),
            bullets: ["Analogies transfer intuition, not proof.", "Causal claims require mechanism and evidence.", "Good explanations can still be logically weak."]
        ),
        ShowcaseNodeSpec(
            category: .thinkingScience,
            language: .ja,
            title: "演繹と帰納の使い分け",
            content: "一般原理から個別結論を導く演繹と、観察の積み重ねから仮説を組み立てる帰納を対比し、学習・研究・意思決定での使い分けを示す。",
            webTitle: "Deductive reasoning",
            webURL: "https://en.wikipedia.org/wiki/Deductive_reasoning",
            noteTitle: "思考メモ",
            noteBody: "学習の方法論として見せやすく、日本語UIでも意味が明快。",
            fileKind: .pdf,
            attachmentTitle: "推論比較メモ",
            attachmentBody: "演繹と帰納の違い、強み、限界を一枚で比較。",
            accentColor: UIColor(red: 0.73, green: 0.57, blue: 0.90, alpha: 1),
            bullets: ["演繹は前提が強ければ結論も強い。", "帰納は観察から仮説を育てる。", "実務では両者を往復することが多い。"]
        ),
        ShowcaseNodeSpec(
            category: .humanScience,
            language: .zhHant,
            title: "睡眠週期與記憶鞏固",
            content: "比較慢波睡眠與 REM 睡眠在記憶鞏固中的角色，並整理睡眠剝奪如何影響學習表現、專注力與情緒調節。",
            webTitle: "Sleep and memory",
            webURL: "https://www.sleepfoundation.org/how-sleep-works/why-do-we-need-sleep",
            noteTitle: "學習提醒",
            noteBody: "人體科學類別可以用這筆資料展示健康與學習之間的連動。",
            fileKind: .image,
            attachmentTitle: "睡眠整理卡",
            attachmentBody: "從睡眠階段到記憶鞏固，一張圖看學習恢復的關鍵。",
            accentColor: UIColor(red: 0.86, green: 0.41, blue: 0.52, alpha: 1),
            bullets: ["慢波睡眠與事實記憶關聯較強。", "REM 睡眠與情緒與程序學習相關。", "睡眠不足會直接壓低學習表現。"]
        ),
        ShowcaseNodeSpec(
            category: .humanScience,
            language: .en,
            title: "Vaccine Response and Immune Memory",
            content: "Explains how antigen exposure, B-cell selection, and memory cell formation create a faster and more specific immune response after future exposure.",
            webTitle: "CDC Vaccines and Immunization",
            webURL: "https://www.cdc.gov/vaccines/index.html",
            noteTitle: "Study note",
            noteBody: "A clear human-science example that stays educational rather than clinical.",
            fileKind: .pdf,
            attachmentTitle: "Immune Memory Brief",
            attachmentBody: "A one-page summary of antigen exposure, selection, and memory response.",
            accentColor: UIColor(red: 0.82, green: 0.36, blue: 0.42, alpha: 1),
            bullets: ["Initial exposure trains recognition pathways.", "Memory cells support faster later responses.", "Specificity improves with selection and maturation."]
        ),
        ShowcaseNodeSpec(
            category: .humanScience,
            language: .ja,
            title: "姿勢制御と前庭系",
            content: "視覚、体性感覚、前庭感覚がどのように統合されて姿勢安定を支えるかを整理し、バランス障害の理解にもつなげる知識点。",
            webTitle: "Vestibular system",
            webURL: "https://en.wikipedia.org/wiki/Vestibular_system",
            noteTitle: "整理メモ",
            noteBody: "身体科学の中で、感覚統合の面白さが伝わりやすいテーマ。",
            fileKind: .image,
            attachmentTitle: "感覚統合カード",
            attachmentBody: "視覚・体性感覚・前庭系の役割分担を簡潔に整理。",
            accentColor: UIColor(red: 0.93, green: 0.48, blue: 0.50, alpha: 1),
            bullets: ["三つの感覚系が姿勢安定を支える。", "一つが乱れると補償が必要になる。", "臨床評価では統合の偏りを見る。"]
        ),
        ShowcaseNodeSpec(
            category: .socialScience,
            language: .zhHant,
            title: "行為經濟學中的預設效應",
            content: "說明預設選項如何改變決策成本與行為傾向，並以器官捐贈、退休儲蓄與產品設定為例，分析選擇架構的力量。",
            webTitle: "Behavioural economics",
            webURL: "https://www.behaviouralinsights.co.uk/",
            noteTitle: "案例筆記",
            noteBody: "社會科學類的經典題材，適合呈現政策與行為設計的關聯。",
            fileKind: .pdf,
            attachmentTitle: "預設效應摘要",
            attachmentBody: "以器官捐贈與退休儲蓄案例快速理解預設設計的影響。",
            accentColor: UIColor(red: 0.94, green: 0.71, blue: 0.28, alpha: 1),
            bullets: ["預設值會降低改變設定的行動成本。", "選擇架構會影響決策結果。", "設計需兼顧倫理與透明度。"]
        ),
        ShowcaseNodeSpec(
            category: .socialScience,
            language: .en,
            title: "Media Framing in Election Coverage",
            content: "Shows how repeated framing shifts what audiences notice, compare, and remember in election reporting, even when the underlying facts remain constant.",
            webTitle: "Media bias",
            webURL: "https://en.wikipedia.org/wiki/Media_bias",
            noteTitle: "Observation note",
            noteBody: "Works well in screenshots because it is readable and clearly belongs to social science.",
            fileKind: .image,
            attachmentTitle: "Framing Snapshot",
            attachmentBody: "A visual note on how emphasis, contrast, and repetition shape public interpretation.",
            accentColor: UIColor(red: 0.96, green: 0.63, blue: 0.22, alpha: 1),
            bullets: ["Framing changes what feels important.", "Repeated emphasis shapes memory and comparison.", "Headline choices can redirect interpretation."]
        ),
        ShowcaseNodeSpec(
            category: .socialScience,
            language: .ja,
            title: "地域コミュニティと防災協働",
            content: "自治体、学校、住民組織、企業がどのように連携すると災害時の初動と復旧が強くなるかを整理し、平時の信頼形成の重要性も示す。",
            webTitle: "内閣府 防災情報",
            webURL: "https://www.bousai.go.jp/",
            noteTitle: "現場メモ",
            noteBody: "社会科学の中でも、公共政策と地域連携を結びつけやすいテーマ。",
            fileKind: .pdf,
            attachmentTitle: "協働防災メモ",
            attachmentBody: "平時の関係構築と災害時の役割分担を一枚に整理。",
            accentColor: UIColor(red: 0.89, green: 0.68, blue: 0.23, alpha: 1),
            bullets: ["平時の連携が初動を左右する。", "役割分担が明確だと復旧も速い。", "信頼形成は訓練と対話で育つ。"]
        )
    ]
}
