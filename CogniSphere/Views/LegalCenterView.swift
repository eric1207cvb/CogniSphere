import SafariServices
import SwiftUI

private struct LegalLinkTarget: Identifiable {
    let id = UUID()
    let url: URL
}

struct LegalCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var regionUI: RegionUIStore

    @State private var selectedDocument: LegalDocumentKind
    @State private var externalLink: LegalLinkTarget?

    init(initialDocument: LegalDocumentKind = .privacy) {
        _selectedDocument = State(initialValue: initialDocument)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard

                    Picker("", selection: $selectedDocument) {
                        ForEach(LegalDocumentKind.allCases) { kind in
                            Text(kind.shortTitle(for: regionUI.region))
                                .tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    documentCard
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .background(regionUI.theme.canvas.ignoresSafeArea())
            .navigationTitle(LegalContentProvider.legalCenterTitle(for: regionUI.region))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(regionUI.copy.done) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(item: $externalLink) { target in
            InAppSafariView(url: target.url)
        }
    }

    private var content: LegalDocumentContent {
        LegalContentProvider.content(for: selectedDocument, region: regionUI.region)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LegalContentProvider.legalCenterSubtitle(for: regionUI.region))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Image(systemName: selectedDocument.iconName)
                    .font(.title3)
                    .foregroundStyle(regionUI.theme.accent)

                Text(content.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(regionUI.theme.cardSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(regionUI.theme.outline.opacity(0.7), lineWidth: 1)
        )
    }

    private var documentCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(content.summary)
                .font(.body)
                .foregroundStyle(.primary)

            ForEach(content.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(section.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !content.links.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(localizedOfficialLinksTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ForEach(content.links) { link in
                        Button {
                            externalLink = LegalLinkTarget(url: link.url)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "link")
                                    .foregroundStyle(regionUI.theme.accent)
                                Text(link.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.tertiarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(content.footerNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(regionUI.theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(regionUI.theme.outline.opacity(0.7), lineWidth: 1)
        )
    }

    private var localizedOfficialLinksTitle: String {
        switch regionUI.region {
        case .taiwan:
            return "官方連結"
        case .unitedStates:
            return "Official Links"
        case .japan:
            return "公式リンク"
        }
    }
}

private struct InAppSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
