import Foundation

enum OCRDisplayTextFormatter {
    nonisolated static func normalize(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map(normalizeLine)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func compactSummary(_ text: String, maxLength: Int) -> String {
        let normalized = normalize(text)
        guard !normalized.isEmpty else { return "" }

        let compact = normalize(
            normalized
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if compact.count <= maxLength { return compact }
        return String(compact.prefix(maxLength)) + "…"
    }

    nonisolated private static func normalizeLine(_ line: String) -> String {
        let collapsed = line
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "" }
        return removedUnnaturalSpaces(in: collapsed)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func removedUnnaturalSpaces(in text: String) -> String {
        let characters = Array(text)
        var output = ""

        for index in characters.indices {
            let character = characters[index]
            if character.isWhitespace {
                guard let previous = previousNonWhitespace(in: characters, before: index),
                      let next = nextNonWhitespace(in: characters, after: index) else {
                    continue
                }

                if shouldRemoveSpace(previous: previous, next: next) {
                    continue
                }

                if output.last != " " {
                    output.append(" ")
                }
                continue
            }

            output.append(character)
        }

        return output
    }

    nonisolated private static func previousNonWhitespace(in characters: [Character], before index: Int) -> Character? {
        guard index > 0 else { return nil }
        for probe in stride(from: index - 1, through: 0, by: -1) {
            let candidate = characters[probe]
            if !candidate.isWhitespace {
                return candidate
            }
        }
        return nil
    }

    nonisolated private static func nextNonWhitespace(in characters: [Character], after index: Int) -> Character? {
        guard index + 1 < characters.count else { return nil }
        for probe in (index + 1)..<characters.count {
            let candidate = characters[probe]
            if !candidate.isWhitespace {
                return candidate
            }
        }
        return nil
    }

    nonisolated private static func shouldRemoveSpace(previous: Character, next: Character) -> Bool {
        let previousIsEastAsian = isEastAsian(previous)
        let nextIsEastAsian = isEastAsian(next)

        if previousIsEastAsian && nextIsEastAsian {
            return true
        }

        if previousIsEastAsian && isClosingEastAsianPunctuation(next) {
            return true
        }

        if isOpeningEastAsianPunctuation(previous) && nextIsEastAsian {
            return true
        }

        return false
    }

    nonisolated private static func isEastAsian(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF,
                 0xFF66...0xFF9D:
                return true
            default:
                return false
            }
        }
    }

    nonisolated private static func isOpeningEastAsianPunctuation(_ character: Character) -> Bool {
        "([（【《〈「『〔［｛".contains(character)
    }

    nonisolated private static func isClosingEastAsianPunctuation(_ character: Character) -> Bool {
        ".,!?)]）】》〉」』〕］｝、。，！？：；".contains(character)
    }
}

enum ImportRecognitionMode: String, Codable, CaseIterable {
    case smartScan = "智慧辨識"

    var localizedLabel: String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "智慧辨識"
        case .unitedStates:
            return "Smart Scan"
        case .japan:
            return "スマート認識"
        }
    }

    var localizedDescription: String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "自動聚焦畫面中央主體，辨識教材、書頁、封面、商品或一般物件"
        case .unitedStates:
            return "Automatically focuses on the centered subject and recognizes textbooks, pages, covers, products, or everyday objects"
        case .japan:
            return "画面中央の主題を優先し、教材、書籍ページ、表紙、商品、日常物体をまとめて認識します"
        }
    }
}

enum KnowledgeImportSourceKind: String {
    case imageAI = "AI 圖像判讀"
    case imageOCR = "圖像辨識"
    case text = "文字來源"

    var localizedLabel: String {
        switch (self, RegionUIStore.runtimeRegion()) {
        case (.imageAI, .taiwan):
            return "AI 圖像判讀"
        case (.imageAI, .unitedStates):
            return "AI Image Analysis"
        case (.imageAI, .japan):
            return "AI画像解析"
        case (.imageOCR, .taiwan):
            return "圖像辨識"
        case (.imageOCR, .unitedStates):
            return "Image OCR"
        case (.imageOCR, .japan):
            return "画像OCR"
        case (.text, .taiwan):
            return "文字來源"
        case (.text, .unitedStates):
            return "Text Source"
        case (.text, .japan):
            return "テキストソース"
        }
    }

