import SwiftUI
import SwiftData

private enum ManualImagePickerRoute: Identifiable {
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

private struct DraftReference: Identifiable {
    let id = UUID()
    let title: String
    let type: ReferenceType
    let payload: String
    let attachmentData: Data?
    let attachmentOriginalFileName: String?
    let attachmentMimeType: String?
    let previewText: String?
    let createdAt = Date()
}

struct AddNodeView: View {
    @Query(sort: \KnowledgeNode.createdAt, order: .reverse) private var allNodes: [KnowledgeNode]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var libraryStore: KnowledgeLibraryStore
    @EnvironmentObject private var persistenceDiagnostics: PersistenceDiagnosticsStore
    @EnvironmentObject private var regionUI: RegionUIStore

    @StateObject private var audioRecorder = AudioRecorderService()

    @State private var title = ""
    @State private var content = ""
    @State private var selectedCategory: KnowledgeCategory = .naturalScience
    @State private var stagedReferences: [DraftReference] = []

    @State private var validationMessage: String?
    @State private var attachmentMessage: String?
    @State private var isSaving = false
    @State private var hasCommittedSave = false

    @State private var showWebSheet = false
    @State private var showTextSheet = false
    @State private var showDocumentPicker = false
    @State private var showCameraUnavailableAlert = false
    @State private var imagePickerRoute: ManualImagePickerRoute?
    @State private var selectedImage: UIImage?
    @State private var isBlinking = false
    @State private var saveResultMessage: String?
    @State private var shouldDismissAfterSaveResult = false

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 10)]

    private var nodeCountsByLibrary: [String: Int] {
        Dictionary(grouping: allNodes, by: effectiveLibraryID(for:)).mapValues(\.count)
    }

    init(initialCategory: KnowledgeCategory? = nil) {
        _selectedCategory = State(initialValue: initialCategory ?? .naturalScience)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(regionUI.copy.knowledgeNodeInfo)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 0) {
                            TextField(regionUI.copy.formTitlePlaceholder, text: $title)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 18)
                                .padding(.vertical, 18)

                            Divider()
                                .padding(.horizontal, 18)

                            VStack(alignment: .leading, spacing: 12) {
                                Text(regionUI.copy.formCategoryLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                                    ForEach(KnowledgeCategory.allCases, id: \.self) { category in
                                        Button {
                                            selectedCategory = category
                                        } label: {
                                            Text(category.localizedName)
                                                .font(.subheadline.weight(.semibold))
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .fill(
                                                            selectedCategory == category
                                                            ? category.accentColor.opacity(0.18)
                                                            : Color(.tertiarySystemGroupedBackground)
                                                        )
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                        .stroke(
                                                            selectedCategory == category
                                                            ? category.accentColor.opacity(0.9)
                                                            : Color.primary.opacity(0.06),
                                                            lineWidth: 1
                                                        )
                                                )
                                                .foregroundStyle(
                                                    selectedCategory == category
                                                    ? category.accentColor
                                                    : Color.primary
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(18)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(regionUI.theme.card)
                        )
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text(regionUI.copy.noteDetail)
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(regionUI.theme.card)

                            if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(localizedContentPlaceholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 18)
                            }

                            TextEditor(text: $content)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(minHeight: 220)
                        }
                        .frame(minHeight: 220)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(regionUI.copy.stageWithNode)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(regionUI.copy.sameEntry)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Label(localizedStagingHint, systemImage: "plus.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if stagedReferences.isEmpty {
                                Text(regionUI.copy.noReferences)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .fill(regionUI.theme.card)
                                    )
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(stagedReferences.sorted(by: { $0.createdAt > $1.createdAt })) { reference in
                                        DraftReferenceRow(reference: reference) {
                                            removeDraftReference(reference)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(regionUI.theme.canvas.ignoresSafeArea())
            .navigationTitle(regionUI.copy.addNodeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.cancel) {
                        cancelAndDismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !audioRecorder.isRecording {
                        Menu {
                            Button(action: startRecording) {
                                Label(regionUI.copy.voiceMemo30s, systemImage: "mic")
                            }

                            Divider()

                            Button(action: { presentWebSheet() }) {
                                Label(regionUI.copy.addWebLink, systemImage: "link")
                            }
                            Button(action: { presentTextSheet() }) {
                                Label(regionUI.copy.addTextNote, systemImage: "text.alignleft")
                            }

                            Divider()

                            Button(action: { presentImagePicker(for: .camera) }) {
                                Label(regionUI.copy.takePhoto, systemImage: "camera")
                            }
                            Button(action: { presentImagePicker(for: .photoLibrary) }) {
                                Label(regionUI.copy.pickPhoto, systemImage: "photo.on.rectangle")
                            }
                            Button(action: { presentDocumentPicker() }) {
                                Label(regionUI.copy.importPDF, systemImage: "doc.text")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(regionUI.copy.save) {
                        saveNode()
                    }
                    .disabled(
                        !persistenceDiagnostics.isPersistentStoreAvailable ||
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        isSaving
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if audioRecorder.isRecording {
                    recordingFloatingBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showWebSheet) {
            ManualWebReferenceSheet { input in
                addWebReference(from: input)
            }
        }
        .sheet(isPresented: $showTextSheet) {
            ManualTextReferenceSheet { content in
                addTextReference(content: content)
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker { attachment in
                appendReference(
                    type: .pdf,
                    title: attachment.originalFileName,
                    payload: attachment.fileName,
                    attachmentData: attachment.data,
                    attachmentOriginalFileName: attachment.originalFileName,
                    attachmentMimeType: attachment.mimeType,
                    previewText: localizedLocalFileStaged
                )
            } onFailure: { message in
                attachmentMessage = message
            }
        }
        .sheet(item: $imagePickerRoute) { route in
            ImagePicker(image: $selectedImage, sourceType: route.sourceType)
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage {
                saveImageToDisk(image)
                selectedImage = nil
            }
        }
        .onDisappear {
            cleanupStagedFilesIfNeeded()
        }
        .alert(localizedSaveUnavailableTitle, isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button(regionUI.copy.ok, role: .cancel) {}
        } message: {
            Text(validationMessage ?? "")
        }
        .alert(localizedSaveResultTitle, isPresented: Binding(
            get: { saveResultMessage != nil },
            set: {
                if !$0 {
                    saveResultMessage = nil
                    shouldDismissAfterSaveResult = false
                }
            }
        )) {
            Button(regionUI.copy.ok, role: .cancel) {
                let shouldDismiss = shouldDismissAfterSaveResult
                saveResultMessage = nil
                shouldDismissAfterSaveResult = false
                if shouldDismiss {
                    dismiss()
                }
            }
        } message: {
            Text(saveResultMessage ?? "")
        }
        .alert(regionUI.copy.attachmentResultTitle, isPresented: Binding(
            get: { attachmentMessage != nil },
            set: { if !$0 { attachmentMessage = nil } }
        )) {
            Button(regionUI.copy.ok, role: .cancel) {}
        } message: {
            Text(attachmentMessage ?? "")
        }
        .alert(regionUI.copy.cameraUnavailableTitle, isPresented: $showCameraUnavailableAlert) {
            Button(regionUI.copy.ok, role: .cancel) {}
        } message: {
            Text(regionUI.copy.cameraUnavailableMessage)
        }
    }

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

            Spacer()

            Button(action: {
                audioRecorder.stopRecording()
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    private func cancelAndDismiss() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        }
        cleanupStagedFilesIfNeeded()
        dismiss()
    }

    private func cleanupStagedFilesIfNeeded() {
        guard !hasCommittedSave else { return }
        for reference in stagedReferences {
            deleteStoredPayloadIfNeeded(for: reference)
        }
    }

    private func presentImagePicker(for sourceType: UIImagePickerController.SourceType) {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            if sourceType == .camera {
                showCameraUnavailableAlert = true
            }
            return
        }

        imagePickerRoute = sourceType == .camera ? .camera : .photoLibrary
    }

    private func appendReference(
        type: ReferenceType,
        title: String,
        payload: String,
        attachmentData: Data? = nil,
        attachmentOriginalFileName: String? = nil,
        attachmentMimeType: String? = nil,
        previewText: String? = nil
    ) {
        guard canPersistChanges(presentAsAttachmentMessage: true) else {
            if type == .image || type == .pdf || type == .audio {
                AttachmentStorageController.deleteStoredFileIfPresent(named: payload)
            }
            return
        }
        stagedReferences.append(
            DraftReference(
                title: title,
                type: type,
                payload: payload,
                attachmentData: attachmentData,
                attachmentOriginalFileName: attachmentOriginalFileName,
                attachmentMimeType: attachmentMimeType,
                previewText: previewText
            )
        )
    }

    private func removeDraftReference(_ reference: DraftReference) {
        stagedReferences.removeAll { $0.id == reference.id }
        deleteStoredPayloadIfNeeded(for: reference)
    }

    private func deleteStoredPayloadIfNeeded(for reference: DraftReference) {
        switch reference.type {
        case .image, .pdf, .audio:
            AttachmentStorageController.deleteStoredFileIfPresent(named: reference.payload)
        case .web, .text:
            break
        }
    }

    private func saveImageToDisk(_ image: UIImage) {
        defer { imagePickerRoute = nil }
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }

        do {
            let attachment = try AttachmentStorageController.saveImage(image)
            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd HH:mm"
            let imageTitle = imagePickerRoute == .camera ? localizedCameraImageTitle(at: formatter.string(from: Date())) : localizedPhotoLibraryImageTitle
            appendReference(
                type: .image,
                title: imageTitle,
                payload: attachment.fileName,
                attachmentData: attachment.data,
                attachmentOriginalFileName: attachment.originalFileName,
                attachmentMimeType: attachment.mimeType,
                previewText: localizedLocalFileStaged
            )
        } catch {
            attachmentMessage = AttachmentStorageController.userFacingErrorMessage(for: error, action: localizedAddImageAction)
        }
    }

    private func startRecording() {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }
        do {
            try AttachmentStorageController.ensureCapacity(forAdditionalBytes: AttachmentStorageController.shortAudioReservationBytes)
        } catch {
            attachmentMessage = AttachmentStorageController.userFacingErrorMessage(for: error, action: localizedStartRecordingAction)
            return
        }

        audioRecorder.startRecording { fileName in
            guard let fileName else {
                attachmentMessage = localizedRecordingFailed
                return
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "MM/dd HH:mm"
            do {
                let attachment = try AttachmentStorageController.storedAttachment(named: fileName)
                appendReference(
                    type: .audio,
                    title: localizedVoiceMemoTitle(at: formatter.string(from: Date())),
                    payload: attachment.fileName,
                    attachmentData: attachment.data,
                    attachmentOriginalFileName: attachment.originalFileName,
                    attachmentMimeType: attachment.mimeType,
                    previewText: localizedLocalAudioStaged
                )
            } catch {
                AttachmentStorageController.deleteStoredFileIfPresent(named: fileName)
                attachmentMessage = localizedRecordingFailed
            }
        }
    }

    private func defaultTextNoteTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        switch regionUI.region {
        case .taiwan:
            return "文字筆記 \(formatter.string(from: Date()))"
        case .unitedStates:
            return "Text Note \(formatter.string(from: Date()))"
        case .japan:
            return "テキストメモ \(formatter.string(from: Date()))"
        }
    }

    @discardableResult
    private func addTextReference(content: String) -> Bool {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        appendReference(type: .text, title: defaultTextNoteTitle(), payload: trimmed, previewText: trimmed)
        return true
    }

    @discardableResult
    private func addWebReference(from rawInput: String) -> Bool {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return false }
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = normalizedWebURL(from: trimmed) else { return false }

        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? regionUI.copy.linkDefaultTitle
        appendReference(type: .web, title: host, payload: url.absoluteString, previewText: url.absoluteString)
        return true
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

        return fallbackConstructedWebURL(from: sanitized)
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

    private func looksLikeDomain(_ host: String) -> Bool {
        guard host.contains("."), !host.contains(" "), host.count >= 4 else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-.")
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func saveNode() {
        guard canPersistChanges() else {
            validationMessage = localizedPersistenceUnavailableMessage
            return
        }
        guard !isSaving else { return }
        isSaving = true

        Task { @MainActor in
            defer { isSaving = false }

            let existingTitles = await loadKnowledgeTitleSnapshot(using: modelContext)
            let validation = KnowledgeNodeCleaner.validate(
                title: title,
                content: content,
                categoryRaw: selectedCategory.rawValue,
                source: .manual,
                existingTitles: existingTitles
            )

            guard let draft = validation.draft else {
                validationMessage = validation.rejectionReason ?? localizedKnowledgeSaveFailure
                return
            }

            let currentNodeCount = nodeCountsByLibrary[libraryStore.activeLibraryID] ?? 0
            let insertionTarget: KnowledgeLibraryInsertionTarget
            do {
                insertionTarget = try libraryStore.prepareActiveLibraryForNextInsertion(
                    currentNodeCount: currentNodeCount,
                    modelContext: modelContext
                )
            } catch {
                validationMessage = localizedGenericSaveFailure
                return
            }

            let newNode = KnowledgeNode(
                title: draft.title,
                content: draft.content,
                category: draft.category,
                x: 0, y: 0, z: 0,
                libraryID: insertionTarget.library.id,
                libraryName: insertionTarget.library.name
            )

            if !stagedReferences.isEmpty {
                newNode.references = stagedReferences.map { reference in
                    KnowledgeReference(
                        title: reference.title,
                        type: reference.type,
                        payload: reference.payload,
                        attachmentData: reference.attachmentData,
                        attachmentOriginalFileName: reference.attachmentOriginalFileName,
                        attachmentMimeType: reference.attachmentMimeType
                    )
                }
            }

            modelContext.insert(newNode)

            do {
                try modelContext.save()
                hasCommittedSave = true
                await KnowledgeTitleIndexStore.shared.register(
                    normalizedTitles: [KnowledgeNodeCleaner.normalizedKey(for: draft.title)]
                )
                if insertionTarget.didArchive {
                    shouldDismissAfterSaveResult = true
                    saveResultMessage = localizedAutoArchiveSaveResult
                } else {
                    dismiss()
                }
            } catch {
                validationMessage = localizedGenericSaveFailure
            }
        }
    }

    private func presentWebSheet() {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }
        showWebSheet = true
    }

    private func presentTextSheet() {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }
        showTextSheet = true
    }

    private func presentDocumentPicker() {
        guard canPersistChanges(presentAsAttachmentMessage: true) else { return }
        showDocumentPicker = true
    }

    private func canPersistChanges(presentAsAttachmentMessage: Bool = false) -> Bool {
        guard persistenceDiagnostics.isPersistentStoreAvailable else {
            if presentAsAttachmentMessage {
                attachmentMessage = localizedPersistenceUnavailableMessage
            } else {
                validationMessage = localizedPersistenceUnavailableMessage
            }
            return false
        }
        return true
    }

    private var localizedPersistenceUnavailableMessage: String {
        persistenceDiagnostics.blockedMutationMessage(for: regionUI.region)
    }

    private func effectiveLibraryID(for node: KnowledgeNode) -> String {
        let rawID = node.libraryID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !rawID.isEmpty {
            return rawID
        }
        return libraryStore.activeLibraryID
    }

    private var localizedContentPlaceholder: String {
        switch regionUI.region {
        case .taiwan:
            return "輸入這個知識節點的主要內容、定義或你想記住的觀察。"
        case .unitedStates:
            return "Write the main idea, definition, or observation you want to keep for this knowledge entry."
        case .japan:
            return "この知識ノードに残したい主な内容、定義、観察を入力してください。"
        }
    }

    private var localizedStagingHint: String {
        switch regionUI.region {
        case .taiwan:
            return "可先加入網頁連結、文字筆記、拍照、相簿圖片、PDF 與 30 秒語音備忘錄。"
        case .unitedStates:
            return "You can stage web links, text notes, photos, library images, PDFs, and a 30-second voice memo before saving."
        case .japan:
            return "保存前に Webリンク、テキストメモ、撮影、写真、PDF、30秒音声メモを先に追加できます。"
        }
    }

    private var localizedLocalFileStaged: String {
        switch regionUI.region {
        case .taiwan:
            return "本機檔案已暫存"
        case .unitedStates:
            return "Stored locally for now"
        case .japan:
            return "端末内ファイルを一時保存しました"
        }
    }

    private var localizedLocalAudioStaged: String {
        switch regionUI.region {
        case .taiwan:
            return "本機語音檔已暫存"
        case .unitedStates:
            return "Voice memo stored locally"
        case .japan:
            return "音声ファイルを端末内に一時保存しました"
        }
    }

    private var localizedSaveUnavailableTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "無法儲存"
        case .unitedStates:
            return "Cannot Save"
        case .japan:
            return "保存できません"
        }
    }

    private var localizedSaveResultTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "儲存完成"
        case .unitedStates:
            return "Saved"
        case .japan:
            return "保存しました"
        }
    }

    private func localizedCameraImageTitle(at timestamp: String) -> String {
        switch regionUI.region {
        case .taiwan:
            return "相機拍攝 \(timestamp)"
        case .unitedStates:
            return "Camera Capture \(timestamp)"
        case .japan:
            return "カメラ撮影 \(timestamp)"
        }
    }

    private var localizedPhotoLibraryImageTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "相簿圖片"
        case .unitedStates:
            return "Photo Library Image"
        case .japan:
            return "写真ライブラリ画像"
        }
    }

    private var localizedAddImageAction: String {
        switch regionUI.region {
        case .taiwan:
            return "加入圖片"
        case .unitedStates:
            return "Add Image"
        case .japan:
            return "画像を追加"
        }
    }

    private var localizedStartRecordingAction: String {
        switch regionUI.region {
        case .taiwan:
            return "開始錄音"
        case .unitedStates:
            return "Start Recording"
        case .japan:
            return "録音を開始"
        }
    }

    private var localizedRecordingFailed: String {
        switch regionUI.region {
        case .taiwan:
            return "錄音失敗，請再試一次。"
        case .unitedStates:
            return "Recording failed. Please try again."
        case .japan:
            return "録音に失敗しました。もう一度お試しください。"
        }
    }

    private func localizedVoiceMemoTitle(at timestamp: String) -> String {
        switch regionUI.region {
        case .taiwan:
            return "語音備忘錄 \(timestamp)"
        case .unitedStates:
            return "Voice Memo \(timestamp)"
        case .japan:
            return "音声メモ \(timestamp)"
        }
    }

    private var localizedKnowledgeSaveFailure: String {
        switch regionUI.region {
        case .taiwan:
            return "這個知識點無法儲存"
        case .unitedStates:
            return "This knowledge entry cannot be saved."
        case .japan:
            return "この知識点は保存できません。"
        }
    }

    private var localizedAutoArchiveSaveResult: String {
        switch regionUI.region {
        case .taiwan:
            return "知識點已儲存。目前知識庫已達 \(KnowledgeLibraryStore.autoArchiveNodeLimit) 筆，系統已自動封存並建立新的知識庫。"
        case .unitedStates:
            return "The entry was saved. The active library reached \(KnowledgeLibraryStore.autoArchiveNodeLimit) entries, so it was archived automatically and a new library was created."
        case .japan:
            return "知識点を保存しました。現在のライブラリが \(KnowledgeLibraryStore.autoArchiveNodeLimit) 件に達したため、自動で保存され、新しいライブラリを作成しました。"
        }
    }

    private var localizedGenericSaveFailure: String {
        switch regionUI.region {
        case .taiwan:
            return "儲存失敗，請再試一次。"
        case .unitedStates:
            return "Save failed. Please try again."
        case .japan:
            return "保存に失敗しました。もう一度お試しください。"
        }
    }
}

