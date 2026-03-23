import Foundation

struct KnowledgeExportPackage: Identifiable {
    let directoryURL: URL
    let createdAt: Date
    let displayNameOverride: String?

    var id: String { directoryURL.path }

    var displayName: String {
        displayNameOverride ?? directoryURL.lastPathComponent
    }
}

enum KnowledgeExportService {
    static func buildExportPackage(for nodes: [KnowledgeNode]) throws -> KnowledgeExportPackage {
        try buildExportPackage(for: nodes, libraryName: nil)
    }

    static func buildExportPackage(for nodes: [KnowledgeNode], libraryName: String?) throws -> KnowledgeExportPackage {
        let timestamp = exportTimestampFormatter.string(from: Date())
        let exportLabel = libraryName.map(safeFileStem).flatMap { $0.isEmpty ? nil : $0 } ?? localizedExportFolderStem()
        let attachmentsFolderName = localizedAttachmentsFolderName()
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CogniSphere-\(exportLabel)-\(timestamp)", isDirectory: true)
        let attachmentsURL = rootURL.appendingPathComponent(attachmentsFolderName, isDirectory: true)

        try? FileManager.default.removeItem(at: rootURL)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)

        var nodeFileNames = Set<String>()
        var attachmentFileNames = Set<String>()
        var indexEntries: [String] = []

        for node in nodes.sorted(by: { $0.createdAt > $1.createdAt }) {
            let markdown = try markdownForNode(
                node,
                attachmentsDirectoryURL: attachmentsURL,
                attachmentsFolderName: attachmentsFolderName,
                usedAttachmentNames: &attachmentFileNames
            )
            let nodeFileName = uniqueFileName(
                base: safeFileStem(node.title),
                ext: "md",
                usedNames: &nodeFileNames
            )
            try markdown.write(
                to: rootURL.appendingPathComponent(nodeFileName),
                atomically: true,
                encoding: .utf8
            )
            indexEntries.append("- [\(node.title)](\(nodeFileName))")
        }