    var summaryTitle: String {
        switch (self, RegionUIStore.runtimeRegion()) {
        case (.imageAI, .taiwan):
            return "AI 圖像摘要"
        case (.imageAI, .unitedStates):
            return "AI Image Summary"
        case (.imageAI, .japan):
            return "AI画像要約"
        case (.imageOCR, .taiwan):
            return "OCR 輸出摘要"
        case (.imageOCR, .unitedStates):
            return "OCR Summary"
        case (.imageOCR, .japan):
            return "OCR要約"
        case (.text, .taiwan):
            return "文字摘要"
        case (.text, .unitedStates):
            return "Text Summary"
        case (.text, .japan):
            return "テキスト要約"
        }
    }
}

struct KnowledgeImportCandidate: Identifiable {
    let id: UUID
    let draft: SanitizedKnowledgeDraft
    let source: KnowledgeNodeInputSource

    init(id: UUID = UUID(), draft: SanitizedKnowledgeDraft, source: KnowledgeNodeInputSource = .ai) {
        self.id = id
        self.draft = draft
        self.source = source
    }
}

struct RejectedKnowledgeImportCandidate: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
}

struct KnowledgeImportPreview: Identifiable {
    let id = UUID()
    let recognitionMode: ImportRecognitionMode
    let source: KnowledgeImportSourceKind
    let extractedText: String?
    let sourceSummary: String?
    let filteredNoiseLineCount: Int
    let candidates: [KnowledgeImportCandidate]
    let rejected: [RejectedKnowledgeImportCandidate]

    var extractedTextSummary: String {
        guard let extractedText else { return "" }
        return OCRDisplayTextFormatter.compactSummary(extractedText, maxLength: 180)
    }

    var hasReviewDetails: Bool {
        !candidates.isEmpty
            || !rejected.isEmpty
            || (sourceSummary?.isEmpty == false)
            || !extractedTextSummary.isEmpty
    }
}

enum KnowledgeImportFallbackBuilder {
    private static let genericTitleLimit = 28
    private static let publicationTitleLimit = 64
    private struct PublicationTitleSelection {
        let candidate: String
        let lineIndex: Int
        let consumedLineCount: Int
        let score: Int
    }

    static func makeDraft(
        from text: String,
        suggestedTitle: String? = nil,
        category: KnowledgeCategory? = nil
    ) -> SanitizedKnowledgeDraft {
        let normalized = OCRDisplayTextFormatter.normalize(text)
        let title = cleanedTitle(from: suggestedTitle, fallbackText: normalized) ?? derivedTitle(from: normalized)
        let resolvedCategory = category
            ?? KnowledgeCategoryResolver.resolve(title: title, content: normalized)
            ?? .thinkingScience

        return SanitizedKnowledgeDraft(
            title: title,
            content: normalized,
            category: resolvedCategory
        )
    }

    private static func cleanedTitle(from suggestedTitle: String?, fallbackText: String) -> String? {
        guard let suggestedTitle else { return nil }
        let trimmed = cleanedTitleCandidate(suggestedTitle)

        guard !trimmed.isEmpty else { return nil }
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("ocr 摘要")
            || lowercased.hasPrefix("ocr summary")
            || lowercased.hasPrefix("ocr要約")
            || lowercased.hasPrefix("pdf 摘要")
            || lowercased.hasPrefix("pdf summary")
            || lowercased.hasPrefix("pdf要約") {
            return nil
        }

        let prefersPublicationTitle = isLikelyPublicationTitle(trimmed)
            || bestPublicationTitleCandidate(from: fallbackText) != nil
        let maxLength = prefersPublicationTitle ? publicationTitleLimit : genericTitleLimit
        let candidate = boundedTitle(trimmed, maxLength: maxLength)
        return isLikelyPublicationMetadataLine(candidate) ? nil : candidate
    }

    private static func derivedTitle(from text: String) -> String {
        if let publicationTitle = bestPublicationTitleCandidate(from: text) {
            return publicationTitle
        }

        let separators = CharacterSet(charactersIn: "。！？.!?\n")
        let firstSegment = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? text

        let compact = firstSegment
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if compact.isEmpty {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "整理知識點"
            case .unitedStates:
                return "Organized Knowledge"
            case .japan:
                return "整理した知識点"
            }
        }

        let candidate = boundedTitle(compact, maxLength: genericTitleLimit)

