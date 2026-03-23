import SwiftUI

struct KnowledgeImportReviewView: View {
    let preview: KnowledgeImportPreview
    let onCancel: () -> Void
    let onRequestOCR: (() async -> ReferenceImageOCRResult?)?
    let onConfirm: ([KnowledgeImportCandidate], ReferenceImageOCRResult?) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore
    @State private var selectedIDs: Set<UUID> = []
    @State private var editableCandidates: [KnowledgeImportCandidate] = []
    @State private var requestedOCRResult: ReferenceImageOCRResult?
    @State private var isRequestingOCR = false
    @State private var editingCandidate: KnowledgeImportCandidate?

    private var localizedReviewInstruction: String {
        switch regionUI.region {
        case .taiwan:
            return "請勾選要加入知識庫的知識項目"
        case .unitedStates:
            return "Select the knowledge entries you want to add"
        case .japan:
            return "知識ライブラリへ追加する項目を選択してください"
        }
    }

    private var localizedRequestOCRLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "額外擷取 OCR 文字"
        case .unitedStates:
            return "Extract Additional OCR Text"
        case .japan:
            return "OCRテキストを追加抽出"
        }
    }

    private var localizedRefreshOCRLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "重新擷取 OCR 文字"
        case .unitedStates:
            return "Refresh OCR Text"
        case .japan:
            return "OCRテキストを再抽出"
        }
    }

    private var localizedOCRCompleted: String {
        switch regionUI.region {
        case .taiwan:
            return "已完成額外 OCR 擷取"
        case .unitedStates:
            return "Additional OCR extraction completed"
        case .japan:
            return "追加のOCR抽出が完了しました"
        }
    }

    private var localizedCreateDraftLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "用 OCR / 摘要建立草稿"
        case .unitedStates:
            return "Create Draft from OCR / Summary"
        case .japan:
            return "OCR / 要約から下書きを作成"
        }
    }

    private var localizedAddAnotherDraftLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "再加入一筆 OCR 草稿"
        case .unitedStates:
            return "Add Another OCR Draft"
        case .japan:
            return "OCR下書きをもう1件追加"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard

                    if !editableCandidates.isEmpty {
                        selectionBar
                    }

                    if editableCandidates.isEmpty {
                        emptyCandidatesCard
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle(regionUI.copy.candidateEntriesTitle)

                            ForEach(editableCandidates) { candidate in
                                candidateCard(candidate)
                            }
                        }
                    }

                    if !preview.rejected.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle(localizedRejectedSectionTitle)

                            VStack(spacing: 10) {
                                ForEach(preview.rejected.prefix(6)) { rejected in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(rejected.title.isEmpty ? localizedUntitledItem : rejected.title)
                                            .font(.subheadline.weight(.semibold))
                                        Text(rejected.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.82))
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(regionUI.theme.canvas)
            .navigationTitle(regionUI.copy.importReviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.cancel) {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(regionUI.theme.accent)
                }

                if !editableCandidates.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(localizedConfirmSelectionLabel) {
                            let chosen = editableCandidates.filter { selectedIDs.contains($0.id) }
                            onConfirm(chosen, requestedOCRResult)
                            dismiss()
                        }
                        .disabled(selectedIDs.isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(regionUI.copy.done) {
                            onCancel()
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                if editableCandidates.isEmpty {
                    editableCandidates = preview.candidates
                }

                if selectedIDs.isEmpty, !editableCandidates.isEmpty {
                    selectedIDs = Set(editableCandidates.map(\.id))
                }
            }
        }
        .presentationDetents([.large])
        .sheet(item: $editingCandidate) { candidate in
            KnowledgeNodeFormSheet(
                screenTitle: localizedEditCandidateTitle,
                saveLabel: localizedApplyLabel,
                initialTitle: candidate.draft.title,
                initialContent: candidate.draft.content,
                initialCategory: candidate.draft.category
            ) { title, content, category in
                updateCandidate(candidate.id, title: title, content: content, category: category)
                return nil
            }
        }
    }

    private var localizedRejectedSectionTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "已自動排除"
        case .unitedStates:
            return "Automatically Rejected"
        case .japan:
            return "自動的に除外"
        }
    }

    private var localizedUntitledItem: String {
        switch regionUI.region {
        case .taiwan:
            return "未命名項目"
        case .unitedStates:
            return "Untitled Item"
        case .japan:
            return "無題の項目"
        }
    }

    private var localizedConfirmSelectionLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "加入 \(selectedIDs.count)"
        case .unitedStates:
            return "Add \(selectedIDs.count)"
        case .japan:
            return "\(selectedIDs.count) 件を追加"
        }
    }

    private var localizedEditCandidateTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "編輯知識條目"
        case .unitedStates:
            return "Edit Knowledge Entry"
        case .japan:
            return "知識項目を編集"
        }
    }

    private var localizedApplyLabel: String {
        switch regionUI.region {
        case .taiwan:
            return "套用"
        case .unitedStates:
            return "Apply"
        case .japan:
            return "適用"
        }
    }

    private var localizedSelectedCount: String {
        switch regionUI.region {
        case .taiwan:
            return "已勾選 \(selectedIDs.count) 項"
        case .unitedStates:
            return "\(selectedIDs.count) selected"
        case .japan:
            return "\(selectedIDs.count) 件を選択中"
        }
    }

    private var localizedSelectAll: String {
        switch regionUI.region {
        case .taiwan:
            return "全選"
        case .unitedStates:
            return "Select All"
        case .japan:
            return "すべて選択"
        }
    }

    private var localizedDeselectAll: String {
        switch regionUI.region {
        case .taiwan:
            return "全不選"
        case .unitedStates:
            return "Clear All"
        case .japan:
            return "すべて解除"
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(localizedSelectedCount)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button(selectedIDs.count == editableCandidates.count ? localizedDeselectAll : localizedSelectAll) {
                if selectedIDs.count == editableCandidates.count {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(editableCandidates.map(\.id))
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(regionUI.theme.card)
            )
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(preview.source.localizedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )

                    Text(preview.recognitionMode.localizedLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(.systemGray6))
                        )
                }

                Text(localizedReviewInstruction)
                    .font(.headline)
            }

            if let sourceSummary = preview.sourceSummary {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview.source.summaryTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(sourceSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(regionUI.theme.cardSecondary)
                )
            }

            if let onRequestOCR {
                Button {
                    requestOCR(using: onRequestOCR)
                } label: {
                    HStack(spacing: 10) {
                        if isRequestingOCR {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "text.viewfinder")
                        }
                        Text(requestedOCRResult == nil ? localizedRequestOCRLabel : localizedRefreshOCRLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.78, green: 0.79, blue: 0.85))
                .foregroundStyle(.primary)
                .disabled(isRequestingOCR)
            }

            if requestedOCRResult != nil {
                Text(localizedOCRCompleted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let fallbackSourceText {
                Button {
                    createDraftFromFallbackText(text: fallbackSourceText, titleHint: fallbackTitleHint)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                        Text(editableCandidates.isEmpty ? localizedCreateDraftLabel : localizedAddAnotherDraftLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private var emptyCandidatesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(regionUI.copy.candidateEntriesTitle)

            Text(regionUI.copy.noDirectCandidatesMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.92))
                )
        }
    }

    private func candidateCard(_ candidate: KnowledgeImportCandidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                toggle(candidate.id)
            } label: {
                ZStack {
                    Circle()
                        .fill(selectedIDs.contains(candidate.id) ? Color.accentColor.opacity(0.14) : Color(.systemGray6))
                        .frame(width: 30, height: 30)
                    Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedIDs.contains(candidate.id) ? Color.accentColor : Color.secondary.opacity(0.45))
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Text(candidate.draft.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    Text(candidate.draft.category.localizedName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                        .fill(regionUI.theme.cardSecondary)
                        )
                }

                Text(candidate.draft.content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .lineSpacing(2)
            }

            Button {
                editingCandidate = candidate
            } label: {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(Color(.systemGray6))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.94))
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.secondary)
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func requestOCR(using action: @escaping () async -> ReferenceImageOCRResult?) {
        isRequestingOCR = true
        Task {
            let result = await action()
            await MainActor.run {
                isRequestingOCR = false
                requestedOCRResult = result
            }
        }
    }

    private func updateCandidate(_ id: UUID, title: String, content: String, category: KnowledgeCategory) {
        guard let index = editableCandidates.firstIndex(where: { $0.id == id }) else { return }
        editableCandidates[index] = KnowledgeImportCandidate(
            id: id,
            draft: SanitizedKnowledgeDraft(
                title: title,
                content: content,
                category: category
            ),
            source: editableCandidates[index].source
        )
    }

    private var fallbackSourceText: String? {
        if let requestedOCRResult {
            let trimmed = requestedOCRResult.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let sourceSummary = preview.sourceSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sourceSummary.isEmpty {
            return sourceSummary
        }

        if let extracted = preview.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !extracted.isEmpty {
            return extracted
        }

        return nil
    }

    private var fallbackTitleHint: String? {
        if let requestedOCRResult {
            return requestedOCRResult.title
        }

        return preview.sourceSummary
    }

    private func createDraftFromFallbackText(text: String, titleHint: String?) {
        let candidate = KnowledgeImportCandidate(
            draft: KnowledgeImportFallbackBuilder.makeDraft(
                from: text,
                suggestedTitle: titleHint
            ),
            source: .manual
        )
        editableCandidates.insert(candidate, at: 0)
        selectedIDs.insert(candidate.id)
        editingCandidate = candidate
    }
}
