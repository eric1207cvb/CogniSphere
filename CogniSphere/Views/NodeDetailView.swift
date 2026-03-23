import SwiftUI
import SwiftData
import PDFKit
import SafariServices

private enum AttachmentPreview: Identifiable {
    case image(KnowledgeReference)
    case pdf(KnowledgeReference)
    case text(title: String, content: String)
    case web(title: String, urlString: String)

    var id: String {
        switch self {
        case let .image(reference), let .pdf(reference):
            return reference.id.uuidString
        case let .text(title, content):
            return "\(title)|\(content.prefix(40))"
        case let .web(title, urlString):
            return "\(title)|\(urlString)"
        }
    }

    var title: String {
        switch self {
        case let .image(reference), let .pdf(reference):
            return reference.title
        case let .text(title, _), let .web(title, _):
            return title
        }
    }
}

private enum ImagePickerRoute: Identifiable {
    case photoLibrary
    case camera

    var id: String {
        switch self {
        case .photoLibrary:
            return "photoLibrary"
        case .camera:
            return "camera"
        }
    }

    var sourceType: UIImagePickerController.SourceType {
        switch self {
        case .photoLibrary:
            return .photoLibrary
        case .camera:
            return .camera
        }
    }
}

private enum AttachmentProcessingState {
    case imageOCR
    case pdfSummary

    var message: String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            switch self {
            case .imageOCR: return "正在整理照片文字"
            case .pdfSummary: return "正在為 PDF 生成摘要"
            }
        case .unitedStates:
            switch self {
            case .imageOCR: return "Processing image text"
            case .pdfSummary: return "Generating PDF summary"
            }
        case .japan:
            switch self {
            case .imageOCR: return "画像の文字を整理しています"
            case .pdfSummary: return "PDFの要約を生成しています"
            }
        }
    }
}

struct ReferenceSummaryDisplay {
    let label: String
    let body: String
    let verificationNote: String?
    let isOutdatedLocalization: Bool
}

