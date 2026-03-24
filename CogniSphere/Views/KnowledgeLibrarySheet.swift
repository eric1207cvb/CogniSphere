import SwiftUI

struct KnowledgeLibrarySheet: View {
    let libraries: [KnowledgeLibraryRecord]
    let activeLibraryID: String
    let selectedLibraryID: String
    let counts: [String: Int]
    let onSelect: (String) -> Void
    let onRename: (String, String) -> Void
    let onExport: (String) -> Void
    let onArchiveCurrent: () -> Void
    let onCreateShowcaseLibrary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore
    @State private var editingLibrary: KnowledgeLibraryRecord?
    @State private var editedName = ""
    @State private var showCreateShowcaseAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section(regionUI.copy.libraryTitle) {
                    ForEach(libraries) { library in
                        Button {
                            onSelect(library.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(KnowledgeLibraryStore.displayName(for: library, region: regionUI.region))
                                            .font(.headline)
                                            .foregroundStyle(.primary)

                                        if library.id == activeLibraryID {
                                            Text(regionUI.copy.currentWriting)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(regionUI.theme.chipFill))
                                                .foregroundStyle(regionUI.theme.chipText)
                                        } else if library.isArchived {
                                            Text(regionUI.copy.archived)
                                                .font(.caption.weight(.semibold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(regionUI.theme.cardSecondary))
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Text(summaryText(for: library))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if library.isArchived {
                                    Button {
                                        onExport(library.id)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(regionUI.copy.exportKnowledgeNetwork)

                                    Button {
                                        editingLibrary = library
                                        editedName = library.name
                                    } label: {
                                        Image(systemName: "pencil")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if library.id == selectedLibraryID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(regionUI.theme.accent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button(action: onArchiveCurrent) {
                        Label(regionUI.copy.archiveAction, systemImage: "archivebox")
                    }
                } footer: {
                    Text(regionUI.copy.archiveFooter)
                }

                Section {
                    Button {
                        showCreateShowcaseAlert = true
                    } label: {
                        Label(localizedShowcaseActionTitle, systemImage: "sparkles.rectangle.stack")
                    }
                } footer: {
                    Text(localizedShowcaseFooter)
                }
            }
            .scrollContentBackground(.hidden)
            .background(regionUI.theme.canvas)
            .navigationTitle(regionUI.copy.libraryTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.done) { dismiss() }
                }
            }
            .alert(regionUI.copy.editLibraryTitle, isPresented: Binding(
                get: { editingLibrary != nil },
                set: { if !$0 { editingLibrary = nil } }
            )) {
                TextField(regionUI.copy.editLibraryPlaceholder, text: $editedName)
                Button(regionUI.copy.cancel, role: .cancel) {
                    editingLibrary = nil
                }
                Button(regionUI.copy.save) {
                    if let library = editingLibrary {
                        onRename(library.id, editedName)
                    }
                    editingLibrary = nil
                }
            } message: {
                Text(regionUI.copy.editLibraryMessage)
            }
            .alert(localizedShowcaseAlertTitle, isPresented: $showCreateShowcaseAlert) {
                Button(regionUI.copy.cancel, role: .cancel) {}
                Button(localizedShowcaseConfirmTitle) {
                    onCreateShowcaseLibrary()
                    dismiss()
                }
            } message: {
                Text(localizedShowcaseAlertMessage)
            }
        }
    }

    private func summaryText(for library: KnowledgeLibraryRecord) -> String {
        let count = counts[library.id] ?? 0
        if let archivedAt = library.archivedAt {
            return regionUI.copy.archiveSummary(
                count: count,
                archivedAt: Self.dateFormatter(locale: regionUI.locale).string(from: archivedAt)
            )
        }
        return regionUI.copy.createdSummary(
            count: count,
            createdAt: Self.dateFormatter(locale: regionUI.locale).string(from: library.createdAt)
        )
    }

    private static func dateFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var localizedShowcaseActionTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "建立上架示範知識庫"
        case .unitedStates:
            return "Create App Store Showcase"
        case .japan:
            return "審査用サンプルを作成"
        }
    }

    private var localizedShowcaseConfirmTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "建立"
        case .unitedStates:
            return "Create"
        case .japan:
            return "作成"
        }
    }

    private var localizedShowcaseAlertTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "建立上架示範知識庫"
        case .unitedStates:
            return "Create App Store Showcase"
        case .japan:
            return "審査用サンプルを作成"
        }
    }

    private var localizedShowcaseAlertMessage: String {
        switch regionUI.region {
        case .taiwan:
            return "系統會建立一個包含六類學門、18 筆中英日節點與示範附件的新知識庫。若目前知識庫已有內容，系統會先封存目前知識庫。"
        case .unitedStates:
            return "This creates a new showcase library with 18 multilingual entries across six disciplines and example attachments. If your current active library already has content, it will be archived first."
        case .japan:
            return "6分類・18件の中英日サンプル知識点と添付を含む新しいサンプルライブラリを作成します。現在のライブラリに内容がある場合は、先に保存されます。"
        }
    }

    private var localizedShowcaseFooter: String {
        switch regionUI.region {
        case .taiwan:
            return "建立可用於 App Store 截圖的示範資料，包含真實節點內容、圖片與 PDF 附件。"
        case .unitedStates:
            return "Creates screenshot-ready sample data with real entries, image cards, and PDF attachments."
        case .japan:
            return "App Store のスクリーンショット用に、実際の知識点、画像カード、PDF 添付をまとめて生成します。"
        }
    }
}