private struct DraftReferenceRow: View {
    let reference: DraftReference
    let onRemove: () -> Void

    private var copy: RegionCopy { RegionUIStore.runtimeCopy() }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(reference.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(reference.previewText ?? fallbackText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var iconName: String {
        switch reference.type {
        case .web:
            return "link"
        case .image:
            return "photo"
        case .pdf:
            return "doc.text"
        case .text:
            return "text.alignleft"
        case .audio:
            return "mic"
        }
    }

    private var iconColor: Color {
        switch reference.type {
        case .web:
            return .blue
        case .image:
            return .orange
        case .pdf:
            return .indigo
        case .text:
            return .secondary
        case .audio:
            return .red
        }
    }

    private var fallbackText: String {
        switch reference.type {
        case .web:
            return reference.payload
        case .image, .pdf:
            return copy.localFileSaved
        case .text:
            return reference.payload
        case .audio:
            return copy.localAudioFile
        }
    }
}

private struct ManualTextReferenceSheet: View {
    let onAdd: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var validationMessage: String?

    private var copy: RegionCopy { RegionUIStore.runtimeCopy() }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy.addTextNote)
                    .font(.headline)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))

                    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(copy.autoTimestampHint)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                    }

                    TextEditor(text: $content)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(minHeight: 220)
                }

                Button {
                    if onAdd(content) {
                        dismiss()
                    } else {
                        validationMessage = copy.invalidNoteMessage
                    }
                } label: {
                    Text(copy.addTextNote)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(copy.addTextNote)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel) {
                        dismiss()
                    }
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
}

private struct ManualWebReferenceSheet: View {
    let onAdd: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var validationMessage: String?

    private var copy: RegionCopy { RegionUIStore.runtimeCopy() }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(copy.addWebLink)
                    .font(.headline)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)

                    TextField(copy.addLinkTitle, text: $input)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                Text(copy.addLinkHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    if onAdd(input) {
                        dismiss()
                    } else {
                        validationMessage = copy.invalidLinkMessage
                    }
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

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle(copy.addWebLink)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancel) {
                        dismiss()
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
        .presentationDetents([.medium])
    }
}

#Preview {
    AddNodeView()
        .modelContainer(for: [KnowledgeLibrary.self, KnowledgeNode.self, KnowledgeReference.self], inMemory: true)
        .environmentObject(KnowledgeLibraryStore())
}
