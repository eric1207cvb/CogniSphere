import SwiftUI
import SwiftData
import UIKit

private struct ImportImageRoute: Identifiable {
    let sourceType: UIImagePickerController.SourceType
    let recognitionMode: ImportRecognitionMode

    var id: String {
        "\(sourceType.rawValue)-\(recognitionMode.rawValue)"
    }
}

private struct AddNodeRoute: Identifiable {
    let id = UUID()
    let category: KnowledgeCategory?
}

private struct LegalRoute: Identifiable {
    let id = UUID()
    let document: LegalDocumentKind
}

struct ContentView: View {
    @Query(sort: \KnowledgeLibrary.createdAt, order: .reverse) private var allLibraries: [KnowledgeLibrary]
    @Query(sort: \KnowledgeNode.createdAt, order: .reverse) private var allNodes: [KnowledgeNode]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var libraryStore: KnowledgeLibraryStore
    @EnvironmentObject private var persistenceDiagnostics: PersistenceDiagnosticsStore
    @EnvironmentObject private var regionUI: RegionUIStore
    @EnvironmentObject private var subscriptionAccess: SubscriptionAccessController

    private static let graphNodeLimit = 150

    init() {}
    
    // 控制相機與載入狀態
    @State private var imageImportRoute: ImportImageRoute?
    @State private var inputImage: UIImage?
    @State private var pendingImportMode: ImportRecognitionMode = .smartScan
    @State private var isAnalyzing = false
    @State private var addNodeRoute: AddNodeRoute?
    @State private var pendingImportPreview: KnowledgeImportPreview?
    @State private var pendingImportImage: UIImage?
    @State private var importAlertMessage: String?
    @State private var exportPackage: KnowledgeExportPackage?
    @State private var showLibrarySheet = false
    @State private var legalRoute: LegalRoute?

    private var graphNodes: [KnowledgeNode] {
        Array(filteredNodes.prefix(Self.graphNodeLimit))
    }

    private var filteredNodes: [KnowledgeNode] {
        guard let selectedLibrary = libraryStore.selectedLibrary else { return allNodes }
        return allNodes.filter { effectiveLibraryID(for: $0) == selectedLibrary.id }
    }

    private var nodeCountsByLibrary: [String: Int] {
        Dictionary(grouping: allNodes, by: effectiveLibraryID(for:)).mapValues(\.count)
    }