        if candidate.isEmpty {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "整理知識點"
            case .unitedStates:
                return "Organized Knowledge"
            case .japan:
                return "整理した知識点"
            }
        }
        return candidate
    }

    private static func bestPublicationTitleCandidate(from text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(cleanedTitleCandidate)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var bestSelection: PublicationTitleSelection?

        for index in lines.indices.prefix(8) {
            let single = lines[index]
            let singleScore = publicationTitleScore(for: single, lineIndex: index, isCombined: false)
            if bestSelection == nil || singleScore > bestSelection!.score {
                bestSelection = PublicationTitleSelection(
                    candidate: single,
                    lineIndex: index,
                    consumedLineCount: 1,
                    score: singleScore
                )
            }

            if isGenericPublicationTitleWithoutSubject(single) {
                for completed in completedGenericTitleSelections(
                    genericTitle: single,
                    lineIndex: index,
                    lines: lines
                ) {
                    if bestSelection == nil || completed.score > bestSelection!.score {
                        bestSelection = completed
                    }
                }
            }

            guard index + 1 < lines.count else { continue }
            let next = lines[index + 1]
            guard shouldCombinePublicationTitleLines(single, next: next) else { continue }

            let combined = cleanedTitleCandidate("\(single) \(next)")
            let combinedScore = publicationTitleScore(for: combined, lineIndex: index, isCombined: true)
            if bestSelection == nil || combinedScore > bestSelection!.score {
                bestSelection = PublicationTitleSelection(
                    candidate: combined,
                    lineIndex: index,
                    consumedLineCount: 2,
                    score: combinedScore
                )
            }
        }

        guard let selection = bestSelection, selection.score >= 18 else { return nil }
        let completedTitle = completedPublicationTitle(from: selection, lines: lines)
        let title = boundedTitle(completedTitle, maxLength: publicationTitleLimit)
        return title.isEmpty ? nil : title
    }

    private static func completedPublicationTitle(
        from selection: PublicationTitleSelection,
        lines: [String]
    ) -> String {
        let base = cleanedTitleCandidate(selection.candidate)
        guard isGenericPublicationTitleWithoutSubject(base) else { return base }

        var bestCandidate = base
        var bestScore = selection.score
        let consumedRange = selection.lineIndex..<(selection.lineIndex + selection.consumedLineCount)

        for index in lines.indices {
            guard !consumedRange.contains(index) else { continue }
            guard abs(index - selection.lineIndex) <= 2 else { continue }

            let subject = cleanedTitleCandidate(lines[index])
            guard isLikelySubjectLine(subject) else { continue }

            let orderedCandidates = mergedPublicationTitleCandidates(
                subject: subject,
                genericTitle: base,
                subjectIndex: index,
                titleIndex: selection.lineIndex
            )

            for merged in orderedCandidates {
                let mergedScore = publicationTitleScore(
                    for: merged,
                    lineIndex: min(index, selection.lineIndex),
                    isCombined: true
                ) + 6
                if mergedScore > bestScore {
                    bestScore = mergedScore
                    bestCandidate = merged
                }
            }
        }

        return bestCandidate
    }

    private static func mergedPublicationTitleCandidates(
        subject: String,
        genericTitle: String,
        subjectIndex: Int,
        titleIndex: Int
    ) -> [String] {
        let subjectFirst = cleanedTitleCandidate("\(subject) \(genericTitle)")
        let titleFirst = cleanedTitleCandidate("\(genericTitle) \(subject)")

        if subjectIndex < titleIndex {
            return [subjectFirst, titleFirst]
        }

        return [titleFirst, subjectFirst]
    }

    private static func completedGenericTitleSelections(
        genericTitle: String,
        lineIndex: Int,
        lines: [String]
    ) -> [PublicationTitleSelection] {
        let preferredIndices = nearbySubjectIndices(around: lineIndex, in: lines)
        guard !preferredIndices.isEmpty else { return [] }

        return preferredIndices.flatMap { index in
            let subject = cleanedTitleCandidate(lines[index])
            return mergedPublicationTitleCandidates(
                subject: subject,
                genericTitle: genericTitle,
                subjectIndex: index,
                titleIndex: lineIndex
            ).map { merged in
                PublicationTitleSelection(
                    candidate: merged,
                    lineIndex: min(index, lineIndex),
                    consumedLineCount: 2,
                    score: publicationTitleScore(
                        for: merged,
                        lineIndex: min(index, lineIndex),
                        isCombined: true
                    ) + 8
                )
            }
        }
    }

    private static func nearbySubjectIndices(around lineIndex: Int, in lines: [String]) -> [Int] {
        let previous = stride(from: lineIndex - 1, through: max(0, lineIndex - 2), by: -1)
            .filter { index in
                let subject = cleanedTitleCandidate(lines[index])
                return isLikelySubjectLine(subject)
            }
        if !previous.isEmpty {
            return Array(previous)
        }

        return ((lineIndex + 1)..<min(lines.count, lineIndex + 3))
            .filter { index in
                let subject = cleanedTitleCandidate(lines[index])
                return isLikelySubjectLine(subject)
            }
    }

    private static func shouldCombinePublicationTitleLines(_ current: String, next: String) -> Bool {
        guard !isLikelyPublicationMetadataLine(current),
              !isLikelyPublicationMetadataLine(next) else {
            return false
        }

        let combined = "\(current) \(next)"
        guard combined.count <= 72 else { return false }
        guard current.count >= 4, next.count >= 4 else { return false }
        guard current.range(of: #"https?://|www\.|isbn|issn|doi"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }
        guard next.range(of: #"https?://|www\.|isbn|issn|doi"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return false
        }

        let nextLowercased = next.lowercased()
        if nextLowercased.hasPrefix("by ") || nextLowercased.hasPrefix("author") {
            return false
        }

        return true
    }

    private static func publicationTitleScore(for candidate: String, lineIndex: Int, isCombined: Bool) -> Int {
        let normalized = cleanedTitleCandidate(candidate)
        guard !normalized.isEmpty else { return Int.min }
        guard !isLikelyPublicationMetadataLine(normalized) else { return Int.min }

        var score = 0
        let length = normalized.count
        let scalars = normalized.unicodeScalars.filter { !$0.properties.isWhitespace }
        let letters = scalars.filter { CharacterSet.letters.contains($0) }
        let cjk = scalars.filter(isEastAsian)
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }
        let digitRatio = Double(digits.count) / Double(max(scalars.count, 1))

        if (6...60).contains(length) { score += 10 }
        if (10...42).contains(length) { score += 8 }
        score += max(0, 8 - lineIndex * 2)
        if isCombined { score += 4 }
        if letters.count + cjk.count >= 8 { score += 8 }
        if digitRatio < 0.12 { score += 4 } else { score -= 8 }

        if normalized.contains(":") || normalized.contains("：") || normalized.contains(" - ") || normalized.contains("｜") {
            score += 4
        }

        let lowercased = normalized.lowercased()
        let publicationSignals = [
            "journal", "review", "guide", "manual", "handbook", "introduction",
            "fundamentals", "design", "analysis", "system", "theory",
            "研究", "導論", "指南", "手冊", "設計", "分析", "系統", "理論",
            "入門", "実践", "基礎", "ガイド", "マニュアル", "レビュー"
        ]
        score += publicationSignals.filter { lowercased.contains($0) }.count * 2
        if isGenericPublicationTitleWithoutSubject(normalized) {
            score -= 10
        }
        if hasGenericPublicationTitlePrefixWithoutSubject(normalized) {
            score -= 12
        }
        if hasSubjectPlusGenericTitleShape(normalized) {
            score += 6
        }

        let tokenCount = normalized
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
            .count
        if (2...12).contains(tokenCount) { score += 4 }

        return score
    }

    nonisolated private static func cleanedTitleCandidate(_ text: String) -> String {
        OCRDisplayTextFormatter.normalize(text)
            .replacingOccurrences(of: #"^\p{P}+|\p{P}+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[\|\•·●]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func boundedTitle(_ title: String, maxLength: Int) -> String {
        let trimmed = cleanedTitleCandidate(title)
        guard trimmed.count > maxLength else { return trimmed }

        let prefix = String(trimmed.prefix(maxLength))
        if let lastSpace = prefix.lastIndex(of: " "), lastSpace > prefix.startIndex {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        }

        return prefix.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func isLikelyPublicationTitle(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        if title.count >= 18 { return true }
        if title.contains(":") || title.contains("：") { return true }
        let signals = ["journal", "review", "guide", "manual", "研究", "指南", "手冊", "入門", "基礎", "ガイド", "マニュアル"]
        return signals.contains { lowercased.contains($0) }
    }

    private static func isGenericPublicationTitleWithoutSubject(_ title: String) -> Bool {
        let normalized = cleanedTitleCandidate(title)
        guard !normalized.isEmpty else { return false }

        let lowercased = normalized.lowercased()
        let englishGenericPatterns = englishGenericTitlePatterns
        if englishGenericPatterns.contains(where: {
            lowercased.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return true
        }

        return genericEastAsianTitleMarkers.contains(normalized)
    }

    private static func hasGenericPublicationTitlePrefixWithoutSubject(_ title: String) -> Bool {
        let normalized = cleanedTitleCandidate(title)
        guard !normalized.isEmpty else { return false }

        let lowercased = normalized.lowercased()
        let englishPrefixPatterns = [
            #"^(study guide|guide|user guide|manual|handbook|introduction|fundamentals|basics|quick start( guide)?)(\b|[:：\-])"#
        ]
        if englishPrefixPatterns.contains(where: {
            lowercased.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return true
        }

        return genericEastAsianTitleMarkers.contains(where: { marker in
            normalized.hasPrefix(marker) && normalized != marker
        })
    }

    private static func hasSubjectPlusGenericTitleShape(_ title: String) -> Bool {
        let normalized = cleanedTitleCandidate(title)
        guard !normalized.isEmpty else { return false }

        let lowercased = normalized.lowercased()
        let englishSuffixPatterns = [
            #".+\b(study guide|guide|user guide|manual|handbook|introduction|fundamentals|basics|quick start( guide)?)$"#
        ]
        if englishSuffixPatterns.contains(where: {
            lowercased.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return true
        }

        return genericEastAsianTitleMarkers.contains(where: { marker in
            normalized.hasSuffix(marker) && normalized != marker
        })
    }

    private static let englishGenericTitlePatterns = [
            #"^study guide$"#,
            #"^guide$"#,
            #"^user guide$"#,
            #"^manual$"#,
            #"^handbook$"#,
            #"^introduction$"#,
            #"^fundamentals$"#,
            #"^basics$"#,
            #"^quick start( guide)?$"#
        ]
    
    private static let genericEastAsianTitleMarkers: Set<String> = [
            "學習指南", "指南", "使用指南", "操作指南", "手冊", "使用手冊",
            "入門", "基礎", "導論", "學習手冊",
            "学習ガイド", "ガイド", "ユーザーガイド", "マニュアル",
            "ハンドブック", "入門", "基礎", "手引き", "案内"
        ]
    

    private static func isLikelySubjectLine(_ line: String) -> Bool {
        let normalized = cleanedTitleCandidate(line)
        guard !normalized.isEmpty else { return false }
        guard !isLikelyPublicationMetadataLine(normalized) else { return false }
        guard !isGenericPublicationTitleWithoutSubject(normalized) else { return false }
        guard normalized.count >= 2, normalized.count <= 48 else { return false }

        let lowercased = normalized.lowercased()
        if lowercased.hasPrefix("by ") || lowercased.hasPrefix("author") {
            return false
        }

        let scalars = normalized.unicodeScalars.filter { !$0.properties.isWhitespace }
        let letters = scalars.filter { CharacterSet.letters.contains($0) || isEastAsian($0) }
        let digits = scalars.filter { CharacterSet.decimalDigits.contains($0) }
        let digitRatio = Double(digits.count) / Double(max(scalars.count, 1))

        guard letters.count >= 2, digitRatio < 0.18 else { return false }
        return true
    }

    private static func isLikelyPublicationMetadataLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let metadataSignals = [
            "isbn", "issn", "doi", "copyright", "all rights reserved", "publisher", "published",
            "volume", "issue", "vol.", "no.", "pp.", "page ", "pages ", "www.", "http://", "https://",
            "出版社", "版權", "著作權", "定價", "頁碼", "國際標準書號", "巻", "号", "価格", "発行"
        ]

        let signalCount = metadataSignals.filter { lowercased.contains($0) }.count
        if signalCount >= 1 { return true }

        let datePattern = #"(19|20)\d{2}([/\-.年])\d{1,2}"#
        if lowercased.range(of: datePattern, options: .regularExpression) != nil {
            return true
        }

        let pricePattern = #"[¥$€£]\s?\d+|\d+\s?(nt\$|usd|jpy|円|元)"#
        return lowercased.range(of: pricePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated private static func isEastAsian(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF,
             0xFF66...0xFF9D:
            return true
        default:
            return false
        }
    }
}
