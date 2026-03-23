import SwiftUI

struct KnowledgeNodeFormSheet: View {
    let screenTitle: String
    let saveLabel: String
    let initialTitle: String
    let initialContent: String
    let initialCategory: KnowledgeCategory
    let onSave: (String, String, KnowledgeCategory) -> String?

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore
    @State private var draftTitle: String
    @State private var draftContent: String
    @State private var draftCategory: KnowledgeCategory
    @State private var validationMessage: String?

    init(
        screenTitle: String,
        saveLabel: String,
        initialTitle: String,
        initialContent: String,
        initialCategory: KnowledgeCategory,
        onSave: @escaping (String, String, KnowledgeCategory) -> String?
    ) {
        self.screenTitle = screenTitle
        self.saveLabel = saveLabel
        self.initialTitle = initialTitle
        self.initialContent = initialContent
        self.initialCategory = initialCategory
        self.onSave = onSave
        _draftTitle = State(initialValue: initialTitle)
        _draftContent = State(initialValue: initialContent)
        _draftCategory = State(initialValue: initialCategory)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(regionUI.copy.formTitleLabel) {
                    TextField(regionUI.copy.formTitlePlaceholder, text: $draftTitle)
                }

                Section(regionUI.copy.formCategoryLabel) {
                    Picker(regionUI.copy.formCategoryLabel, selection: $draftCategory) {
                        ForEach(KnowledgeCategory.allCases, id: \.self) { category in
                            Text(category.localizedName).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section(regionUI.copy.formContentLabel) {
                    TextEditor(text: $draftContent)
                        .frame(minHeight: 220)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.cancel) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(saveLabel) {
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTitle.isEmpty else {
            validationMessage = regionUI.copy.emptyTitleValidation
            return
        }

        guard !trimmedContent.isEmpty else {
            validationMessage = regionUI.copy.emptyContentValidation
            return
        }

        if let message = onSave(trimmedTitle, trimmedContent, draftCategory) {
            validationMessage = message
            return
        }

        dismiss()
    }
}