        let indexTitle: String
        let exportedAtLabel: String
        let countLabel: String
        let libraryLabel: String
        let listTitle: String
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            indexTitle = "# CogniSphere 匯出"
            exportedAtLabel = "匯出時間"
            countLabel = "知識點數量"
            libraryLabel = "知識網絡"
            listTitle = "## 知識點列表"
        case .unitedStates:
            indexTitle = "# CogniSphere Export"
            exportedAtLabel = "Exported At"
            countLabel = "Knowledge Entries"
            libraryLabel = "Knowledge Network"
            listTitle = "## Entries"
        case .japan:
            indexTitle = "# CogniSphere エクスポート"
            exportedAtLabel = "出力日時"
            countLabel = "知識項目数"
            libraryLabel = "知識ネットワーク"
            listTitle = "## 一覧"
        }

        let libraryLine: String
        if let libraryName, !libraryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            libraryLine = "- \(libraryLabel): \(libraryName)"
        } else {
            libraryLine = ""
        }

        let index = """
        \(indexTitle)

        - \(exportedAtLabel): \(displayDateFormatter.string(from: Date()))
        - \(countLabel): \(nodes.count)
        \(libraryLine)

        \(listTitle)

        \(indexEntries.joined(separator: "\n"))
        """

        try index.write(
            to: rootURL.appendingPathComponent("index.md"),
            atomically: true,
            encoding: .utf8
        )

        return KnowledgeExportPackage(
            directoryURL: rootURL,
            createdAt: Date(),
            displayNameOverride: rootURL.lastPathComponent
        )
    }

    private static func markdownForNode(
        _ node: KnowledgeNode,
        attachmentsDirectoryURL: URL,
        attachmentsFolderName: String,
        usedAttachmentNames: inout Set<String>
    ) throws -> String {
        let region = RegionUIStore.runtimeRegion()
        var sections: [String] = []
        sections.append("# \(escapeMarkdown(node.title))")
        let categoryLabel: String
        let createdLabel: String
        let referenceCountLabel: String
        let knowledgeContentTitle: String
        let referencesTitle: String
        let noReferencesText: String
        switch region {
        case .taiwan:
            categoryLabel = "門類"
            createdLabel = "建立時間"
            referenceCountLabel = "參考資料數"
            knowledgeContentTitle = "## 知識內容"
            referencesTitle = "## 參考資料"
            noReferencesText = "目前沒有附加參考資料。"
        case .unitedStates:
            categoryLabel = "Category"
            createdLabel = "Created"
            referenceCountLabel = "Reference Count"
            knowledgeContentTitle = "## Knowledge Content"
            referencesTitle = "## References"
            noReferencesText = "No references attached."
        case .japan:
            categoryLabel = "分類"
            createdLabel = "作成日時"
            referenceCountLabel = "参考資料数"
            knowledgeContentTitle = "## 知識内容"
            referencesTitle = "## 参考資料"
            noReferencesText = "参考資料はありません。"
        }
        sections.append("""
        - \(categoryLabel)：\(KnowledgeCategory(rawValue: node.category)?.localizedName ?? node.category)
        - \(createdLabel)：\(displayDateFormatter.string(from: node.createdAt))
        - \(referenceCountLabel)：\(node.references?.count ?? 0)
        """)
        sections.append("""
        \(knowledgeContentTitle)

        \(node.content.trimmingCharacters(in: .whitespacesAndNewlines))
        """)

        let references = (node.references ?? []).sorted { $0.createdAt < $1.createdAt }
        if references.isEmpty {
            sections.append("\(referencesTitle)\n\n\(noReferencesText)")
        } else {
            var referenceSections: [String] = [referencesTitle]

            for reference in references {
                referenceSections.append(
                    try markdownForReference(
                        reference,
                        attachmentsDirectoryURL: attachmentsDirectoryURL,
                        attachmentsFolderName: attachmentsFolderName,
                        usedAttachmentNames: &usedAttachmentNames
                    )
                )
            }

            sections.append(referenceSections.joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private static func markdownForReference(
        _ reference: KnowledgeReference,
        attachmentsDirectoryURL: URL,
        attachmentsFolderName: String,
        usedAttachmentNames: inout Set<String>
    ) throws -> String {
        let region = RegionUIStore.runtimeRegion()
        var lines: [String] = []
        let typeLabel: String
        let createdLabel: String
        let linkLabel: String
        let attachmentLabel: String
        let missingAttachmentLabel: String
        let summaryTitle: String
        switch region {
        case .taiwan:
            typeLabel = "類型"
            createdLabel = "建立時間"
            linkLabel = "連結"
            attachmentLabel = "附件"
            missingAttachmentLabel = "本機檔案遺失"
            summaryTitle = "#### 摘要大綱"
        case .unitedStates:
            typeLabel = "Type"
            createdLabel = "Created"
            linkLabel = "Link"
            attachmentLabel = "Attachment"
            missingAttachmentLabel = "Local file missing"
            summaryTitle = "#### Summary"
        case .japan:
            typeLabel = "種類"
            createdLabel = "作成日時"
            linkLabel = "リンク"
            attachmentLabel = "添付"
            missingAttachmentLabel = "端末内ファイルが見つかりません"
            summaryTitle = "#### 要約"
        }
        lines.append("### \(escapeMarkdown(reference.title))")
        lines.append("- \(typeLabel)：\(reference.type.localizedName)")
        lines.append("- \(createdLabel)：\(displayDateFormatter.string(from: reference.createdAt))")

        switch reference.type {
        case .web:
            lines.append("- \(linkLabel)：\(reference.payload)")
        case .text:
            lines.append("")
            lines.append(reference.payload.trimmingCharacters(in: .whitespacesAndNewlines))
        case .image, .pdf, .audio:
            if let sourceURL = storedAttachmentURL(for: reference) {
                let exportedName = uniqueFileName(
                    base: safeFileStem(sourceURL.deletingPathExtension().lastPathComponent),
                    ext: sourceURL.pathExtension,
                    usedNames: &usedAttachmentNames
                )
                let targetURL = attachmentsDirectoryURL.appendingPathComponent(exportedName)
                try? FileManager.default.removeItem(at: targetURL)
                try FileManager.default.copyItem(at: sourceURL, to: targetURL)
                lines.append("- \(attachmentLabel)：[\(exportedName)](\(attachmentsFolderName)/\(exportedName))")
            } else {
                lines.append("- \(attachmentLabel)：\(missingAttachmentLabel)（\(reference.attachmentDisplayFileName)）")
            }
        }

        if let summary = reference.summaryOutline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            lines.append("")
            lines.append(summaryTitle)
            lines.append("")
            lines.append(summary)
        }

        return lines.joined(separator: "\n")
    }

    private static func storedAttachmentURL(for reference: KnowledgeReference) -> URL? {
        AttachmentStorageController.restoredLocalFileURL(for: reference)
    }

    private static func uniqueFileName(base: String, ext: String, usedNames: inout Set<String>) -> String {
        let sanitizedBase = base.isEmpty ? "untitled" : base
        var candidate = "\(sanitizedBase).\(ext)"
        var suffix = 2

        while usedNames.contains(candidate) {
            candidate = "\(sanitizedBase)-\(suffix).\(ext)"
            suffix += 1
        }

        usedNames.insert(candidate)
        return candidate
    }

    nonisolated private static func safeFileStem(_ text: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
        let collapsed = text
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return String(collapsed.prefix(64))
    }

    private static func escapeMarkdown(_ text: String) -> String {
        text.replacingOccurrences(of: "\n", with: " ")
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = RegionUIStore.runtimeLocale()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func localizedExportFolderStem() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "知識匯出"
        case .unitedStates:
            return "Export"
        case .japan:
            return "書き出し"
        }
    }

    private static func localizedAttachmentsFolderName() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "附件"
        case .unitedStates:
            return "attachments"
        case .japan:
            return "添付"
        }
    }
}