    private var selectedLibraryLabel: String {
        libraryStore.selectedLibrary.map {
            KnowledgeLibraryStore.displayName(for: $0, region: regionUI.region)
        } ?? regionUI.copy.libraryTitle
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 1. 底層的 3D 知識星空
                InteractiveGraphView(
                    nodes: graphNodes,
                    totalNodeCount: filteredNodes.count,
                    onSelectCategory: { category in
                        presentAddNode(category: category)
                    }
                )
                
                // 2. 頂層的 CogniSphere 概念載入畫面
                if isAnalyzing {
                    KnowledgeExtractionLoadingView()
                        .transition(.opacity.animation(.easeInOut(duration: 0.3))) // 平滑淡入淡出
                        .zIndex(1) // 確保載入畫面蓋在畫布上方
                }

                VStack {
                    HStack {
                        Button {
                            showLibrarySheet = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(selectedLibraryLabel)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    if libraryStore.isViewingArchivedLibrary {
                                        Text(regionUI.copy.reviewing)
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(regionUI.theme.chipFill))
                                            .foregroundStyle(regionUI.theme.chipText)
                                    }
                                }

                                Text(regionUI.copy.nodeCountText(filteredNodes.count))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(regionUI.theme.card.opacity(0.96))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(regionUI.theme.outline.opacity(0.7), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    HStack {
                        Spacer()

                        Button {
                            subscriptionAccess.presentPaywall()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: subscriptionAccess.isSubscriber ? "checkmark.seal.fill" : "sparkles")
                                    .font(.caption.weight(.semibold))
                                Text(subscriptionAccess.quotaStatusLabel(for: regionUI.region))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(subscriptionAccess.isSubscriber ? regionUI.theme.chipText : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(subscriptionAccess.isSubscriber ? regionUI.theme.chipFill : regionUI.theme.accent)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    Spacer()
                }
            }
            .background(regionUI.theme.canvas.ignoresSafeArea())
            .navigationTitle(regionUI.copy.appTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    languageSwitcher
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            presentImporter(sourceType: .camera)
                        } label: {
                            Label(regionUI.copy.takePhoto, systemImage: "camera")
                        }

                        Button {
                            presentImporter(sourceType: .photoLibrary)
                        } label: {
                            Label(regionUI.copy.pickPhoto, systemImage: "photo.on.rectangle")
                        }

                        Divider()

                        Button {
                            exportAllKnowledge()
                        } label: {
                            Label(regionUI.copy.exportAllKnowledge, systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "camera.shutter.button.fill")
                            .font(.title2)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { presentAddNode() }) {
                        Image(systemName: "plus")
                            .font(.title3)
                    }
                }
            }
            .sheet(item: $imageImportRoute) { route in
                ImagePicker(image: $inputImage, sourceType: route.sourceType)
            }
            .sheet(item: $addNodeRoute) { route in
                AddNodeView(initialCategory: route.category)
            }
            .sheet(isPresented: $showLibrarySheet) {
                KnowledgeLibrarySheet(
                    libraries: libraryStore.visibleLibraries,
                    activeLibraryID: libraryStore.activeLibraryID,
                    selectedLibraryID: libraryStore.selectedLibraryID,
                    counts: nodeCountsByLibrary,
                    onSelect: { libraryStore.selectLibrary(id: $0) },
                    onRename: { id, name in
                        do {
                            try libraryStore.renameLibrary(
                                id: id,
                                to: name,
                                modelContext: modelContext,
                                libraries: allLibraries
                            )
                        } catch {
                            importAlertMessage = localizedLibraryRenameFailure()
                        }
                    },
                    onExport: exportLibrary,
                    onArchiveCurrent: archiveCurrentKnowledgeLibrary
                )
            }
            .sheet(item: $exportPackage) { package in
                DirectoryExportPicker(directoryURL: package.directoryURL) { exported in
                    exportPackage = nil
                    importAlertMessage = exported
                        ? exportOpenedMessage(for: package.displayName)
                        : nil
                }
            }
            .sheet(item: $pendingImportPreview) { preview in
                KnowledgeImportReviewView(
                    preview: preview,
                    onCancel: {
                        pendingImportPreview = nil
                        pendingImportImage = nil
                    },
                    onRequestOCR: pendingImportImage.map { image in
                        {
                            guard await MainActor.run(body: {
                                subscriptionAccess.authorize(.additionalOCR)
                            }) else {
                                return nil
                            }
                            do {
                                return try await KnowledgeExtractionService.shared.prepareReferenceImageOCR(image: image)
                            } catch {
                                await MainActor.run {
                                    handleProtectedServiceError(error, feature: .additionalOCR)
                                }
                                return nil
                            }
                        }
                    },
                    onConfirm: { selected, ocrResult in
                        commitImportSelection(selected, from: preview, supplementalTextReference: ocrResult)
                    }
                )
            }
            .sheet(item: $legalRoute) { route in
                LegalCenterView(initialDocument: route.document)
            }
            .alert(regionUI.copy.importResultTitle, isPresented: Binding(
                get: { importAlertMessage != nil },
                set: { if !$0 { importAlertMessage = nil } }
            )) {
                Button(regionUI.copy.ok, role: .cancel) {}
            } message: {
                Text(importAlertMessage ?? "")
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                legalFooter
            }
            // 監聽圖片選擇，一旦拍照或選取完成就呼叫 AI
            .onChange(of: inputImage) { oldImage, newImage in
                if let image = newImage {
                    startAIAnalysis(image: image)
                }
            }
            .task {
                do {
                    try libraryStore.bootstrapIfNeeded(modelContext: modelContext, libraries: allLibraries)
                } catch {
                    importAlertMessage = localizedLibraryBootstrapFailure()
                }
                libraryStore.sync(with: allLibraries)
                do {
                    try migrateLegacyNodesIfNeeded()
                } catch {
                    importAlertMessage = localizedLegacyMigrationFailure()
                }
            }
            .onChange(of: allLibraries) { _, newLibraries in
                libraryStore.sync(with: newLibraries)
                do {
                    try migrateLegacyNodesIfNeeded()
                } catch {
                    importAlertMessage = localizedLegacyMigrationFailure()
                }
            }
        }
    }

    private var legalFooter: some View {
        VStack(spacing: 0) {
            Button {
                legalRoute = LegalRoute(document: .privacy)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))

                    VStack(spacing: 2) {
                        Text(LegalContentProvider.legalCenterTitle(for: regionUI.region))
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Text(LegalContentProvider.legalCenterSubtitle(for: regionUI.region))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(regionUI.theme.chipText)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(regionUI.theme.card.opacity(0.98))
                )
                .overlay(
                    Capsule()
                        .stroke(regionUI.theme.outline.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(regionUI.theme.canvas.opacity(0.96))
                .overlay(alignment: .top) {
                    Divider().opacity(0.2)
                }
        )
    }

    private var languageSwitcher: some View {
        Menu {
            Button {
                regionUI.setRegionOverride(nil)
            } label: {
                Label(automaticLanguageLabel, systemImage: regionUI.usesAutomaticRegion ? "checkmark.circle.fill" : "iphone.gen3")
            }

            Divider()

            ForEach(SupportedRegionUI.allCases) { region in
                Button {
                    regionUI.setRegionOverride(region)
                } label: {
                    Label(languageOptionTitle(for: region), systemImage: regionUI.region == region && !regionUI.usesAutomaticRegion ? "checkmark.circle.fill" : "globe")
                }
            }
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(regionUI.theme.accentSoft)
                        .frame(width: 24, height: 24)

                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(regionUI.theme.accent)
                }

                Text(languageSwitcherBadge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.2)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(regionUI.theme.chipText)
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(regionUI.theme.card.opacity(0.97))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(regionUI.theme.outline.opacity(0.72), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, y: 3)
        }
    }

    private var languageSwitcherBadge: String {
        if regionUI.usesAutomaticRegion {
            return automaticLanguageShortLabel
        }
        return languageOptionShortTitle(for: regionUI.region)
    }

    private var automaticLanguageLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "跟隨 Apple 裝置自動切換"
        case .unitedStates:
            return "Match Apple device automatically"
        case .japan:
            return "Appleデバイスに合わせて自動切替"
        }
    }

    private var automaticLanguageShortLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "自動"
        case .unitedStates:
            return "Auto"
        case .japan:
            return "自動"
        }
    }

    private func languageOptionTitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "台灣繁體中文"
        case .unitedStates:
            return "English (US)"
        case .japan:
            return "日本語"
        }
    }

    private func languageOptionShortTitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "繁中"
        case .unitedStates:
            return "EN"
        case .japan:
            return "日本語"
        }
    }

    private func startAIAnalysis(image: UIImage) {
        guard canMutateKnowledge() else {
            inputImage = nil
            pendingImportImage = nil
            return
        }
        guard subscriptionAccess.authorize(.smartScan) else {
            inputImage = nil
            pendingImportImage = nil
            return
        }

        withAnimation {
            isAnalyzing = true
        }
        
        Task {
            do {
                let existingTitles = await loadKnowledgeTitleSnapshot(using: modelContext)
                if let preview = try await KnowledgeExtractionService.shared.prepareNoteImageImport(
                    image: image,
                    mode: pendingImportMode,
                    existingTitles: existingTitles
                ) {
                    await MainActor.run {
                        withAnimation { isAnalyzing = false }
                        inputImage = nil
                        pendingImportImage = image
                        if !preview.hasReviewDetails {
                            pendingImportImage = nil
                            importAlertMessage = localizedImportMiss()
                        } else {
                            pendingImportPreview = preview
                        }
                    }
                } else {
                    await MainActor.run {
                        withAnimation { isAnalyzing = false }
                        inputImage = nil
                        pendingImportImage = nil
                        importAlertMessage = localizedImportAnalysisFailure()
                    }
                }
            } catch {
                print("解析失敗: \(error)")
                await MainActor.run {
                    inputImage = nil
                    pendingImportImage = nil
                    withAnimation { isAnalyzing = false }
                    if !handleProtectedServiceError(error, feature: .smartScan) {
                        importAlertMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func presentImporter(sourceType: UIImagePickerController.SourceType, mode: ImportRecognitionMode = .smartScan) {
        guard canMutateKnowledge() else { return }
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            if sourceType == .camera {
                importAlertMessage = regionUI.copy.cameraUnavailableMessage
            } else {
                importAlertMessage = localizedPhotoLibraryUnavailable()
            }
            return
        }

        pendingImportMode = mode
        imageImportRoute = ImportImageRoute(sourceType: sourceType, recognitionMode: mode)
    }

    private func presentAddNode(category: KnowledgeCategory? = nil) {
        guard canMutateKnowledge() else { return }
        addNodeRoute = AddNodeRoute(category: category)
    }

    private func canMutateKnowledge() -> Bool {
        guard persistenceDiagnostics.isPersistentStoreAvailable else {
            importAlertMessage = persistenceDiagnostics.blockedMutationMessage(for: regionUI.region)
            return false
        }
        guard !libraryStore.isViewingArchivedLibrary else {
            importAlertMessage = localizedArchivedLibraryMutationMessage()
            return false
        }
        return true
    }

    @MainActor
    private func handleProtectedServiceError(_ error: Error, feature: PremiumFeature) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == "KnowledgeExtractionService",
              [402, 403, 429].contains(nsError.code) else {
            return false
        }

        if [402, 429].contains(nsError.code) {
            subscriptionAccess.markQuotaExhausted()
        }
        subscriptionAccess.presentPaywall(for: feature)
        importAlertMessage = nsError.localizedDescription
        return true
    }

    private func commitImportSelection(
        _ selected: [KnowledgeImportCandidate],
        from preview: KnowledgeImportPreview,
        supplementalTextReference: ReferenceImageOCRResult?
    ) {
        guard canMutateKnowledge() else {
            pendingImportPreview = nil
            pendingImportImage = nil
            return
        }
        let currentNodeCount = nodeCountsByLibrary[libraryStore.activeLibraryID] ?? 0

        Task {
            do {
                let saveResult = try await KnowledgeExtractionService.shared.saveSelectedCandidates(
                    selected,
                    preview: preview,
                    modelContext: modelContext,
                    library: libraryStore.activeLibrary ?? KnowledgeLibraryRecord(
                        id: UUID().uuidString,
                        name: regionUI.copy.defaultActiveLibraryName,
                        createdAt: Date(),
                        archivedAt: nil
                    ),
                    libraryStore: libraryStore,
                    startingNodeCount: currentNodeCount,
                    supplementalTextReference: supplementalTextReference
                )
                await MainActor.run {
                    pendingImportPreview = nil
                    pendingImportImage = nil
                    importAlertMessage = saveResult.insertedCount > 0
                        ? localizedInsertedCountMessage(
                            saveResult.insertedCount,
                            autoArchived: saveResult.didAutoArchive
                        )
                        : localizedNoNewEntriesMessage()
                }
            } catch {
                await MainActor.run {
                    pendingImportPreview = nil
                    pendingImportImage = nil
                    importAlertMessage = localizedSaveLibraryFailure()
                }
            }
        }
    }

    private func exportAllKnowledge() {
        guard !allNodes.isEmpty else {
            importAlertMessage = localizedNoExportableEntries()
            return
        }

        do {
            exportPackage = try KnowledgeExportService.buildExportPackage(for: allNodes)
        } catch {
            importAlertMessage = localizedExportPrepareFailure()
        }
    }

    private func exportLibrary(_ libraryID: String) {
        guard let library = libraryStore.libraries.first(where: { $0.id == libraryID }) else {
            importAlertMessage = localizedExportPrepareFailure()
            return
        }

        let libraryNodes = allNodes.filter { effectiveLibraryID(for: $0) == libraryID }
        guard !libraryNodes.isEmpty else {
            importAlertMessage = localizedNoExportableEntries()
            return
        }

        do {
            exportPackage = try KnowledgeExportService.buildExportPackage(
                for: libraryNodes,
                libraryName: KnowledgeLibraryStore.displayName(for: library, region: regionUI.region)
            )
            showLibrarySheet = false
        } catch {
            importAlertMessage = localizedExportPrepareFailure()
        }
    }

    private func archiveCurrentKnowledgeLibrary() {
        guard canMutateKnowledge() else { return }
        do {
            try migrateLegacyNodesIfNeeded()
            _ = try libraryStore.archiveCurrentLibraryAndCreateNew(
                modelContext: modelContext,
                libraries: allLibraries
            )
            showLibrarySheet = false
            importAlertMessage = localizedArchiveCompletedMessage()
        } catch {
            importAlertMessage = localizedArchiveFailure()
        }
    }

    private func migrateLegacyNodesIfNeeded() throws {
        guard let activeLibrary = libraryStore.activeLibrary else { return }
        let legacyNodes = allNodes.filter { node in
            let rawID = node.libraryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return rawID.isEmpty
        }

        guard !legacyNodes.isEmpty else { return }

        let originalAssignments = legacyNodes.map { node in
            (node: node, libraryID: node.libraryID, libraryName: node.libraryName)
        }

        for node in legacyNodes {
            node.libraryID = activeLibrary.id
            node.libraryName = activeLibrary.name
        }

        do {
            try modelContext.save()
        } catch {
            for assignment in originalAssignments {
                assignment.node.libraryID = assignment.libraryID
                assignment.node.libraryName = assignment.libraryName
            }
            throw error
        }
    }

    private func effectiveLibraryID(for node: KnowledgeNode) -> String {
        let rawID = node.libraryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawID.isEmpty {
            return rawID
        }
        return libraryStore.activeLibraryID
    }

    private func exportOpenedMessage(for displayName: String) -> String {
        switch regionUI.region {
        case .taiwan:
            return "已開啟匯出介面：\(displayName)"
        case .unitedStates:
            return "Export sheet opened: \(displayName)"
        case .japan:
            return "書き出し画面を開きました：\(displayName)"
        }
    }

    private func localizedImportMiss() -> String {
        switch regionUI.region {
        case .taiwan:
            return "這次沒有辨識出可直接加入的知識項目。"
        case .unitedStates:
            return "No importable knowledge entries were recognized this time."
        case .japan:
            return "今回は直接取り込める知識項目を認識できませんでした。"
        }
    }

    private func localizedImportAnalysisFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "AI 目前無法從這張圖判斷出可加入的知識項目。請讓想辨識的主體置中並拍清楚一些。"
        case .unitedStates:
            return "AI could not identify importable knowledge entries from this image. Center the subject and capture it more clearly."
        case .japan:
            return "この画像から取り込める知識項目を AI で判断できませんでした。認識したい主題を中央に置き、もう少し鮮明に撮影してください。"
        }
    }

    private func localizedLibraryBootstrapFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "無法初始化知識庫，請重新啟動 App 後再試。"
        case .unitedStates:
            return "The knowledge library could not be initialized. Restart the app and try again."
        case .japan:
            return "知識ライブラリを初期化できませんでした。App を再起動してもう一度お試しください。"
        }
    }

    private func localizedLibraryRenameFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "知識庫名稱未能儲存，請再試一次。"
        case .unitedStates:
            return "The library name could not be saved. Please try again."
        case .japan:
            return "知識ライブラリ名を保存できませんでした。もう一度お試しください。"
        }
    }

    private func localizedArchiveFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "封存知識庫失敗，請再試一次。"
        case .unitedStates:
            return "Failed to archive the knowledge library. Please try again."
        case .japan:
            return "知識ライブラリのアーカイブに失敗しました。もう一度お試しください。"
        }
    }

    private func localizedLegacyMigrationFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "舊知識點整理失敗，請重新啟動 App 後再試。"
        case .unitedStates:
            return "Legacy knowledge entries could not be reorganized. Restart the app and try again."
        case .japan:
            return "旧知識項目の整理に失敗しました。App を再起動してもう一度お試しください。"
        }
    }

    private func localizedPhotoLibraryUnavailable() -> String {
        switch regionUI.region {
        case .taiwan:
            return "目前無法開啟相簿。"
        case .unitedStates:
            return "Photos cannot be opened right now."
        case .japan:
            return "現在写真ライブラリを開けません。"
        }
    }

    private func localizedArchivedLibraryMutationMessage() -> String {
        switch regionUI.region {
        case .taiwan:
            return "目前正在複習封存知識網絡。請先切回「\(regionUI.copy.defaultActiveLibraryName)」再新增知識點。"
        case .unitedStates:
            return "You are reviewing an archived knowledge network. Switch back to the active library before adding entries."
        case .japan:
            return "現在は保存済み知識ネットワークを復習中です。知識点を追加する前に現在のライブラリへ戻してください。"
        }
    }

    private func localizedInsertedCountMessage(_ count: Int, autoArchived: Bool) -> String {
        let base: String
        switch regionUI.region {
        case .taiwan:
            base = "已加入 \(count) 個知識項目。"
        case .unitedStates:
            base = "\(count) knowledge entries added."
        case .japan:
            base = "\(count) 件の知識項目を追加しました。"
        }

        guard autoArchived else { return base }

        switch regionUI.region {
        case .taiwan:
            return "\(base) 目前知識庫已達 \(KnowledgeLibraryStore.autoArchiveNodeLimit) 筆，系統已自動封存並建立新的知識庫。"
        case .unitedStates:
            return "\(base) The active library reached \(KnowledgeLibraryStore.autoArchiveNodeLimit) entries, so it was archived automatically and a new library was created."
        case .japan:
            return "\(base) 現在のライブラリが \(KnowledgeLibraryStore.autoArchiveNodeLimit) 件に達したため、自動で保存され、新しいライブラリを作成しました。"
        }
    }

    private func localizedNoNewEntriesMessage() -> String {
        switch regionUI.region {
        case .taiwan:
            return "沒有新的知識項目被加入。"
        case .unitedStates:
            return "No new knowledge entries were added."
        case .japan:
            return "新しい知識項目は追加されませんでした。"
        }
    }

    private func localizedSaveLibraryFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "寫入知識庫失敗，請再試一次。"
        case .unitedStates:
            return "Failed to save to the knowledge library. Please try again."
        case .japan:
            return "知識ライブラリへの保存に失敗しました。もう一度お試しください。"
        }
    }

    private func localizedNoExportableEntries() -> String {
        switch regionUI.region {
        case .taiwan:
            return "目前沒有可匯出的知識點。"
        case .unitedStates:
            return "There are no knowledge entries to export yet."
        case .japan:
            return "書き出せる知識点がまだありません。"
        }
    }

    private func localizedExportPrepareFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "匯出準備失敗，請再試一次。"
        case .unitedStates:
            return "Failed to prepare the export. Please try again."
        case .japan:
            return "書き出しの準備に失敗しました。もう一度お試しください。"
        }
    }

    private func localizedArchiveCompletedMessage() -> String {
        switch regionUI.region {
        case .taiwan:
            return "已封存目前知識網絡，新的知識庫已建立。"
        case .unitedStates:
            return "The current knowledge network was archived and a new library has been created."
        case .japan:
            return "現在の知識ネットワークを保存し、新しいライブラリを作成しました。"
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [KnowledgeLibrary.self, KnowledgeNode.self, KnowledgeReference.self], inMemory: true)
        .environmentObject(KnowledgeLibraryStore())
}
