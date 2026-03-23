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

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore
    @State private var editingLibrary: KnowledgeLibraryRecord?
    @State private var editedName = ""

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
}