struct NodeDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var libraryStore: KnowledgeLibraryStore
    @EnvironmentObject private var persistenceDiagnostics: PersistenceDiagnosticsStore
    @EnvironmentObject private var regionUI: RegionUIStore
    @EnvironmentObject private var subscriptionAccess: SubscriptionAccessController
    @Bindable var node: KnowledgeNode
    
    // 🎙️ 錄音與播放控制器
    @StateObject private var audioRecorder = AudioRecorderService()
    @StateObject private var audioPlayer = AudioPlayerService()
    
    // 追蹤現在正在播放哪一個資源
    @State private var playingReferenceID: UUID?
    
    // 彈出視窗控制
    @State private var showWebLinkSheet = false
    @State private var showTextSheet = false
    @State private var showEditNodeSheet = false
    
    // Picker 狀態
    @State private var showDocumentPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var imagePickerRoute: ImagePickerRoute?
    
    @State private var selectedImage: UIImage?
    @State private var attachmentPreview: AttachmentPreview?
    @State private var processingState: AttachmentProcessingState?
    @State private var attachmentActionMessage: String?
    @State private var knowledgeDraftFromReference: KnowledgeReference?
    
    // 錄音紅點閃爍動畫狀態
    @State private var isBlinking = false

    private var webReferences: [KnowledgeReference] {
        (node.references ?? [])
            .filter { $0.type == .web }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var textReferences: [KnowledgeReference] {
        (node.references ?? [])
            .filter { $0.type == .text }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var attachmentReferences: [KnowledgeReference] {
        (node.references ?? [])
            .filter { $0.type != .web && $0.type != .text }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var copy: RegionCopy { regionUI.copy }

    var body: some View {
        NavigationStack {
            List {
                // 1. AI 摘要區塊
                Section(header: Text(copy.aiSummarySection)) {
                    Text(node.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                Section(header: Text(copy.webLinksSection)) {
                    if !webReferences.isEmpty {
                        ForEach(webReferences) { ref in
                            Button(action: {
                                handleReferenceTap(ref)
                            }) {
                                ReferenceRowView(reference: ref)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteWebReference)
                    } else {
                        Text(copy.noWebLinks)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
                
                // 2. 參考資料區塊
                Section(header: Text(copy.attachmentsSection)) {
                    if !attachmentReferences.isEmpty {
                        ForEach(attachmentReferences) { ref in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    Button(action: {
                                        handleReferenceTap(ref)
                                    }) {
                                        let summaryDisplay = referenceSummaryDisplay(for: ref)
                                        ReferenceRowView(
                                            reference: ref,
                                            isPlaying: (audioPlayer.isPlaying && playingReferenceID == ref.id),
                                            summaryDisplay: summaryDisplay,
                                            onImageThumbnailLongPress: ref.type == .image ? {
                                                attachmentPreview = .image(ref)
                                            } : nil
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    if shouldShowImageOCRAction(for: ref) {
                                        Button(ref.summaryOutline == nil ? copy.imageOCRAction : copy.imageOCRRefresh) {
                                            runImageReferenceOCR(for: ref)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                    } else if shouldShowPDFSummaryAction(for: ref) {
                                        Button(ref.summaryOutline == nil ? copy.pdfSummaryAction : copy.pdfSummaryRefresh) {
                                            runPDFReferenceSummary(for: ref)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }

                                if let summary = referenceSummary(for: ref) {
                                    HStack(spacing: 10) {
                                        Button {
                                            attachmentPreview = .text(
                                                title: summaryPreviewTitle(for: ref),
                                                content: summary
                                            )
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "doc.text.magnifyingglass")
                                                Text(summaryPreviewButtonTitle(for: ref))
                                                    .font(.subheadline.weight(.medium))
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                    .fill(Color(.tertiarySystemGroupedBackground))
                                            )
                                        }
                                        .buttonStyle(.plain)

                                        Button(copy.convertToKnowledgeNode) {
                                            guard canPersistChanges() else { return }
                                            knowledgeDraftFromReference = ref
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteReference)
                    } else {
                        Text(copy.noAttachments)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .italic()
                    }
                }
            }
            .navigationTitle(node.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        guard canPersistChanges() else { return }
                        showEditNodeSheet = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !audioRecorder.isRecording {
                        Menu {
                            Button(action: {
                                guard canPersistChanges() else { return }
                                showDocumentPicker = true
                            }) {
                                Label(copy.importPDF, systemImage: "doc.text")
                            }
                            
                            // 📸 雙重圖片來源選項
                            Button(action: {
                                presentImagePicker(for: .photoLibrary)
                            }) {
                                Label(copy.pickPhoto, systemImage: "photo.on.rectangle")
                            }
                            
                            Button(action: {
                                presentImagePicker(for: .camera)
                            }) {
                                Label(copy.takePhoto, systemImage: "camera")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                guard canPersistChanges() else { return }
                                showTextSheet = true
                            }) {
                                Label(copy.addTextNote, systemImage: "text.alignleft")
                            }
                            Button(action: {
                                guard canPersistChanges() else { return }
                                showWebLinkSheet = true
                            }) {
                                Label(copy.addWebLink, systemImage: "link")
                            }
                            
                            Divider()
                            
                            Button(action: startRecording) {
                                Label(copy.voiceMemo30s, systemImage: "mic")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if audioRecorder.isRecording {
                    recordingFloatingBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .overlay {
            if let processingState {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(processingState.message)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
                    )
                }
            }
        }
        .sheet(isPresented: $showWebLinkSheet) {
            WebLinkManagerSheet(
                references: webReferences,
                onAdd: { input in
                    addWebReference(from: input)
                }
            )
        }
        .sheet(isPresented: $showTextSheet) {
            TextNoteManagerSheet(
                references: textReferences,
                defaultTitle: defaultTextNoteTitle(),
                onAdd: { content in
                    addTextReference(content: content)
                }
            )
        }
        .sheet(isPresented: $showEditNodeSheet) {
            KnowledgeNodeFormSheet(
                screenTitle: copy.editKnowledgeNode,
                saveLabel: copy.save,
                initialTitle: node.title,
                initialContent: node.content,
                initialCategory: node.categoryEnum
            ) { title, content, category in
                saveNodeEdits(title: title, content: content, category: category)
            }
        }
        .alert(copy.cameraUnavailableTitle, isPresented: $showCameraUnavailableAlert) {
            Button(copy.ok, role: .cancel) {}
        } message: {
            Text(copy.cameraUnavailableMessage)
        }
        .alert(copy.attachmentResultTitle, isPresented: Binding(
            get: { attachmentActionMessage != nil },
            set: { if !$0 { attachmentActionMessage = nil } }
        )) {
            Button(copy.ok, role: .cancel) {}
        } message: {
            Text(attachmentActionMessage ?? "")
        }
        
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { attachment in
                addRealReference(
                    type: .pdf,
                    title: attachment.originalFileName,
                    payload: attachment.fileName,
                    attachmentData: attachment.data,
                    attachmentOriginalFileName: attachment.originalFileName,
                    attachmentMimeType: attachment.mimeType
                )
            } onFailure: { message in
                attachmentActionMessage = message
            }
        }
        
        .sheet(item: $imagePickerRoute) { route in
            ImagePicker(image: $selectedImage, sourceType: route.sourceType)
        }
        .sheet(item: $attachmentPreview) { preview in
            AttachmentPreviewSheet(preview: preview)
        }
        .sheet(item: $knowledgeDraftFromReference) { reference in
            KnowledgeNodeFormSheet(
                screenTitle: copy.createFromSummary,
                saveLabel: copy.addKnowledgeNode,
                initialTitle: draftTitleForReference(reference),
                initialContent: referenceSummary(for: reference) ?? "",
                initialCategory: node.categoryEnum
            ) { title, content, category in
                createKnowledgeNodeFromReferenceSummary(
                    title: title,
                    content: content,
                    category: category
                )
            }
        }
        .onChange(of: selectedImage) { oldImage, newImage in
            if let image = newImage {
                saveImageToDisk(image)
                selectedImage = nil
            }
        }
    }
    
    // MARK: - 🎨 錄音浮動列 UI 元件
    private var recordingFloatingBar: some View {
        HStack(spacing: 20) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(isBlinking ? 0.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(), value: isBlinking)
                .onAppear { isBlinking = true }
            
            Text(audioRecorder.formattedRecordingDuration)
                .font(.system(.title3, design: .monospaced))
                .bold()
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                audioRecorder.stopRecording()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
    
    // MARK: - 核心操作邏輯

    private func presentImagePicker(for sourceType: UIImagePickerController.SourceType) {
        guard canPersistChanges() else { return }
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            if sourceType == .camera {
                showCameraUnavailableAlert = true
            }
            return
        }

        imagePickerRoute = sourceType == .camera ? .camera : .photoLibrary
    }
    
    // 📸 將圖片壓縮並儲存進沙盒，標題加上時間戳記
    private func saveImageToDisk(_ image: UIImage) {
        defer { imagePickerRoute = nil }
        guard canPersistChanges() else { return }

        do {
            let attachment = try AttachmentStorageController.saveImage(image)
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd HH:mm"
            let title = imagePickerRoute == .camera ? "\(copy.takePhoto) \(formatter.string(from: Date()))" : copy.pickPhoto
            addRealReference(
                type: .image,
                title: title,
                payload: attachment.fileName,
                attachmentData: attachment.data,
                attachmentOriginalFileName: attachment.originalFileName,
                attachmentMimeType: attachment.mimeType
            )
        } catch {
            print("❌ 圖片儲存失敗: \(error)")
            attachmentActionMessage = AttachmentStorageController.userFacingErrorMessage(for: error, action: copy.pickPhoto)
        }
    }

    private func runImageReferenceOCR(for reference: KnowledgeReference) {
        guard canPersistChanges() else { return }
        guard subscriptionAccess.authorize(.referenceImageOCR) else { return }

        guard let image = AttachmentStorageController.image(for: reference) else {
            attachmentActionMessage = copy.imageMissingForOCR
            return
        }

        processingState = .imageOCR
        Task {
            do {
                let result = try await KnowledgeExtractionService.shared.prepareReferenceImageOCR(image: image)
                await MainActor.run {
                    processingState = nil
                    if let result {
                        updateReferenceSummary(for: reference, summary: result.content, verificationNote: result.verificationNote)
                    } else {
                        attachmentActionMessage = copy.imageOCRRejected
                    }
                }
            } catch {
                await MainActor.run {
                    processingState = nil
                    if !handleProtectedServiceError(error, feature: .referenceImageOCR) {
                        attachmentActionMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func runPDFReferenceSummary(for reference: KnowledgeReference) {
        guard canPersistChanges() else { return }
        guard subscriptionAccess.authorize(.pdfSummary) else { return }

        guard let fileURL = AttachmentStorageController.restoredLocalFileURL(for: reference) else {
            attachmentActionMessage = copy.pdfMissingForSummary
            return
        }

        processingState = .pdfSummary
        Task {
            do {
                let result = try await KnowledgeExtractionService.shared.preparePDFReferenceSummary(fileURL: fileURL)
                await MainActor.run {
                    processingState = nil
                    if let result {
                        updateReferenceSummary(for: reference, summary: result.content, verificationNote: result.verificationNote)
                    } else {
                        attachmentActionMessage = copy.pdfSummaryUnavailable
                    }
                }
            } catch {
                await MainActor.run {
                    processingState = nil
                    if !handleProtectedServiceError(error, feature: .pdfSummary) {
                        attachmentActionMessage = error.localizedDescription
                    }
                }
            }
        }
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
        attachmentActionMessage = nsError.localizedDescription
        return true
    }
    
    private func startRecording() {
        guard canPersistChanges() else { return }
        do {
            try AttachmentStorageController.ensureCapacity(forAdditionalBytes: AttachmentStorageController.shortAudioReservationBytes)
        } catch {
            attachmentActionMessage = AttachmentStorageController.userFacingErrorMessage(for: error, action: copy.voiceMemo30s)
            return
        }

        if audioPlayer.isPlaying {
            audioPlayer.stopAudio()
            playingReferenceID = nil
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            audioRecorder.startRecording { fileName in
                if let fileName = fileName {
                    do {
                        let attachment = try AttachmentStorageController.storedAttachment(named: fileName)
                        addRealReference(
                            type: .audio,
                            title: copy.voiceMemo30s,
                            payload: attachment.fileName,
                            attachmentData: attachment.data,
                            attachmentOriginalFileName: attachment.originalFileName,
                            attachmentMimeType: attachment.mimeType
                        )
                    } catch {
                        AttachmentStorageController.deleteStoredFileIfPresent(named: fileName)
                        attachmentActionMessage = localizedAudioMissingMessage()
                    }
                }
            }
        }
    }
    
    private func handleReferenceTap(_ reference: KnowledgeReference) {
        switch reference.type {
        case .audio:
            if audioPlayer.isPlaying && playingReferenceID == reference.id {
                audioPlayer.stopAudio()
                playingReferenceID = nil
            } else {
                guard let fileURL = AttachmentStorageController.restoredLocalFileURL(for: reference) else {
                    attachmentActionMessage = localizedAudioMissingMessage()
                    return
                }
                audioPlayer.playAudio(fileURL: fileURL)
                playingReferenceID = reference.id
            }
        case .web:
            attachmentPreview = .web(title: reference.title, urlString: reference.payload)
        case .image:
            attachmentPreview = .image(reference)
        case .pdf:
            attachmentPreview = .pdf(reference)
        case .text:
            attachmentPreview = .text(title: reference.title, content: reference.payload)
        }
    }
    
    @discardableResult
    private func addRealReference(
        type: ReferenceType,
        title: String,
        payload: String,
        attachmentData: Data? = nil,
        attachmentOriginalFileName: String? = nil,
        attachmentMimeType: String? = nil
    ) -> Bool {
        guard canPersistChanges() else {
            if type == .image || type == .pdf || type == .audio {
                AttachmentStorageController.deleteStoredFileIfPresent(named: payload)
            }
            return false
        }
        let newRef = KnowledgeReference(
            title: title,
            type: type,
            payload: payload,
            attachmentData: attachmentData,
            attachmentOriginalFileName: attachmentOriginalFileName,
            attachmentMimeType: attachmentMimeType
        )
        let previousReferences = node.references ?? []
        if node.references == nil { node.references = [] }
        node.references?.append(newRef)

        do {
            try context.save()
            return true
        } catch {
            node.references = previousReferences.isEmpty ? nil : previousReferences
            if type == .image || type == .pdf || type == .audio {
                AttachmentStorageController.deleteStoredFileIfPresent(named: payload)
            }
            attachmentActionMessage = localizedReferenceSaveFailure()
            return false
        }
    }

    private func updateReferenceSummary(for reference: KnowledgeReference, summary: String, verificationNote: String?) {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        reference.summaryOutline = trimmed
        reference.summaryVerificationNote = verificationNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        reference.summaryLocalizationRaw = regionUI.region.rawValue
        reference.summaryUpdatedAt = Date()

        do {
            try context.save()
            attachmentActionMessage = copy.summaryUpdated
        } catch {
            attachmentActionMessage = copy.summaryUpdateFailed
        }
    }

    private func referenceSummary(for reference: KnowledgeReference) -> String? {
        let trimmed = reference.summaryOutline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        guard !hasSummaryLocalizationMismatch(for: reference) else { return nil }
        return trimmed
    }

    private func referenceSummaryDisplay(for reference: KnowledgeReference) -> ReferenceSummaryDisplay? {
        let trimmed = reference.summaryOutline?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }

        let label = summaryPreviewTitle(for: reference)
        if hasSummaryLocalizationMismatch(for: reference) {
            return ReferenceSummaryDisplay(
                label: label,
                body: summaryLocalizationMismatchMessage(for: reference),
                verificationNote: nil,
                isOutdatedLocalization: true
            )
        }

        let verificationNote = reference.summaryVerificationNote?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ReferenceSummaryDisplay(
            label: label,
            body: trimmed,
            verificationNote: verificationNote?.isEmpty == false ? verificationNote : nil,
            isOutdatedLocalization: false
        )
    }

    private func summaryPreviewTitle(for reference: KnowledgeReference) -> String {
        switch reference.type {
        case .image:
            return copy.ocrSummaryLabel
        case .pdf:
            return copy.pdfSummaryLabel
        case .web, .text, .audio:
            return copy.genericSummaryLabel
        }
    }

    private func summaryPreviewButtonTitle(for reference: KnowledgeReference) -> String {
        switch reference.type {
        case .image:
            return copy.previewOCRSummary
        case .pdf:
            return copy.previewPDFSummary
        case .web, .text, .audio:
            return copy.previewSummary
        }
    }

    private func hasSummaryLocalizationMismatch(for reference: KnowledgeReference) -> Bool {
        guard reference.type == .image || reference.type == .pdf else { return false }
        if let summaryLocalizationRaw = reference.summaryLocalizationRaw,
           let summaryRegion = SupportedRegionUI(rawValue: summaryLocalizationRaw) {
            return summaryRegion != regionUI.region
        }
        guard let summary = reference.summaryOutline?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty,
              let inferredRegion = inferredSummaryRegion(for: summary) else {
            return false
        }
        return inferredRegion != regionUI.region
    }

    private func inferredSummaryRegion(for text: String) -> SupportedRegionUI? {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return nil }

        let latinCount = scalars.filter {
            CharacterSet.letters.contains($0) && $0.value < 0x024F
        }.count
        let kanaCount = scalars.filter {
            (0x3040...0x309F).contains($0.value)
                || (0x30A0...0x30FF).contains($0.value)
                || (0x31F0...0x31FF).contains($0.value)
                || (0xFF66...0xFF9D).contains($0.value)
        }.count
        let hanCount = scalars.filter {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
        }.count

        if latinCount >= max(8, scalars.count / 3) {
            return .unitedStates
        }
        if kanaCount >= 2 {
            return .japan
        }
        if hanCount >= max(4, scalars.count / 4) {
            return .taiwan
        }

        return nil
    }

    private func summaryLocalizationMismatchMessage(for reference: KnowledgeReference) -> String {
        let isOCR = reference.type == .image
        switch regionUI.region {
        case .taiwan:
            return isOCR
                ? "這份 OCR 摘要是以其他語言生成的。請點右側「更新 OCR」，重新產生目前語言版本。"
                : "這份 PDF 摘要是以其他語言生成的。請點右側「更新摘要」，重新產生目前語言版本。"
        case .unitedStates:
            return isOCR
                ? "This OCR summary was generated in another app language. Tap Refresh OCR to regenerate it in the current language."
                : "This PDF summary was generated in another app language. Tap Refresh Summary to regenerate it in the current language."
        case .japan:
            return isOCR
                ? "このOCR要約は別のアプリ言語で生成されています。右側の「OCR更新」を押して、現在の言語で再生成してください。"
                : "このPDF要約は別のアプリ言語で生成されています。右側の「要約更新」を押して、現在の言語で再生成してください。"
        }
    }

    private func draftTitleForReference(_ reference: KnowledgeReference) -> String {
        let sourceText = referenceSummary(for: reference) ?? reference.title
        return KnowledgeImportFallbackBuilder.makeDraft(
            from: sourceText,
            suggestedTitle: reference.title,
            category: node.categoryEnum
        ).title
    }

    private func createKnowledgeNodeFromReferenceSummary(
        title: String,
        content: String,
        category: KnowledgeCategory
    ) -> String? {
        guard canPersistChanges() else {
            return persistenceDiagnostics.blockedMutationMessage(for: regionUI.region)
        }
        let descriptor = FetchDescriptor<KnowledgeNode>()
        let existingNodes = (try? context.fetch(descriptor)) ?? []
        let existingTitles = Set(existingNodes.map { KnowledgeNodeCleaner.normalizedKey(for: $0.title) })
        let validation = KnowledgeNodeCleaner.validate(
            title: title,
            content: content,
            categoryRaw: category.rawValue,
            source: .manual,
            existingTitles: existingTitles
        )

        guard let draft = validation.draft else {
            return validation.rejectionReason ?? copy.createKnowledgeNodeFailed
        }

        let targetLibrary = libraryStore.activeLibrary
        let newNode = KnowledgeNode(
            title: draft.title,
            content: draft.content,
            category: draft.category,
            x: 0, y: 0, z: 0,
            libraryID: targetLibrary?.id,
            libraryName: targetLibrary?.name
        )
        context.insert(newNode)

        do {
            try context.save()
            if let targetLibrary,
               libraryStore.selectedLibraryID != targetLibrary.id {
                libraryStore.selectLibrary(id: targetLibrary.id)
                attachmentActionMessage = copy.createdFromSummarySwitched
            } else {
                attachmentActionMessage = copy.createdFromSummary
            }
            Task {
                await KnowledgeTitleIndexStore.shared.register(
                    normalizedTitles: [KnowledgeNodeCleaner.normalizedKey(for: draft.title)]
                )
            }
            return nil
        } catch {
            context.delete(newNode)
            return copy.createKnowledgeNodeFailed
        }
    }
    
    private func deleteReference(at offsets: IndexSet) {
        guard canPersistChanges() else { return }
        var referencesToDelete: [KnowledgeReference] = []
        for index in offsets {
            guard attachmentReferences.indices.contains(index) else { continue }
            let refToDelete = attachmentReferences[index]
            referencesToDelete.append(refToDelete)
            context.delete(refToDelete)
        }

        do {
            try context.save()
            referencesToDelete.forEach(deleteStoredPayloadIfNeeded(for:))
        } catch {
            attachmentActionMessage = copy.deleteAttachmentFailed
        }
    }

    private func deleteWebReference(at offsets: IndexSet) {
        guard canPersistChanges() else { return }
        var referencesToDelete: [KnowledgeReference] = []
        for index in offsets {
            guard webReferences.indices.contains(index) else { continue }
            let refToDelete = webReferences[index]
            referencesToDelete.append(refToDelete)
            context.delete(refToDelete)
        }

        do {
            try context.save()
            referencesToDelete.forEach(deleteStoredPayloadIfNeeded(for:))
        } catch {
            attachmentActionMessage = copy.deleteLinkFailed
        }
    }
    
    private func defaultTextNoteTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "文字筆記 \(formatter.string(from: node.createdAt))"
        case .unitedStates:
            return "Text Note \(formatter.string(from: node.createdAt))"
        case .japan:
            return "テキストメモ \(formatter.string(from: node.createdAt))"
        }
    }

    @discardableResult
    private func addTextReference(content: String) -> Bool {
        guard canPersistChanges() else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return addRealReference(type: .text, title: defaultTextNoteTitle(), payload: trimmed)
    }

    @discardableResult
    private func addWebReference(from rawInput: String) -> Bool {
        guard canPersistChanges() else { return false }
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        guard let url = normalizedWebURL(from: trimmed) else {
            return false
        }

        let title = url.host?.replacingOccurrences(of: "www.", with: "") ?? copy.linkDefaultTitle
        return addRealReference(type: .web, title: title, payload: url.absoluteString)
    }

    private func normalizedURLString(from input: String) -> String {
        if input.contains("://") {
            return input
        }
        return "https://\(input)"
    }

    private func normalizedWebURL(from input: String) -> URL? {
        let sanitized = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "／", with: "/")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "．", with: ".")
            .replacingOccurrences(of: "　", with: "")

        guard !sanitized.isEmpty else { return nil }

        if let detectedURL = detectedWebURL(in: sanitized) {
            return detectedURL
        }

        let normalized = normalizedURLString(from: sanitized)
        if let directURL = validatedWebURL(from: normalized) {
            return directURL
        }

        if let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let encodedURL = validatedWebURL(from: encoded) {
            return encodedURL
        }

        if let fallbackURL = fallbackConstructedWebURL(from: sanitized) {
            return fallbackURL
        }

        return nil
    }

    private func detectedWebURL(in input: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }

        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        guard let match = detector.firstMatch(in: input, options: [], range: range),
              match.range.location != NSNotFound,
              let url = match.url else {
            return nil
        }

        return validatedWebURL(from: url.absoluteString)
    }

    private func fallbackConstructedWebURL(from input: String) -> URL? {
        let body = input.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
        let pieces = body.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = pieces.first else { return nil }

        let hostCandidate = String(first)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard looksLikeDomain(hostCandidate) else { return nil }

        var components = URLComponents()
        components.scheme = "https"
        components.host = hostCandidate

        if pieces.count > 1 {
            let rawPath = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawPath.isEmpty {
                components.percentEncodedPath = "/" + (rawPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawPath)
            }
        }

        guard let absolute = components.url?.absoluteString else { return nil }
        return validatedWebURL(from: absolute)
    }

    private func validatedWebURL(from rawString: String) -> URL? {
        guard let url = URL(string: rawString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              host.rangeOfCharacter(from: .alphanumerics) != nil else {
            return nil
        }

        return url
    }

    private func localizedReferenceSaveFailure() -> String {
        switch regionUI.region {
        case .taiwan:
            return "附件儲存失敗，請再試一次。"
        case .unitedStates:
            return "The attachment could not be saved. Please try again."
        case .japan:
            return "添付を保存できませんでした。もう一度お試しください。"
        }
    }

    private func looksLikeDomain(_ host: String) -> Bool {
        guard host.contains("."), !host.contains(" "), host.count >= 4 else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func saveNodeEdits(title: String, content: String, category: KnowledgeCategory) -> String? {
        guard canPersistChanges() else {
            return persistenceDiagnostics.blockedMutationMessage(for: regionUI.region)
        }
        let normalizedTitle = KnowledgeNodeCleaner.normalizedKey(for: title)
        let currentKey = KnowledgeNodeCleaner.normalizedKey(for: node.title)

        if normalizedTitle != currentKey {
            let descriptor = FetchDescriptor<KnowledgeNode>()
            let allNodes = (try? context.fetch(descriptor)) ?? []
            let duplicateExists = allNodes.contains {
                $0.id != node.id && KnowledgeNodeCleaner.normalizedKey(for: $0.title) == normalizedTitle
            }
            if duplicateExists {
                switch RegionUIStore.runtimeRegion() {
                case .taiwan:
                    return "已存在相同標題的知識節點。"
                case .unitedStates:
                    return "A knowledge entry with the same title already exists."
                case .japan:
                    return "同じタイトルの知識点が既に存在します。"
                }
            }
        }

        let validation = KnowledgeNodeCleaner.validate(
            title: title,
            content: content,
            categoryRaw: category.rawValue,
            source: .manual,
            existingTitles: []
        )

        guard let draft = validation.draft else {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return validation.rejectionReason ?? "內容不符合知識節點規則。"
            case .unitedStates:
                return validation.rejectionReason ?? "This content does not meet the knowledge entry rules."
            case .japan:
                return validation.rejectionReason ?? "この内容は知識点のルールに合いません。"
            }
        }

        node.title = draft.title
        node.content = draft.content
        node.category = draft.category.rawValue

        do {
            try context.save()
            Task { @MainActor in
                await refreshKnowledgeTitleSnapshot(using: context)
            }
            return nil
        } catch {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "儲存節點失敗，請再試一次。"
            case .unitedStates:
                return "Failed to save the knowledge entry. Please try again."
            case .japan:
                return "知識点の保存に失敗しました。もう一度お試しください。"
            }
        }
    }

    private func shouldShowImageOCRAction(for reference: KnowledgeReference) -> Bool {
        reference.type == .image
    }

    private func shouldShowPDFSummaryAction(for reference: KnowledgeReference) -> Bool {
        reference.type == .pdf
    }

    private func localizedAudioMissingMessage() -> String {
        switch regionUI.region {
        case .taiwan:
            return "這筆語音附件目前無法在本機開啟。"
        case .unitedStates:
            return "This audio attachment is not available on this device right now."
        case .japan:
            return "この音声添付は現在この端末で開けません。"
        }
    }

    private func deleteStoredPayloadIfNeeded(for reference: KnowledgeReference) {
        if let fileName = reference.attachmentLocalFileName {
            AttachmentStorageController.deleteStoredFileIfPresent(named: fileName)
        }
    }

    private func canPersistChanges() -> Bool {
        guard persistenceDiagnostics.isPersistentStoreAvailable else {
            attachmentActionMessage = persistenceDiagnostics.blockedMutationMessage(for: regionUI.region)
            return false
        }
        return true
    }
}

// MARK: - 單筆資源的 UI 元件
struct ReferenceRowView: View {
    let reference: KnowledgeReference
    var isPlaying: Bool = false
    var summaryDisplay: ReferenceSummaryDisplay? = nil
    var onImageThumbnailLongPress: (() -> Void)? = nil
    
    var body: some View {
        let copy = RegionUIStore.runtimeCopy()
        HStack(spacing: 12) {
            if reference.type == .image, let uiImage = AttachmentStorageController.image(for: reference) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .onLongPressGesture {
                        onImageThumbnailLongPress?()
                    }
            } else {
                Image(systemName: isPlaying ? "pause.circle.fill" : iconName(for: reference.type))
                    .foregroundColor(isPlaying ? .red : .accentColor)
                    .frame(width: 36)
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reference.title)
                    .font(.headline)
                
                if reference.type == .web || reference.type == .text {
                    Text(reference.payload)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                } else if reference.type == .audio {
                    Text(isPlaying ? copy.audioPlaying : copy.localAudioFile)
                        .font(.caption)
                        .foregroundColor(isPlaying ? .red : .green)
                } else {
                    Text(copy.localFileSaved)
                        .font(.caption)
                        .foregroundColor(.green)
                }

                if let summaryDisplay {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(summaryDisplay.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(summaryDisplay.body)
                            .font(.subheadline)
                            .foregroundStyle(summaryDisplay.isOutdatedLocalization ? .secondary : .primary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)

                        if let verificationNote = summaryDisplay.verificationNote,
                           !verificationNote.isEmpty {
                            Text(verificationNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconName(for type: ReferenceType) -> String {
        switch type {
        case .web: return "safari"
        case .image: return "photo.artframe"
        case .pdf: return "doc.richtext"
        case .text: return "note.text"
        case .audio: return "waveform.circle"
        }
    }

}

private struct AttachmentPreviewSheet: View {
    let preview: AttachmentPreview

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let copy = RegionUIStore.runtimeCopy()
        NavigationStack {
            Group {
                switch preview {
                case let .image(reference):
                    ImageAttachmentPreview(reference: reference)
                case let .pdf(reference):
                    PDFAttachmentPreview(reference: reference)
                case let .text(_, content):
                    TextAttachmentPreview(content: content)
                case let .web(_, urlString):
                    WebAttachmentPreview(urlString: urlString)
                }
            }
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case let .web(_, urlString) = preview,
                   let url = URL(string: urlString) {
                    ToolbarItem(placement: .primaryAction) {
                        Link("Safari", destination: url)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.close) {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct TextAttachmentPreview: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
    }
}

private struct ImageAttachmentPreview: View {
    let reference: KnowledgeReference

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.96).ignoresSafeArea()

                if let image = AttachmentStorageController.image(for: reference) {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(
                                width: max(proxy.size.width - 24, 0),
                                height: max(proxy.size.height - 24, 0),
                                alignment: .center
                            )
                            .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
                            .padding(12)
                    }
                } else {
                    ContentUnavailableView(RegionUIStore.runtimeCopy().notFoundImage, systemImage: "photo.badge.exclamationmark")
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct PDFAttachmentPreview: View {
    let reference: KnowledgeReference

    var body: some View {
        if let localFileURL = AttachmentStorageController.restoredLocalFileURL(for: reference) {
            PDFKitView(url: localFileURL)
                .background(Color(.secondarySystemBackground))
        } else {
            ContentUnavailableView(RegionUIStore.runtimeCopy().notFoundPDF, systemImage: "doc.badge.gearshape")
        }
    }
}

private struct WebAttachmentPreview: View {
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            SafariPreview(url: url)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ContentUnavailableView(RegionUIStore.runtimeCopy().cannotPreviewLink, systemImage: "safari")
        }
    }
}

private struct SafariPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

private struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}

private struct WebLinkManagerSheet: View {
    let references: [KnowledgeReference]
    let onAdd: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var drafts = [WebLinkDraft()]
    @State private var validationMessage: String?
    @FocusState private var focusedDraftID: UUID?

    var body: some View {
        let copy = RegionUIStore.runtimeCopy()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(copy.addLinkTitle)
                                .font(.headline)

                            Spacer()

                            Button(action: addDraft) {
                                Text("+1")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(Color(.tertiarySystemFill))
                                    )
                            }
                        }

                        ForEach($drafts) { $draft in
                            HStack(spacing: 10) {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)

                                TextField(copy.addLinkHint, text: $draft.text)
                                    .textInputAutocapitalization(.never)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .textContentType(.URL)
                                    .submitLabel(.done)
                                    .focused($focusedDraftID, equals: draft.id)
                                    .onSubmit {
                                        beginSubmit(shouldDismiss: false)
                                    }

                                if drafts.count > 1 {
                                    Button(action: {
                                        removeDraft(id: draft.id)
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }

                        Text(copy.addLinkHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button {
                            beginSubmit(shouldDismiss: false)
                        } label: {
                            Text(copy.addLinkButton)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.accentColor)
                                )
                                .foregroundStyle(.white)
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy.alreadyAdded)
                            .font(.headline)

                        if references.isEmpty {
                            Text(copy.noLinksYet)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(references) { reference in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(reference.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(reference.payload)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .navigationTitle(copy.addLinkTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.done) {
                        beginSubmit(shouldDismiss: true)
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(copy.keyboardDismiss) {
                        focusedDraftID = nil
                    }
                }
            }
            .alert(copy.invalidLinkTitle, isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button(copy.ok, role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            focusedDraftID = drafts.first?.id
        }
    }

    private func beginSubmit(shouldDismiss: Bool) {
        focusedDraftID = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            submit(shouldDismiss: shouldDismiss)
        }
    }

    private func submit(shouldDismiss: Bool) {
        let copy = RegionUIStore.runtimeCopy()
        let trimmedInputs = drafts
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmedInputs.isEmpty {
            if shouldDismiss {
                dismiss()
            } else {
                validationMessage = copy.invalidLinkMessage
            }
            return
        }

        var remainingDrafts: [WebLinkDraft] = []
        var invalidInputs: [String] = []

        for draft in drafts {
            let trimmed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if onAdd(trimmed) {
                continue
            }

            invalidInputs.append(trimmed)
            remainingDrafts.append(draft)
        }

        if invalidInputs.isEmpty {
            if shouldDismiss {
                dismiss()
            } else {
                drafts = [WebLinkDraft()]
                focusedDraftID = drafts.first?.id
            }
            return
        }

        validationMessage = copy.invalidLinkMessage
        drafts = remainingDrafts.isEmpty ? [WebLinkDraft()] : remainingDrafts
        focusedDraftID = drafts.first?.id
    }

    private func addDraft() {
        let newDraft = WebLinkDraft()
        drafts.append(newDraft)
        focusedDraftID = newDraft.id
    }

    private func removeDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
        if drafts.isEmpty {
            drafts = [WebLinkDraft()]
        }
    }
}

private struct TextNoteManagerSheet: View {
    let references: [KnowledgeReference]
    let defaultTitle: String
    let onAdd: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var noteContent = ""
    @State private var validationMessage: String?

    var body: some View {
        let copy = RegionUIStore.runtimeCopy()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(copy.addNoteTitle)
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(defaultTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            TextEditor(text: $noteContent)
                                .frame(minHeight: 130)
                                .scrollContentBackground(.hidden)
                                .textInputAutocapitalization(.sentences)
                                .autocorrectionDisabled(false)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )

                        Text(copy.autoTimestampHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy.alreadyAdded)
                            .font(.headline)

                        if references.isEmpty {
                            Text(copy.noNotesYet)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(references) { reference in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(reference.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(reference.payload)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color(.secondarySystemGroupedBackground))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .navigationTitle(copy.addNoteTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(copy.done) {
                        submit()
                    }
                    .disabled(noteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert(copy.invalidNoteTitle, isPresented: Binding(
                get: { validationMessage != nil },
                set: { if !$0 { validationMessage = nil } }
            )) {
                Button(copy.ok, role: .cancel) {}
            } message: {
                Text(validationMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() {
        if onAdd(noteContent) {
            dismiss()
        } else {
            validationMessage = RegionUIStore.runtimeCopy().invalidNoteMessage
        }
    }
}

private struct WebLinkDraft: Identifiable {
    let id = UUID()
    var text = ""
}
