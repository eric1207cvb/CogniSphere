import Foundation
import CoreImage
import PDFKit
import SwiftData
import UIKit
import Vision // 👈 引入 Apple 最強的視覺 AI 框架

struct AIKnowledgeResponse: Decodable {
    let sourceSummary: String?
    let nodes: [AINodeDTO]

    private enum CodingKeys: String, CodingKey {
        case sourceSummary = "source_summary"
        case nodes
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case ocrSummary = "ocr_summary"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        sourceSummary = try container.decodeIfPresent(String.self, forKey: .sourceSummary)
            ?? legacyContainer.decodeIfPresent(String.self, forKey: .ocrSummary)
        nodes = try container.decodeIfPresent([AINodeDTO].self, forKey: .nodes) ?? []
    }

    init(sourceSummary: String?, nodes: [AINodeDTO]) {
        self.sourceSummary = sourceSummary
        self.nodes = nodes
    }
}

struct AINodeDTO: Codable {
    let title: String
    let content: String
    let category: String
}

private struct OCRSummaryResponse: Codable {
    let ocrSummary: String?
    let verificationNote: String?

    enum CodingKeys: String, CodingKey {
        case ocrSummary = "ocr_summary"
        case verificationNote = "verification_note"
    }
}

struct ReferenceImageOCRResult {
    let title: String
    let content: String
    let verificationNote: String?
}

struct KnowledgeSaveSelectionResult {
    let insertedCount: Int
    let didAutoArchive: Bool
}

private struct OCRDocumentRepairResponse: Codable {
    let documentText: String?
    let documentType: String?
    let confidenceNote: String?

    enum CodingKeys: String, CodingKey {
        case documentText = "document_text"
        case documentType = "document_type"
        case confidenceNote = "confidence_note"
    }
}

private enum PDFSummaryPreparationError: LocalizedError {
    case noReadableText
    case unsupportedSummarySource
    case aiSummaryUnavailable

    var errorDescription: String? {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            switch self {
            case .noReadableText:
                return "這份 PDF 沒有擷取到可摘要的文字內容。若是掃描版文件，請確認頁面清晰後再試一次。"
            case .unsupportedSummarySource:
                return "這份 PDF 沒有偵測到足夠可摘要的中、英、日內容，因此暫時不生成摘要。"
            case .aiSummaryUnavailable:
                return "AI 目前無法生成這份 PDF 的摘要，請稍後再試。"
            }
        case .unitedStates:
            switch self {
            case .noReadableText:
                return "No readable PDF text was extracted. If this is a scanned file, please try again with clearer pages."
            case .unsupportedSummarySource:
                return "This PDF does not contain enough Chinese, English, or Japanese content to summarize yet."
            case .aiSummaryUnavailable:
                return "AI could not generate a PDF summary right now. Please try again later."
            }
        case .japan:
            switch self {
            case .noReadableText:
                return "要約できる文字をPDFから抽出できませんでした。スキャンPDFの場合は、より鮮明なページで再度お試しください。"
            case .unsupportedSummarySource:
                return "このPDFには要約に十分な中英日テキストがありません。"
            case .aiSummaryUnavailable:
                return "現在AIでPDF要約を生成できません。しばらくしてからもう一度お試しください。"
            }
        }
    }
}

actor KnowledgeTitleIndexStore {
    static let shared = KnowledgeTitleIndexStore()

    private var normalizedTitles = Set<String>()
    private var isLoaded = false

    func state() -> (isLoaded: Bool, titles: Set<String>) {
        (isLoaded, normalizedTitles)
    }

    func replace(with titles: Set<String>) {
        normalizedTitles = titles
        isLoaded = true
    }

    func register(normalizedTitles titles: [String]) {
        normalizedTitles.formUnion(titles)
        isLoaded = true
    }
}

@MainActor
func loadKnowledgeTitleSnapshot(using modelContext: ModelContext) async -> Set<String> {
    let state = await KnowledgeTitleIndexStore.shared.state()
    if state.isLoaded {
        return state.titles
    }

    let descriptor = FetchDescriptor<KnowledgeNode>()
    let nodes = (try? modelContext.fetch(descriptor)) ?? []
    let snapshot = Set(nodes.map { KnowledgeNodeCleaner.normalizedKey(for: $0.title) })
    await KnowledgeTitleIndexStore.shared.replace(with: snapshot)
    return snapshot
}

@MainActor
func refreshKnowledgeTitleSnapshot(using modelContext: ModelContext) async {
    let descriptor = FetchDescriptor<KnowledgeNode>()
    let nodes = (try? modelContext.fetch(descriptor)) ?? []
    let snapshot = Set(nodes.map { KnowledgeNodeCleaner.normalizedKey(for: $0.title) })
    await KnowledgeTitleIndexStore.shared.replace(with: snapshot)
}

final class KnowledgeExtractionService {
    static let shared = KnowledgeExtractionService()
    private static let requestTimeout: TimeInterval = 25
    private static let retryableStatusCodes: Set<Int> = [408, 425, 429, 500, 502, 503, 504]

    private enum ProtectedRequestKind: String {
        case smartScan = "smart_scan"
        case referenceImageOCR = "reference_image_ocr"
        case pdfSummary = "pdf_summary"
        case ocrRepair = "ocr_repair"
    }

    private enum OCRRepairPurpose {
        case knowledgeImport
        case referenceSummary
        case pdfSummary
    }
    
    // ✅ 直接使用你目前正在服役的 WonderKid 伺服器，不用改後端！
    private static let serverURL = URL(string: "https://wonderkidai-server.onrender.com/api/chat")!
    private static let ocrNoiseFragments = [
        "http://", "https://", "www.", ".com", ".tw", "isbn", "issn", "doi",
        "all rights reserved", "copyright", "printed in", "scan me", "qr code",
        "版權", "出版社", "頁碼", "國際標準書號"
    ]
    private static let educationalDocumentTerms = [
        "textbook", "chapter", "section", "exercise", "theorem", "definition", "lecture",
        "course", "curriculum", "syllabus", "worksheet", "handout", "lesson", "unit",
        "module", "lab manual", "problem set", "introduction to", "fundamentals", "edition",
        "教科書", "教材", "課本", "課程", "講義", "章節", "習題", "例題", "定理", "定義",
        "導論", "入門", "實驗", "研究", "論文", "章", "節", "概論", "教學", "單元",
        "テキスト", "教科書", "教材", "講義", "章", "節", "演習", "定理", "定義", "入門"
    ]
    private static let generalDocumentTerms = [
        "journal", "article", "paper", "abstract", "introduction", "methods", "results", "discussion",
        "magazine", "newspaper", "headline", "column", "editorial", "advertisement", "brochure",
        "manual", "instructions", "guide", "specification", "warnings", "precautions", "ingredients",
        "periodical", "supplement", "review", "appendix", "table of contents",
        "期刊", "論文", "文章", "摘要", "前言", "方法", "結果", "討論", "結論", "雜誌",
        "報紙", "社論", "廣告", "型錄", "手冊", "說明書", "規格", "注意事項", "警告", "成分",
        "目錄", "附錄", "研究摘要", "專欄",
        "雑誌", "新聞", "論文", "要旨", "序論", "方法", "結果", "考察", "結論", "広告",
        "パンフレット", "マニュアル", "取扱説明書", "仕様", "注意事項", "警告", "目次", "付録"
    ]
    private static let incidentalPackagingTerms = [
        "coffee", "latte", "espresso", "cappuccino", "mocha", "arabica", "roast", "bean",
        "beverage", "drink", "tea", "milk", "sugar", "calories", "nutrition", "ingredients",
        "bottle", "can", "cup", "mug", "ml", "fl oz", "cafe", "brew",
        "咖啡", "拿鐵", "濃縮", "飲料", "瓶裝", "罐裝", "成分", "營養", "熱量", "毫升",
        "茶飲", "牛奶", "砂糖", "咖啡豆", "烘焙",
        "コーヒー", "ラテ", "エスプレッソ", "飲料", "ボトル", "缶", "成分", "栄養", "カロリー"
    ]

    private struct ImagePayloadProfile {
        let maxDimension: CGFloat
        let maxBytes: Int
        let detail: String
    }

    struct EducationalCoverProfile {
        let title: String
        let subtitle: String?
        let audienceHint: String?
    }

    func prepareNoteImageImport(
        image: UIImage,
        mode: ImportRecognitionMode,
        existingTitles: Set<String>
    ) async throws -> KnowledgeImportPreview? {
        let importStart = CFAbsoluteTimeGetCurrent()
        let ocrStart = CFAbsoluteTimeGetCurrent()
        let rawExtractedText = try await extractBestTextFromImage(image: image)
        await PerformanceTraceRecorder.shared.record(
            name: "note_import_ocr",
            durationMs: elapsedDurationMs(since: ocrStart),
            metadata: ["raw_chars": "\(rawExtractedText.count)"]
        )

        let cleanedOCR = cleanedOCRText(from: rawExtractedText)
        let extractedText = cleanedOCR.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let salvagedText = salvagedVerticalCJKText(from: rawExtractedText)
        let preferredOCRText = preferredImportOCRText(
            cleanedText: extractedText,
            cleaningResult: cleanedOCR,
            salvagedText: salvagedText
        )
        let repairedPreferredOCRText: String?
        if let preferredOCRText {
            repairedPreferredOCRText = await repairedOCRTextIfNeeded(
                preferredOCRText,
                rawText: rawExtractedText,
                purpose: .knowledgeImport
            )
        } else {
            repairedPreferredOCRText = nil
        }
        let reviewFallbackText = reviewableImportOCRText(
            cleanedText: extractedText,
            salvagedText: salvagedText,
            rawText: rawExtractedText
        )
        let shouldBypassAIExpansion = repairedPreferredOCRText.map {
            shouldBypassAIKnowledgeExpansion(
                for: $0,
                cleaningResult: cleanedOCR
            )
        } ?? false
        let coverHintText = normalizedDocumentCoverHint(
            preferredOCRText: repairedPreferredOCRText,
            fallbackOCRText: reviewFallbackText
        )
        let shouldPrioritizeCoverImageAI = coverHintText.map(looksLikeEducationalCoverText) ?? false
        let directCoverCandidate = coverHintText.flatMap {
            textbookCoverFallbackCandidate(
                from: $0,
                recognitionMode: mode,
                existingTitles: existingTitles
            )
        }

        if let directCoverCandidate, shouldPrioritizeCoverImageAI {
            let preview = KnowledgeImportPreview(
                recognitionMode: mode,
                source: .imageOCR,
                extractedText: coverHintText,
                sourceSummary: normalizedOCRSummary(nil, fallbackFrom: coverHintText ?? ""),
                filteredNoiseLineCount: cleanedOCR.filteredLineCount,
                candidates: [directCoverCandidate],
                rejected: []
            )

            await PerformanceTraceRecorder.shared.record(
                name: "note_import_total",
                durationMs: elapsedDurationMs(since: importStart),
                metadata: [
                    "candidates": "1",
                    "rejected": "0",
                    "mode": "cover_direct"
                ]
            )
            return preview
        }

        let result: AIKnowledgeResponse
        let sourceKind: KnowledgeImportSourceKind
        let sourceSummary: String?
        let extractedTextForPreview: String?
        let filteredNoiseLineCount: Int

        if let repairedPreferredOCRText, !shouldBypassAIExpansion {
            result = try await requestKnowledgeFromOCRText(repairedPreferredOCRText, mode: mode)
            sourceKind = .imageOCR
            sourceSummary = normalizedOCRSummary(result.sourceSummary, fallbackFrom: repairedPreferredOCRText)
            extractedTextForPreview = repairedPreferredOCRText
            filteredNoiseLineCount = cleanedOCR.filteredLineCount
        } else if shouldPrioritizeCoverImageAI {
            result = try await requestKnowledgeFromImage(
                image,
                mode: mode,
                supportingOCRText: coverHintText,
                prioritizeDocumentCover: true
            )
            sourceKind = .imageAI
            sourceSummary = normalizedSourceSummary(result.sourceSummary)
                ?? normalizedOCRSummary(nil, fallbackFrom: coverHintText ?? reviewFallbackText ?? "")
            extractedTextForPreview = coverHintText ?? reviewFallbackText
            filteredNoiseLineCount = cleanedOCR.filteredLineCount
        } else if let repairedPreferredOCRText {
            result = AIKnowledgeResponse(sourceSummary: nil, nodes: [])
            sourceKind = .imageOCR
            sourceSummary = normalizedOCRSummary(nil, fallbackFrom: repairedPreferredOCRText)
            extractedTextForPreview = repairedPreferredOCRText
            filteredNoiseLineCount = cleanedOCR.filteredLineCount
        } else {
            result = try await requestKnowledgeFromImage(image, mode: mode)
            sourceKind = .imageAI
            sourceSummary = normalizedSourceSummary(result.sourceSummary)
                ?? normalizedOCRSummary(nil, fallbackFrom: reviewFallbackText ?? "")
            extractedTextForPreview = reviewFallbackText
            filteredNoiseLineCount = cleanedOCR.filteredLineCount
        }

        let preview = buildKnowledgeImportPreview(
            result: result,
            recognitionMode: mode,
            existingTitles: existingTitles,
            source: sourceKind,
            extractedText: extractedTextForPreview,
            sourceSummary: sourceSummary,
            filteredNoiseLineCount: filteredNoiseLineCount
        )
        let finalizedPreview = previewWithFallbackCandidateIfNeeded(
            preview,
            recognitionMode: mode,
            existingTitles: existingTitles,
            fallbackText: reviewFallbackText ?? repairedPreferredOCRText ?? sourceSummary,
            rawExtractedText: rawExtractedText
        )

        await PerformanceTraceRecorder.shared.record(
            name: "note_import_total",
            durationMs: elapsedDurationMs(since: importStart),
            metadata: [
                "candidates": "\(finalizedPreview.candidates.count)",
                "rejected": "\(finalizedPreview.rejected.count)",
                "mode": sourceKind == .imageOCR ? "ocr_plus_ai" : "image_ai_fallback"
            ]
        )
        return finalizedPreview
    }

    private func preferredImportOCRText(
        cleanedText: String,
        cleaningResult: OCRCleaningResult,
        salvagedText: String
    ) -> String? {
        let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if shouldPreferOCRPrimaryPath(cleanedText: trimmed, cleaningResult: cleaningResult) {
            return trimmed
        }

        let salvagedCleaning = OCRCleaningResult(cleanedText: salvagedText, filteredLineCount: 0)
        if shouldCreateReferenceOCR(from: salvagedText, cleaningResult: salvagedCleaning) {
            return salvagedText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func reviewableImportOCRText(
        cleanedText: String,
        salvagedText: String,
        rawText: String
    ) -> String? {
        let trimmed = OCRDisplayTextFormatter.normalize(cleanedText)
        if trimmed.count >= 24 {
            return trimmed
        }

        let salvaged = OCRDisplayTextFormatter.normalize(salvagedText)
        if salvaged.count >= 24 {
            return salvaged
        }

        let normalizedRaw = OCRDisplayTextFormatter.normalize(normalizedOCRLine(rawText))
        if normalizedRaw.count >= 40 {
            return String(normalizedRaw.prefix(220))
        }

        return nil
    }

    private func previewWithFallbackCandidateIfNeeded(
        _ preview: KnowledgeImportPreview,
        recognitionMode: ImportRecognitionMode,
        existingTitles: Set<String>,
        fallbackText: String?,
        rawExtractedText: String
    ) -> KnowledgeImportPreview {
        guard preview.candidates.isEmpty else { return preview }

        guard let normalizedFallback = fallbackImportText(
            explicitFallback: fallbackText,
            preview: preview,
            rawExtractedText: rawExtractedText
        ) else {
            return preview
        }

        guard let fallbackCandidate = fallbackImportCandidate(
            from: normalizedFallback,
            recognitionMode: recognitionMode,
            existingTitles: existingTitles,
            titleHint: preview.sourceSummary
        ) else {
            return preview
        }

        return KnowledgeImportPreview(
            recognitionMode: preview.recognitionMode,
            source: preview.source,
            extractedText: preview.extractedText ?? normalizedFallback,
            sourceSummary: preview.sourceSummary ?? normalizedOCRSummary(nil, fallbackFrom: normalizedFallback),
            filteredNoiseLineCount: preview.filteredNoiseLineCount,
            candidates: [fallbackCandidate],
            rejected: preview.rejected
        )
    }

    private func shouldBypassAIKnowledgeExpansion(
        for text: String,
        cleaningResult: OCRCleaningResult
    ) -> Bool {
        let normalized = OCRDisplayTextFormatter.normalize(text)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map(OCRDisplayTextFormatter.normalize)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return true }

        let score = cleanedOCRScore(for: normalized)
        let noisePenalty = estimatedOCRNoisePenalty(for: normalized)
        let informativeLineCount = lines.filter { !isLikelyOCRNoiseLine($0) }.count
        let suspiciousFragmentLineCount = lines.filter(isSuspiciousCJKFragmentLine).count
        let filteredRatio = Double(cleaningResult.filteredLineCount) / Double(max(lines.count + cleaningResult.filteredLineCount, 1))

        if score < 52 {
            return true
        }

        if normalized.count < 140 && informativeLineCount < 3 {
            return true
        }

        if noisePenalty >= max(6, informativeLineCount * 3) {
            return true
        }

        if suspiciousFragmentLineCount >= 1 && informativeLineCount < 4 {
            return true
        }

        if filteredRatio > 0.35 && normalized.count < 220 {
            return true
        }

        return false
    }

    private func normalizedDocumentCoverHint(
        preferredOCRText: String?,
        fallbackOCRText: String?
    ) -> String? {
        let candidates = [preferredOCRText, fallbackOCRText]
        for candidate in candidates {
            guard let candidate else { continue }
            let normalized = OCRDisplayTextFormatter.normalize(candidate)
            guard normalized.count >= 12 else { continue }
            return normalized.count > 320 ? String(normalized.prefix(320)) : normalized
        }
        return nil
    }

    private func fallbackImportText(
        explicitFallback: String?,
        preview: KnowledgeImportPreview,
        rawExtractedText: String
    ) -> String? {
        let rawLine = OCRDisplayTextFormatter.normalize(normalizedOCRLine(rawExtractedText))
        let candidates = [
            explicitFallback,
            preview.extractedText,
            preview.sourceSummary,
            normalizedOCRSummary(nil, fallbackFrom: rawExtractedText),
            rawLine
        ]

        var firstLongCandidate: String?
        for candidate in candidates {
            let normalized = candidate.map(OCRDisplayTextFormatter.normalize)
            guard let normalized, normalized.count >= 40 else { continue }

            let clipped = normalized.count > 1400 ? String(normalized.prefix(1400)) : normalized
            if firstLongCandidate == nil {
                firstLongCandidate = clipped
            }

            if isReadableFallbackImportText(clipped) {
                return clipped
            }
        }

        return firstLongCandidate.flatMap { isReadableFallbackImportText($0) ? $0 : nil }
    }

    private func fallbackImportCandidate(
        from text: String,
        recognitionMode: ImportRecognitionMode,
        existingTitles: Set<String>,
        titleHint: String?
    ) -> KnowledgeImportCandidate? {
        if let textbookCoverCandidate = textbookCoverFallbackCandidate(
            from: text,
            recognitionMode: recognitionMode,
            existingTitles: existingTitles
        ) {
            return textbookCoverCandidate
        }

        let fallbackContent = preferredFallbackCandidateText(
            fallbackText: text,
            titleHint: titleHint
        )
        let draft = KnowledgeImportFallbackBuilder.makeDraft(
            from: fallbackContent,
            suggestedTitle: titleHint
        )
        let validation = KnowledgeNodeCleaner.validate(
            title: draft.title,
            content: draft.content,
            categoryRaw: draft.category.rawValue,
            source: .manual,
            existingTitles: existingTitles
        )

        guard let sanitizedDraft = validation.draft else { return nil }
        return KnowledgeImportCandidate(draft: sanitizedDraft, source: .manual)
    }

    private func preferredFallbackCandidateText(
        fallbackText: String,
        titleHint: String?
    ) -> String {
        let normalizedFallback = OCRDisplayTextFormatter.normalize(fallbackText)
        if isReadableFallbackImportText(normalizedFallback) {
            return normalizedFallback
        }

        if let titleHint {
            let normalizedHint = OCRDisplayTextFormatter.normalize(titleHint)
            if normalizedHint.count >= 20 {
                return normalizedHint
            }
        }

        return normalizedFallback
    }

    private func isReadableFallbackImportText(_ text: String) -> Bool {
        let normalized = OCRDisplayTextFormatter.normalize(text)
        let lines = normalized
            .components(separatedBy: .newlines)
            .map(OCRDisplayTextFormatter.normalize)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return false }

        let visibleScalars = normalized.unicodeScalars.filter { !$0.properties.isWhitespace }
        let visibleCount = visibleScalars.count
        guard visibleCount >= 24 else { return false }

        let letterLikeCount = visibleScalars.filter { CharacterSet.letters.contains($0) }.count
        let cjkLikeCount = visibleScalars.filter {
            (0x3400...0x4DBF).contains($0.value) ||
            (0x4E00...0x9FFF).contains($0.value) ||
            (0xF900...0xFAFF).contains($0.value) ||
            (0x3040...0x309F).contains($0.value) ||
            (0x30A0...0x30FF).contains($0.value) ||
            (0x31F0...0x31FF).contains($0.value)
        }.count
        let digitCount = visibleScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = visibleScalars.filter {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }.count

        let digitRatio = Double(digitCount) / Double(max(visibleCount, 1))
        let punctuationRatio = Double(punctuationCount) / Double(max(visibleCount, 1))
        let informativeLineCount = lines.filter { !isLikelyOCRNoiseLine($0) }.count
        let suspiciousFragmentLineCount = lines.filter(isSuspiciousCJKFragmentLine).count
        let noisePenalty = estimatedOCRNoisePenalty(for: normalized)

        guard letterLikeCount >= 12 || cjkLikeCount >= 8 else { return false }
        guard digitRatio < 0.42 else { return false }
        guard punctuationRatio < 0.36 else { return false }
        guard informativeLineCount >= 1 else { return false }

        if suspiciousFragmentLineCount >= max(2, lines.count - 1) && informativeLineCount < 3 {
            return false
        }

        if noisePenalty >= max(8, lines.count * 4) {
            return false
        }

        return informativeLineCount >= 2 || normalized.count >= 80
    }

    private func isSuspiciousCJKFragmentLine(_ line: String) -> Bool {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.count >= 5 else { return false }

        let singleCharacterCJKTokens = tokens.filter { token in
            let scalars = token.unicodeScalars
            guard scalars.count == 1 else { return false }
            guard let scalar = scalars.first else { return false }
            return (0x3400...0x4DBF).contains(scalar.value)
                || (0x4E00...0x9FFF).contains(scalar.value)
                || (0xF900...0xFAFF).contains(scalar.value)
                || (0x3040...0x309F).contains(scalar.value)
                || (0x30A0...0x30FF).contains(scalar.value)
                || (0x31F0...0x31FF).contains(scalar.value)
        }.count

        return singleCharacterCJKTokens * 2 >= tokens.count
    }

    private func textbookCoverFallbackCandidate(
        from text: String,
        recognitionMode: ImportRecognitionMode,
        existingTitles: Set<String>
    ) -> KnowledgeImportCandidate? {
        let _ = recognitionMode
        guard looksLikeEducationalCoverText(text) else { return nil }
        guard let profile = educationalCoverProfile(from: text) else { return nil }

        let category = KnowledgeCategoryResolver.resolve(title: profile.title, content: text) ?? .naturalScience
        let content = localizedEducationalCoverSummary(profile: profile, text: text, category: category)
        let validation = KnowledgeNodeCleaner.validate(
            title: profile.title,
            content: content,
            categoryRaw: category.rawValue,
            source: .manual,
            existingTitles: existingTitles
        )

        guard let sanitizedDraft = validation.draft else { return nil }
        return KnowledgeImportCandidate(draft: sanitizedDraft, source: .manual)
    }

    private func looksLikeEducationalCoverText(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let educationalHits = Self.educationalDocumentTerms.filter { lowered.contains($0.lowercased()) }.count
        let coverSignals = [
            "edition", "international edition", "pearson", "prentice", "chapter",
            "textbook", "principles", "introduction", "fundamentals",
            "教科書", "教材", "課本", "章", "節",
            "版", "第", "章節",
            "版", "入門", "基礎",
            "版", "章", "節"
        ].filter { lowered.contains($0.lowercased()) }.count
        return educationalHits >= 1 || coverSignals >= 2
    }

    func educationalCoverProfile(from text: String) -> EducationalCoverProfile? {
        let lines = text
            .components(separatedBy: .newlines)
            .map(normalizedOCRLine)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        let filtered = lines.enumerated().compactMap { index, line -> (index: Int, line: String)? in
            isCandidateEducationalCoverLine(line) ? (index, line) : nil
        }

        guard !filtered.isEmpty else { return nil }

        if let prioritizedSelection = prioritizedEducationalCoverSelection(from: filtered) {
            let subtitle = extractedEducationalSubtitle(
                from: filtered,
                titleStartIndex: prioritizedSelection.startIndex,
                consumedCount: prioritizedSelection.consumedCount,
                title: prioritizedSelection.title
            )
            let audienceHint = extractedEducationalAudienceHint(
                from: filtered.map(\.line),
                excluding: [prioritizedSelection.title, subtitle].compactMap { $0 }
            )
            return EducationalCoverProfile(
                title: prioritizedSelection.title,
                subtitle: subtitle,
                audienceHint: audienceHint
            )
        }

        var bestSelection: (title: String, startIndex: Int, consumedCount: Int, score: Int)?

        for position in filtered.indices {
            let current = filtered[position]
            let singleScore = educationalCoverTitleScore(current.line, lineIndex: current.index, isCombined: false)
            if singleScore > (bestSelection?.score ?? Int.min) {
                bestSelection = (current.line, current.index, 1, singleScore)
            }

            guard position + 1 < filtered.count else { continue }
            let next = filtered[position + 1]
            guard next.index == current.index + 1 else { continue }

            let combined = OCRDisplayTextFormatter.normalize("\(current.line) \(next.line)")
            let combinedScore = educationalCoverTitleScore(combined, lineIndex: current.index, isCombined: true)
            if combinedScore > (bestSelection?.score ?? Int.min) {
                bestSelection = (combined, current.index, 2, combinedScore)
            }
        }

        guard let bestSelection, bestSelection.score >= 18 else { return nil }

        let subtitle = extractedEducationalSubtitle(
            from: filtered,
            titleStartIndex: bestSelection.startIndex,
            consumedCount: bestSelection.consumedCount,
            title: bestSelection.title
        )
        let audienceHint = extractedEducationalAudienceHint(
            from: filtered.map(\.line),
            excluding: [bestSelection.title, subtitle].compactMap { $0 }
        )
        return EducationalCoverProfile(
            title: bestSelection.title,
            subtitle: subtitle,
            audienceHint: audienceHint
        )
    }

    private func prioritizedEducationalCoverSelection(
        from lines: [(index: Int, line: String)]
    ) -> (title: String, startIndex: Int, consumedCount: Int)? {
        let topCandidates = lines.filter { $0.index <= 2 }

        for candidateIndex in topCandidates.indices {
            let current = topCandidates[candidateIndex]
            guard candidateIndex + 1 < topCandidates.count else { continue }

            let next = topCandidates[candidateIndex + 1]
            guard next.index == current.index + 1 else { continue }
            guard current.index <= 1 else { continue }
            guard !looksLikeAudienceLine(next.line) else { continue }

            let combined = OCRDisplayTextFormatter.normalize("\(current.line) \(next.line)")
            guard isPlausibleEducationalTitle(combined) else { continue }

            let combinedScore = educationalCoverTitleScore(combined, lineIndex: current.index, isCombined: true)
            guard combinedScore >= 28 else { continue }

            let isMixedScriptPair = hasMixedLatinAndEastAsianScript(combined)
            let hasIntroSignal = containsEducationalTitleSignal(current.line) || containsEducationalTitleSignal(next.line)
            let hasShortHeadlineShape = current.line.count <= 14 || next.line.count <= 20
            guard isMixedScriptPair || hasIntroSignal || hasShortHeadlineShape else { continue }

            return (combined, current.index, 2)
        }

        return nil
    }

    private func isCandidateEducationalCoverLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        if lowered.contains("edition") || lowered.contains("international edition") {
            return false
        }
        if lowered.contains("pearson") || lowered.contains("isbn") || lowered.contains("copyright") {
            return false
        }
        if KnowledgeImportFallbackBuilder.makeDraft(from: line).title.isEmpty {
            return false
        }

        let letters = line.unicodeScalars.filter {
            CharacterSet.letters.contains($0)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0x3040...0x30FF).contains($0.value)
        }
        return letters.count >= 3
    }

    private func educationalCoverTitleScore(
        _ title: String,
        lineIndex: Int,
        isCombined: Bool
    ) -> Int {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard isPlausibleEducationalTitle(trimmed) else { return Int.min }

        let lowered = trimmed.lowercased()
        let scalars = trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }
        let latinCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let eastAsianCount = scalars.filter {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
                || (0x3040...0x30FF).contains($0.value)
                || (0x31F0...0x31FF).contains($0.value)
        }.count
        let tokenCount = lowered
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
            .count

        var score = 0
        if (4...28).contains(trimmed.count) { score += 12 }
        if (6...20).contains(trimmed.count) { score += 8 }
        score += max(0, 10 - lineIndex * 2)
        if isCombined { score += 4 }
        if latinCount >= 3 || eastAsianCount >= 3 { score += 8 }
        if latinCount >= 2 && eastAsianCount >= 2 { score += 6 }
        if tokenCount <= 6 { score += 4 }
        if isCombined && hasMixedLatinAndEastAsianScript(trimmed) { score += 8 }

        let titleSignals = [
            "guide", "manual", "handbook", "introduction", "fundamentals", "basics",
            "入門", "基礎", "導論", "手冊", "指南",
            "入門", "基礎", "ガイド", "マニュアル"
        ]
        score += titleSignals.filter { lowered.contains($0) }.count * 3

        if looksLikeAudienceLine(trimmed) { score -= 14 }
        if trimmed.contains("。") || trimmed.contains("，") || trimmed.contains(",") { score -= 8 }
        if tokenCount >= 9 { score -= 8 }
        if lowered.hasPrefix("for ") || lowered.hasPrefix("how to ") { score -= 10 }

        return score
    }

    private func extractedEducationalSubtitle(
        from lines: [(index: Int, line: String)],
        titleStartIndex: Int,
        consumedCount: Int,
        title: String
    ) -> String? {
        let consumed = Set(titleStartIndex..<(titleStartIndex + consumedCount))
        let nearby = lines.filter { candidate in
            !consumed.contains(candidate.index)
                && abs(candidate.index - titleStartIndex) <= 2
                && candidate.line != title
        }

        for candidate in nearby {
            let line = candidate.line
            guard !looksLikeAudienceLine(line) else { continue }
            guard !isLikelyOCRNoiseLine(line) else { continue }
            guard line.count >= 6, line.count <= 40 else { continue }
            guard !line.lowercased().contains("edition") else { continue }
            return line
        }

        return nil
    }

    private func extractedEducationalAudienceHint(
        from lines: [String],
        excluding excludedLines: [String]
    ) -> String? {
        for line in lines {
            guard !excludedLines.contains(line) else { continue }
            if looksLikeAudienceLine(line) {
                return line
            }
        }
        return nil
    }

    private func looksLikeAudienceLine(_ line: String) -> Bool {
        let lowered = line.lowercased()
        let strongSignals = [
            "for beginners", "for absolute beginners", "for starter", "for self-paced",
            "zero knowledge", "entry level", "step by step",
            "初學者", "新手", "零基礎", "超基礎", "快速上手", "從零開始", "知識ゼロ",
            "初心者", "はじめて", "ゼロから", "独学"
        ]
        if strongSignals.contains(where: { lowered.contains($0.lowercased()) }) {
            return true
        }

        let introductorySignals = ["超入門", "入門", "基礎"]
        guard introductorySignals.contains(where: { lowered.contains($0.lowercased()) }) else {
            return false
        }

        // Short lines like "超入門" are often subtitle fragments, not audience copy.
        return line.count >= 8 || lowered.contains("for ")
    }

    private func hasMixedLatinAndEastAsianScript(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        let hasLatin = scalars.contains { CharacterSet.letters.contains($0) && $0.value < 0x0100 }
        let hasEastAsian = scalars.contains {
            (0x3400...0x4DBF).contains($0.value)
                || (0x4E00...0x9FFF).contains($0.value)
                || (0xF900...0xFAFF).contains($0.value)
                || (0x3040...0x309F).contains($0.value)
                || (0x30A0...0x30FF).contains($0.value)
                || (0x31F0...0x31FF).contains($0.value)
        }
        return hasLatin && hasEastAsian
    }

    private func containsEducationalTitleSignal(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let signals = [
            "guide", "manual", "handbook", "introduction", "fundamentals", "basics",
            "入門", "基礎", "導論", "手冊", "指南", "ガイド", "マニュアル"
        ]
        return signals.contains { lowered.contains($0.lowercased()) }
    }

    private func isPlausibleEducationalTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard trimmed.count >= 6, trimmed.count <= 48 else { return false }
        let lowered = trimmed.lowercased()
        if lowered.contains("edition") || lowered.contains("pearson") {
            return false
        }
        if looksLikeAudienceLine(trimmed) && trimmed.count > 16 {
            return false
        }
        let tokens = lowered
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return false }
        if tokens.count >= 5 && !tokens.contains("of") && !tokens.contains("for") {
            return false
        }
        return true
    }

    private func localizedEducationalCoverSummary(
        profile: EducationalCoverProfile,
        text: String,
        category: KnowledgeCategory
    ) -> String {
        let compact = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let excerpt = compact.count > 180 ? String(compact.prefix(180)) + "…" : compact
        let subtitleSegment = profile.subtitle.map { subtitle in
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "副題可辨識為「\(subtitle)」。"
            case .unitedStates:
                return "The visible subtitle appears to be “\(subtitle).” "
            case .japan:
                return "副題として「\(subtitle)」が読み取れます。"
            }
        } ?? ""
        let audienceSegment = profile.audienceHint.map { hint in
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "封面也顯示它偏向「\(hint)」這類受眾或學習情境。"
            case .unitedStates:
                return "The cover also suggests an audience or learning context such as “\(hint).” "
            case .japan:
                return "表紙からは「\(hint)」のような対象読者や学習文脈も読み取れます。"
            }
        } ?? ""

        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "這看起來是一份教材或教科書封面，較明確的主題是「\(profile.title)」，屬於\(category.localizedName)相關學習內容。\(subtitleSegment)\(audienceSegment)可先把它當作該書或課程的入口知識點，之後再補充章節重點與細節。封面可辨識資訊：\(excerpt)"
        case .unitedStates:
            return "This appears to be a textbook or learning-material cover. The more specific study topic is “\(profile.title),” which fits \(category.localizedName). \(subtitleSegment)\(audienceSegment)It can serve as an anchor entry for the book or course before you add chapter-level concepts. Recognizable cover text: \(excerpt)"
        case .japan:
            return "これは教材または教科書の表紙と見られます。より具体的な主題は「\(profile.title)」で、\(category.localizedName)に関連する学習内容です。\(subtitleSegment)\(audienceSegment)まずはこの本や授業の入口となる知識項目として保存し、後から章ごとの要点を補えます。表紙から読めた情報: \(excerpt)"
        }
    }

    @MainActor
    func saveSelectedCandidates(
        _ candidates: [KnowledgeImportCandidate],
        preview: KnowledgeImportPreview,
        modelContext: ModelContext,
        library: KnowledgeLibraryRecord,
        libraryStore: KnowledgeLibraryStore,
        startingNodeCount: Int,
        supplementalTextReference: ReferenceImageOCRResult? = nil
    ) async throws -> KnowledgeSaveSelectionResult {
        guard !candidates.isEmpty else {
            return KnowledgeSaveSelectionResult(insertedCount: 0, didAutoArchive: false)
        }
        let saveStart = CFAbsoluteTimeGetCurrent()

        var existingTitles = await loadKnowledgeTitleSnapshot(using: modelContext)
        var insertedCount = 0
        var insertedNormalizedTitles: [String] = []
        var currentLibrary = library
        var currentNodeCount = startingNodeCount
        var didAutoArchive = false

        for candidate in candidates {
            let validation = KnowledgeNodeCleaner.validate(
                title: candidate.draft.title,
                content: candidate.draft.content,
                categoryRaw: candidate.draft.category.rawValue,
                source: candidate.source,
                existingTitles: existingTitles
            )

            guard let draft = validation.draft else { continue }

            let insertionTarget = try libraryStore.prepareActiveLibraryForNextInsertion(
                currentNodeCount: currentNodeCount,
                modelContext: modelContext
            )

            currentLibrary = insertionTarget.library
            if insertionTarget.didArchive {
                didAutoArchive = true
                currentNodeCount = 0
            }

            let newNode = KnowledgeNode(
                title: draft.title,
                content: draft.content,
                category: draft.category,
                x: 0, y: 0, z: 0,
                libraryID: currentLibrary.id,
                libraryName: currentLibrary.name
            )

            if let supplementalTextReference {
                let summaryReference = KnowledgeReference(
                    title: supplementalTextReference.title,
                    type: .text,
                    payload: supplementalTextReference.content
                )
                newNode.references = [summaryReference]
            }

            modelContext.insert(newNode)
            let normalizedTitle = KnowledgeNodeCleaner.normalizedKey(for: draft.title)
            existingTitles.insert(normalizedTitle)
            insertedNormalizedTitles.append(normalizedTitle)
            insertedCount += 1
            currentNodeCount += 1
        }

        if insertedCount > 0 {
            try modelContext.save()
            await KnowledgeTitleIndexStore.shared.register(normalizedTitles: insertedNormalizedTitles)
        }

        await PerformanceTraceRecorder.shared.record(
            name: "knowledge_save_selection",
            durationMs: elapsedDurationMs(since: saveStart),
            metadata: [
                "selected": "\(candidates.count)",
                "inserted": "\(insertedCount)",
                "auto_archived": didAutoArchive ? "true" : "false"
            ]
        )

        return KnowledgeSaveSelectionResult(
            insertedCount: insertedCount,
            didAutoArchive: didAutoArchive
        )
    }

    func prepareReferenceImageOCR(image: UIImage) async throws -> ReferenceImageOCRResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let rawExtractedText = try await extractBestTextFromImage(image: image)
        let cleanedOCR = cleanedOCRText(from: rawExtractedText)
        let extractedText = cleanedOCR.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let salvagedText = salvagedVerticalCJKText(from: rawExtractedText)
        let finalizedText: String

        if shouldCreateReferenceOCR(from: extractedText, cleaningResult: cleanedOCR) {
            finalizedText = extractedText
        } else if shouldCreateReferenceOCR(
            from: salvagedText,
            cleaningResult: OCRCleaningResult(cleanedText: salvagedText, filteredLineCount: 0)
        ) {
            finalizedText = salvagedText
        } else {
            await PerformanceTraceRecorder.shared.record(
                name: "reference_image_ocr",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "status": "rejected_noise",
                    "raw_chars": "\(rawExtractedText.count)",
                    "cleaned_chars": "\(extractedText.count)",
                    "salvaged_chars": "\(salvagedText.count)"
                ]
            )
            return nil
        }

        let repairedFinalizedText = await repairedOCRTextIfNeeded(
            finalizedText,
            rawText: rawExtractedText,
            purpose: .referenceSummary
        )
        let summaryResult = try await summarizeReferenceOCRText(repairedFinalizedText)
        let finalContent = normalizedOCRSummary(summaryResult?.ocrSummary, fallbackFrom: repairedFinalizedText) ?? repairedFinalizedText

        await PerformanceTraceRecorder.shared.record(
            name: "reference_image_ocr",
            durationMs: elapsedDurationMs(since: start),
            metadata: [
                "chars": "\(repairedFinalizedText.count)",
                "summary_chars": "\(finalContent.count)"
            ]
        )
        return ReferenceImageOCRResult(
            title: imageOCRSummaryReferenceTitle(),
            content: finalContent,
            verificationNote: normalizedVerificationNote(summaryResult?.verificationNote)
        )
    }

    func preparePDFReferenceSummary(fileURL: URL) async throws -> ReferenceImageOCRResult? {
        let start = CFAbsoluteTimeGetCurrent()
        guard let extraction = await extractSummarizablePDFTextAsync(from: fileURL) else {
            await PerformanceTraceRecorder.shared.record(
                name: "reference_pdf_summary",
                durationMs: elapsedDurationMs(since: start),
                metadata: ["status": "no_text"]
            )
            throw PDFSummaryPreparationError.noReadableText
        }

        guard looksLikeSummarizablePDFDocument(text: extraction.text) else {
            await PerformanceTraceRecorder.shared.record(
                name: "reference_pdf_summary",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "status": "unsupported_content",
                    "source": extraction.source
                ]
            )
            throw PDFSummaryPreparationError.unsupportedSummarySource
        }

        let repairedExtractionText = await repairedOCRTextIfNeeded(
            extraction.text,
            rawText: extraction.source == "page_ocr" ? extraction.text : nil,
            purpose: .pdfSummary
        )
        let summaryResult = try await summarizePDFText(repairedExtractionText)
        guard let summary = summaryResult?.ocrSummary, !summary.isEmpty else {
            await PerformanceTraceRecorder.shared.record(
                name: "reference_pdf_summary",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "status": "empty_summary",
                    "source": extraction.source
                ]
            )
            throw PDFSummaryPreparationError.aiSummaryUnavailable
        }

        await PerformanceTraceRecorder.shared.record(
            name: "reference_pdf_summary",
            durationMs: elapsedDurationMs(since: start),
            metadata: [
                "chars": "\(repairedExtractionText.count)",
                "summary_chars": "\(summary.count)",
                "source": extraction.source
            ]
        )
        return ReferenceImageOCRResult(
            title: pdfSummaryReferenceTitle(),
            content: summary,
            verificationNote: normalizedVerificationNote(summaryResult?.verificationNote)
        )
    }
    
    // MARK: - Apple Vision 邊緣運算 (OCR 函數)
    private func extractBestTextFromImage(image: UIImage) async throws -> String {
        let generalText = try await bestRawOCRText(
            from: ocrCandidateImages(from: image),
            maxCandidates: 8,
            stopScore: 180
        )
        let generalScore = cleanedOCRScore(for: generalText)
        if generalScore >= 180 {
            return generalText
        }

        let segmentedText = try await extractSegmentedPageText(from: image)
        let segmentedScore = cleanedOCRScore(for: segmentedText)
        if segmentedScore >= 180 {
            return segmentedText
        }

        if max(generalScore, segmentedScore) >= 120 {
            return segmentedScore > generalScore ? segmentedText : generalText
        }

        let tiledText = try await extractTiledPageText(from: image)
        let tiledScore = cleanedOCRScore(for: tiledText)

        if tiledScore >= max(segmentedScore, generalScore) {
            return tiledText
        }

        return segmentedScore > generalScore ? segmentedText : generalText
    }

    private func bestRawOCRText(
        from candidates: [UIImage],
        maxCandidates: Int? = nil,
        stopScore: Int = 160
    ) async throws -> String {
        var bestRawText = ""
        var bestScore = 0
        let sourceCandidates = maxCandidates.map { Array(candidates.prefix($0)) } ?? candidates

        for candidate in sourceCandidates {
            let rawText = try await extractTextFromImage(image: candidate)
            let score = cleanedOCRScore(for: rawText)

            if score > bestScore {
                bestScore = score
                bestRawText = rawText
            }

            if score >= stopScore {
                break
            }
        }

        return bestRawText
    }

    private func extractTextFromImage(image: UIImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let cgImage = try self.normalizedCGImage(from: image)
                    let accurateText = try self.performVisionOCR(
                        cgImage: cgImage,
                        level: .accurate,
                        minimumTextHeight: 0.003,
                        usesLanguageCorrection: true
                    )
                    let accurateScore = self.cleanedOCRText(from: accurateText).cleanedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .count

                    if accurateScore >= 12 {
                        continuation.resume(returning: accurateText)
                        return
                    }

                    let fastText = try self.performVisionOCR(
                        cgImage: cgImage,
                        level: .fast,
                        minimumTextHeight: 0.0015,
                        usesLanguageCorrection: false
                    )
                    let fastScore = self.cleanedOCRText(from: fastText).cleanedText
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .count

                    continuation.resume(returning: fastScore > accurateScore ? fastText : accurateText)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performVisionOCR(
        cgImage: CGImage,
        level: VNRequestTextRecognitionLevel,
        minimumTextHeight: Float,
        usesLanguageCorrection: Bool
    ) throws -> String {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        var recognizedText = ""
        let request = VNRecognizeTextRequest { request, error in
            if error != nil { return }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")
        }

        request.recognitionLanguages = ["zh-Hant", "zh-Hans", "ja-JP", "en-US"]
        request.recognitionLevel = level
        request.usesLanguageCorrection = usesLanguageCorrection
        request.minimumTextHeight = minimumTextHeight

        try requestHandler.perform([request])
        return recognizedText
    }

    private func normalizedCGImage(from image: UIImage) throws -> CGImage {
        if image.imageOrientation == .up, let cgImage = image.cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        let rendered = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        if let cgImage = rendered.cgImage {
            return cgImage
        }

        let ciContext = CIContext(options: nil)
        if let ciImage = image.ciImage,
           let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            return cgImage
        }

        throw NSError(
            domain: "ImageError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: {
                switch RegionUIStore.runtimeRegion() {
                case .taiwan: return "無法轉換圖片格式"
                case .unitedStates: return "Image format conversion failed."
                case .japan: return "画像形式の変換に失敗しました。"
                }
            }()]
        )
    }

    private func ocrCandidateImages(from image: UIImage) -> [UIImage] {
        var candidates: [UIImage] = []

        func appendVariants(for base: UIImage) {
            candidates.append(base)

            if let focused = focusedPageImage(from: base) {
                candidates.append(focused)
                if let upscaledFocused = upscaledOCRImage(from: focused) {
                    candidates.append(upscaledFocused)
                }
            }

            if let upscaled = upscaledOCRImage(from: base) {
                candidates.append(upscaled)
            }

            if let enhanced = enhancedOCRImage(from: base) {
                candidates.append(enhanced)
                if let upscaledEnhanced = upscaledOCRImage(from: enhanced) {
                    candidates.append(upscaledEnhanced)
                }
            }

            if let rotatedLeft = rotatedImage(base, radians: -.pi / 2) {
                candidates.append(rotatedLeft)
                if let upscaledRotatedLeft = upscaledOCRImage(from: rotatedLeft) {
                    candidates.append(upscaledRotatedLeft)
                }
                if let enhancedRotatedLeft = enhancedOCRImage(from: rotatedLeft) {
                    candidates.append(enhancedRotatedLeft)
                    if let upscaledEnhancedRotatedLeft = upscaledOCRImage(from: enhancedRotatedLeft) {
                        candidates.append(upscaledEnhancedRotatedLeft)
                    }
                }
            }

            if let rotatedRight = rotatedImage(base, radians: .pi / 2) {
                candidates.append(rotatedRight)
                if let upscaledRotatedRight = upscaledOCRImage(from: rotatedRight) {
                    candidates.append(upscaledRotatedRight)
                }
                if let enhancedRotatedRight = enhancedOCRImage(from: rotatedRight) {
                    candidates.append(enhancedRotatedRight)
                    if let upscaledEnhancedRotatedRight = upscaledOCRImage(from: enhancedRotatedRight) {
                        candidates.append(upscaledEnhancedRotatedRight)
                    }
                }
            }
        }

        for centered in centerPriorityImages(from: image) {
            appendVariants(for: centered)
        }

        appendVariants(for: image)

        for page in splitSpreadPagesIfNeeded(from: image) {
            appendVariants(for: page)
        }

        return candidates
    }

    private func centerPriorityImages(from image: UIImage) -> [UIImage] {
        guard let cgImage = try? normalizedCGImage(from: image) else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return [] }

        let primaryRect = centeredCropRect(
            imageWidth: width,
            imageHeight: height,
            widthRatio: 0.7,
            heightRatio: 0.74
        )
        let secondaryRect = centeredCropRect(
            imageWidth: width,
            imageHeight: height,
            widthRatio: 0.54,
            heightRatio: 0.62
        )

        let crops = [primaryRect, secondaryRect].compactMap { rect -> UIImage? in
            guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped)
        }

        return crops
    }

    private func centeredCropRect(
        imageWidth: Int,
        imageHeight: Int,
        widthRatio: CGFloat,
        heightRatio: CGFloat
    ) -> CGRect {
        let cropWidth = max(1, Int(CGFloat(imageWidth) * widthRatio))
        let cropHeight = max(1, Int(CGFloat(imageHeight) * heightRatio))
        let originX = max(0, (imageWidth - cropWidth) / 2)
        let originY = max(0, (imageHeight - cropHeight) / 2)
        return CGRect(x: originX, y: originY, width: cropWidth, height: cropHeight)
    }

    private func extractSegmentedPageText(from image: UIImage) async throws -> String {
        let pages = splitSpreadPagesIfNeeded(from: image)
        let sourcePages = pages.isEmpty ? [image] : pages
        var pageTexts: [String] = []

        for page in sourcePages {
            let columns = splitVerticalColumnsIfNeeded(from: page)
            guard !columns.isEmpty else { continue }

            var columnTexts: [String] = []
            for column in columns {
                let rawText = try await bestRawOCRText(
                    from: verticalColumnCandidateImages(from: column),
                    maxCandidates: 4,
                    stopScore: 80
                )
                let cleaned = cleanedOCRText(from: rawText).cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.count >= 4 {
                    columnTexts.append(cleaned)
                }

                if columnTexts.joined(separator: "\n").count >= 220 {
                    break
                }
            }

            if !columnTexts.isEmpty {
                pageTexts.append(columnTexts.joined(separator: "\n"))
                if pageTexts.joined(separator: "\n").count >= 260 {
                    break
                }
            }
        }

        return pageTexts.joined(separator: "\n")
    }

    private func extractTiledPageText(from image: UIImage) async throws -> String {
        let pages = splitSpreadPagesIfNeeded(from: image)
        let sourcePages = pages.isEmpty ? [image] : pages
        var pageTexts: [String] = []

        for page in sourcePages {
            let focused = focusedPageImage(from: page) ?? page
            var variantResults: [String] = []

            for radians in [-CGFloat.pi / 2, CGFloat.pi / 2] {
                guard let rotated = rotatedImage(focused, radians: radians) else { continue }
                let tiledText = try await extractTileOCRText(from: rotated)
                if !tiledText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    variantResults.append(tiledText)
                }
            }

            if let best = variantResults.max(by: {
                cleanedOCRText(from: $0).cleanedText.count < cleanedOCRText(from: $1).cleanedText.count
            }) {
                pageTexts.append(best)
            }
        }

        return pageTexts.joined(separator: "\n")
    }

    private func extractTileOCRText(from image: UIImage) async throws -> String {
        let tiles = horizontalTileImages(from: image)
        guard !tiles.isEmpty else { return "" }

        var fragments: [String] = []
        var seen = Set<String>()

        for tile in tiles {
            let rawText = try await bestRawOCRText(
                from: tileCandidateImages(from: tile),
                maxCandidates: 3,
                stopScore: 70
            )
            let cleaned = cleanedOCRText(from: rawText).cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count >= 2, seen.insert(cleaned).inserted {
                fragments.append(cleaned)
            }

            if fragments.joined(separator: "\n").count >= 220 {
                break
            }
        }

        return fragments.joined(separator: "\n")
    }

    private func cleanedOCRScore(for text: String) -> Int {
        cleanedOCRText(from: text).cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .count
    }

    private func splitVerticalColumnsIfNeeded(from image: UIImage) -> [UIImage] {
        let sourceImage = focusedPageImage(from: image) ?? image
        guard let cgImage = try? normalizedCGImage(from: sourceImage) else { return [] }

        let detectedColumns = detectedVerticalColumnImages(from: cgImage)
        if detectedColumns.count >= 2 {
            return detectedColumns
        }

        let width = cgImage.width
        let height = cgImage.height
        guard height > width else { return [] }

        let aspectRatio = CGFloat(width) / CGFloat(height)
        guard aspectRatio >= 0.42, aspectRatio <= 0.95 else { return [] }

        let estimatedColumns = max(4, min(12, Int(round(CGFloat(width) / 72.0))))
        guard estimatedColumns >= 4 else { return [] }

        let overlap = max(8, Int(CGFloat(width) * 0.018))
        let baseColumnWidth = max(1, width / estimatedColumns)
        let stride = max(12, baseColumnWidth / 2)

        var columns: [UIImage] = []
        var currentRightEdge = width
        while currentRightEdge > 0 {
            let endX = min(width, currentRightEdge + overlap)
            let startX = max(0, currentRightEdge - baseColumnWidth - overlap)
            let rect = CGRect(
                x: startX,
                y: 0,
                width: max(1, endX - startX),
                height: height
            ).integral

            guard let cropped = cgImage.cropping(to: rect) else { continue }
            columns.append(UIImage(cgImage: cropped))
            currentRightEdge -= stride

            if columns.count >= 18 {
                break
            }
        }

        return columns
    }

    private func verticalColumnCandidateImages(from image: UIImage) -> [UIImage] {
        var candidates: [UIImage] = []

        if let rotatedLeft = rotatedImage(image, radians: -.pi / 2) {
            candidates.append(rotatedLeft)
            if let upscaledRotatedLeft = upscaledOCRImage(from: rotatedLeft) {
                candidates.append(upscaledRotatedLeft)
            }
            if let enhancedRotatedLeft = enhancedOCRImage(from: rotatedLeft) {
                candidates.append(enhancedRotatedLeft)
                if let upscaledEnhancedRotatedLeft = upscaledOCRImage(from: enhancedRotatedLeft) {
                    candidates.append(upscaledEnhancedRotatedLeft)
                }
            }
        }

        if let rotatedRight = rotatedImage(image, radians: .pi / 2) {
            candidates.append(rotatedRight)
            if let upscaledRotatedRight = upscaledOCRImage(from: rotatedRight) {
                candidates.append(upscaledRotatedRight)
            }
            if let enhancedRotatedRight = enhancedOCRImage(from: rotatedRight) {
                candidates.append(enhancedRotatedRight)
                if let upscaledEnhancedRotatedRight = upscaledOCRImage(from: enhancedRotatedRight) {
                    candidates.append(upscaledEnhancedRotatedRight)
                }
            }
        }

        candidates.append(image)
        if let upscaled = upscaledOCRImage(from: image) {
            candidates.append(upscaled)
        }
        if let enhanced = enhancedOCRImage(from: image) {
            candidates.append(enhanced)
            if let upscaledEnhanced = upscaledOCRImage(from: enhanced) {
                candidates.append(upscaledEnhanced)
            }
        }

        return candidates
    }

    private func horizontalTileImages(from image: UIImage) -> [UIImage] {
        guard let cgImage = try? normalizedCGImage(from: image) else { return [] }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return [] }

        let tileHeight = max(120, min(height, Int(CGFloat(height) * 0.24)))
        let stride = max(80, Int(CGFloat(tileHeight) * 0.62))
        var tiles: [UIImage] = []
        var currentY = 0

        while currentY < height {
            let endY = min(height, currentY + tileHeight)
            let rect = CGRect(x: 0, y: currentY, width: width, height: max(1, endY - currentY)).integral
            if let cropped = cgImage.cropping(to: rect) {
                tiles.append(UIImage(cgImage: cropped))
            }

            if endY >= height || tiles.count >= 14 {
                break
            }

            currentY += stride
        }

        return tiles
    }

    private func tileCandidateImages(from image: UIImage) -> [UIImage] {
        var candidates: [UIImage] = [image]

        if let focused = focusedPageImage(from: image) {
            candidates.append(focused)
        }

        if let upscaled = upscaledOCRImage(from: image) {
            candidates.append(upscaled)
        }

        if let enhanced = enhancedOCRImage(from: image) {
            candidates.append(enhanced)
            if let upscaledEnhanced = upscaledOCRImage(from: enhanced) {
                candidates.append(upscaledEnhanced)
            }
        }

        return candidates
    }

    private func splitSpreadPagesIfNeeded(from image: UIImage) -> [UIImage] {
        guard image.size.width > image.size.height * 1.18,
              let cgImage = try? normalizedCGImage(from: image) else {
            return []
        }

        let width = cgImage.width
        let height = cgImage.height
        let overlap = Int(CGFloat(width) * 0.04)
        let halfWidth = width / 2

        let leftRect = CGRect(x: 0, y: 0, width: min(width, halfWidth + overlap), height: height)
        let rightRect = CGRect(x: max(0, halfWidth - overlap), y: 0, width: width - max(0, halfWidth - overlap), height: height)

        let crops = [leftRect, rightRect].compactMap { rect -> UIImage? in
            guard let cropped = cgImage.cropping(to: rect.integral) else { return nil }
            return UIImage(cgImage: cropped)
        }

        return crops
    }

    private func enhancedOCRImage(from image: UIImage) -> UIImage? {
        guard let cgImage = try? normalizedCGImage(from: image) else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard let controlsFilter = CIFilter(name: "CIColorControls") else { return nil }
        controlsFilter.setValue(input, forKey: kCIInputImageKey)
        controlsFilter.setValue(0.02, forKey: kCIInputBrightnessKey)
        controlsFilter.setValue(1.35, forKey: kCIInputContrastKey)
        controlsFilter.setValue(0.0, forKey: kCIInputSaturationKey)

        guard let contrasted = controlsFilter.outputImage,
              let sharpenFilter = CIFilter(name: "CISharpenLuminance") else { return nil }
        sharpenFilter.setValue(contrasted, forKey: kCIInputImageKey)
        sharpenFilter.setValue(0.7, forKey: kCIInputRadiusKey)
        sharpenFilter.setValue(0.55, forKey: kCIInputSharpnessKey)

        guard let sharpened = sharpenFilter.outputImage else { return nil }

        let ciContext = CIContext(options: nil)
        guard let outputCGImage = ciContext.createCGImage(sharpened, from: sharpened.extent) else {
            return nil
        }

        return UIImage(cgImage: outputCGImage)
    }

    private func focusedPageImage(from image: UIImage) -> UIImage? {
        guard let cgImage = try? normalizedCGImage(from: image) else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let insetXRatio: CGFloat = width > height ? 0.06 : 0.08
        let insetTopRatio: CGFloat = 0.05
        let insetBottomRatio: CGFloat = 0.08

        let insetX = Int(CGFloat(width) * insetXRatio)
        let insetTop = Int(CGFloat(height) * insetTopRatio)
        let insetBottom = Int(CGFloat(height) * insetBottomRatio)

        let rect = CGRect(
            x: insetX,
            y: insetTop,
            width: max(1, width - (insetX * 2)),
            height: max(1, height - insetTop - insetBottom)
        ).integral

        guard rect.width > 0, rect.height > 0,
              let baseCropped = cgImage.cropping(to: rect) else {
            return nil
        }

        if let detectedRect = detectedTextContentRect(in: baseCropped),
           let refined = baseCropped.cropping(to: detectedRect.integral),
           detectedRect.width > CGFloat(baseCropped.width) * 0.38,
           detectedRect.height > CGFloat(baseCropped.height) * 0.42 {
            return UIImage(cgImage: refined)
        }

        return UIImage(cgImage: baseCropped)
    }

    private func upscaledOCRImage(from image: UIImage) -> UIImage? {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > 0 else { return nil }
        guard longSide < 2200 else { return image }

        let scaleFactor = min(2.4, 2200.0 / longSide)
        let targetSize = CGSize(
            width: image.size.width * scaleFactor,
            height: image.size.height * scaleFactor
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func detectedTextContentRect(in cgImage: CGImage) -> CGRect? {
        guard let analysis = analyzeTextInk(in: cgImage) else { return nil }

        let rowThreshold = max(2, Int(Double(analysis.sampleWidth) * 0.018))
        let columnThreshold = max(2, Int(Double(analysis.sampleHeight) * 0.012))

        guard let rowRange = mergedRange(
            activeRanges(
                in: analysis.rowDarkCounts,
                threshold: rowThreshold,
                minimumLength: max(3, analysis.sampleHeight / 32)
            )
        ),
        let columnRange = mergedRange(
            activeRanges(
                in: analysis.columnDarkCounts,
                threshold: columnThreshold,
                minimumLength: max(2, analysis.sampleWidth / 48)
            )
        ) else {
            return nil
        }

        return imageRect(
            xRange: columnRange,
            yRange: rowRange,
            sampleWidth: analysis.sampleWidth,
            sampleHeight: analysis.sampleHeight,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            paddingX: 16,
            paddingY: 18
        )
    }

    private func detectedVerticalColumnImages(from cgImage: CGImage) -> [UIImage] {
        guard let analysis = analyzeTextInk(in: cgImage) else { return [] }

        let rowThreshold = max(2, Int(Double(analysis.sampleWidth) * 0.018))
        let columnThreshold = max(2, Int(Double(analysis.sampleHeight) * 0.011))

        guard let rowRange = mergedRange(
            activeRanges(
                in: analysis.rowDarkCounts,
                threshold: rowThreshold,
                minimumLength: max(3, analysis.sampleHeight / 32)
            )
        ) else {
            return []
        }

        let columnRanges = activeRanges(
            in: analysis.columnDarkCounts,
            threshold: columnThreshold,
            minimumLength: max(2, analysis.sampleWidth / 70)
        )

        guard columnRanges.count >= 2 else { return [] }

        return columnRanges.reversed().compactMap { range in
            let rect = imageRect(
                xRange: range,
                yRange: rowRange,
                sampleWidth: analysis.sampleWidth,
                sampleHeight: analysis.sampleHeight,
                imageWidth: cgImage.width,
                imageHeight: cgImage.height,
                paddingX: 12,
                paddingY: 14
            ).integral

            guard rect.width > 8, rect.height > 8,
                  let cropped = cgImage.cropping(to: rect) else {
                return nil
            }

            return UIImage(cgImage: cropped)
        }
    }

    private func analyzeTextInk(in cgImage: CGImage) -> (sampleWidth: Int, sampleHeight: Int, rowDarkCounts: [Int], columnDarkCounts: [Int])? {
        let maxSampleLongSide = 240
        let originalWidth = cgImage.width
        let originalHeight = cgImage.height
        guard originalWidth > 0, originalHeight > 0 else { return nil }

        let scale = min(1.0, Double(maxSampleLongSide) / Double(max(originalWidth, originalHeight)))
        let sampleWidth = max(48, Int(Double(originalWidth) * scale))
        let sampleHeight = max(48, Int(Double(originalHeight) * scale))

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var buffer = [UInt8](repeating: 255, count: sampleWidth * sampleHeight)

        guard let context = CGContext(
            data: &buffer,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: sampleWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))

        var rowDarkCounts = [Int](repeating: 0, count: sampleHeight)
        var columnDarkCounts = [Int](repeating: 0, count: sampleWidth)

        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let value = buffer[(y * sampleWidth) + x]
                if value < 214 {
                    rowDarkCounts[y] += 1
                    columnDarkCounts[x] += 1
                }
            }
        }

        return (sampleWidth, sampleHeight, rowDarkCounts, columnDarkCounts)
    }

    private func activeRanges(in counts: [Int], threshold: Int, minimumLength: Int) -> [ClosedRange<Int>] {
        guard !counts.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        var start: Int?

        for (index, count) in counts.enumerated() {
            if count >= threshold {
                start = start ?? index
            } else if let rangeStart = start, index - rangeStart >= minimumLength {
                ranges.append(rangeStart...(index - 1))
                start = nil
            } else {
                start = nil
            }
        }

        if let start, counts.count - start >= minimumLength {
            ranges.append(start...(counts.count - 1))
        }

        return mergeNearbyRanges(ranges, maximumGap: 3)
    }

    private func mergeNearbyRanges(_ ranges: [ClosedRange<Int>], maximumGap: Int) -> [ClosedRange<Int>] {
        guard var current = ranges.first else { return [] }
        var merged: [ClosedRange<Int>] = []

        for range in ranges.dropFirst() {
            if range.lowerBound - current.upperBound <= maximumGap {
                current = current.lowerBound...range.upperBound
            } else {
                merged.append(current)
                current = range
            }
        }

        merged.append(current)
        return merged
    }

    private func mergedRange(_ ranges: [ClosedRange<Int>]) -> ClosedRange<Int>? {
        guard let first = ranges.first, let last = ranges.last else { return nil }
        return first.lowerBound...last.upperBound
    }

    private func imageRect(
        xRange: ClosedRange<Int>,
        yRange: ClosedRange<Int>,
        sampleWidth: Int,
        sampleHeight: Int,
        imageWidth: Int,
        imageHeight: Int,
        paddingX: Int,
        paddingY: Int
    ) -> CGRect {
        let scaleX = CGFloat(imageWidth) / CGFloat(sampleWidth)
        let scaleY = CGFloat(imageHeight) / CGFloat(sampleHeight)

        let minX = max(0, Int(CGFloat(xRange.lowerBound) * scaleX) - paddingX)
        let maxX = min(imageWidth, Int(CGFloat(xRange.upperBound + 1) * scaleX) + paddingX)
        let minY = max(0, Int(CGFloat(yRange.lowerBound) * scaleY) - paddingY)
        let maxY = min(imageHeight, Int(CGFloat(yRange.upperBound + 1) * scaleY) + paddingY)

        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
    }

    private func rotatedImage(_ image: UIImage, radians: CGFloat) -> UIImage? {
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let rotatedBounds = CGRect(origin: .zero, size: originalSize)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral
        let targetSize = CGSize(width: abs(rotatedBounds.width), height: abs(rotatedBounds.height))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            context.cgContext.translateBy(x: targetSize.width / 2, y: targetSize.height / 2)
            context.cgContext.rotate(by: radians)
            image.draw(in: CGRect(
                x: -originalSize.width / 2,
                y: -originalSize.height / 2,
                width: originalSize.width,
                height: originalSize.height
            ))
        }
    }

    private func userVisibleLanguageInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "所有對使用者可見的文字都必須使用自然繁體中文。"
        case .unitedStates:
            return "All user-visible text must be written in natural English only."
        case .japan:
            return "ユーザーに見える文章はすべて自然な日本語のみで書いてください。"
        }
    }

    private func summaryLanguageInstruction(minLength: Int, maxLength: Int) -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "請用自然繁體中文寫一段 \(minLength) 到 \(maxLength) 字的簡單摘要"
        case .unitedStates:
            return "Write a concise \(minLength)-to-\(maxLength)-word summary in natural English"
        case .japan:
            return "自然な日本語で \(minLength) から \(maxLength) 文字程度の要約を書いてください"
        }
    }

    private func verificationNoteMissingInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "未進行外部比對"
        case .unitedStates:
            return "No external verification performed"
        case .japan:
            return "外部照合は行っていません"
        }
    }

    private func localizedOCRSummaryJSONExample() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return #"{"ocr_summary": "摘要內容", "verification_note": "是否比對外部資訊與比對結果"}"#
        case .unitedStates:
            return #"{"ocr_summary": "summary text", "verification_note": "whether external verification was performed"}"#
        case .japan:
            return #"{"ocr_summary": "要約文", "verification_note": "外部照合の有無と結果"}"#
        }
    }

    private func localizedKnowledgeJSONExample() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return #"{"source_summary": "文字重點摘要", "nodes": [{"title": "知識點標題", "content": "整理後的知識內容", "category": "門類"}]}"#
        case .unitedStates:
            return #"{"source_summary": "source summary", "nodes": [{"title": "knowledge title", "content": "organized knowledge content", "category": "category"}]}"#
        case .japan:
            return #"{"source_summary": "要点まとめ", "nodes": [{"title": "知識タイトル", "content": "整理した知識内容", "category": "門類"}]}"#
        }
    }

    private func summarySystemInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "你是一個輸出 JSON 格式摘要的 AI。所有對使用者可見的內容都必須使用自然繁體中文。"
        case .unitedStates:
            return "You are an AI that returns JSON summaries. All user-visible content must be written in natural English only."
        case .japan:
            return "あなたはJSON形式の要約を返すAIです。ユーザーに見える内容はすべて自然な日本語のみで書いてください。"
        }
    }

    private func conservativeOCRSummarySystemInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "你是一個輸出 JSON 格式摘要的 AI。你只能根據提供的 OCR 片段寫保守摘要，不能腦補。所有對使用者可見的內容都必須使用自然繁體中文。"
        case .unitedStates:
            return "You are an AI that returns JSON summaries. You may only write a conservative summary from the provided OCR fragments and must not invent details. All user-visible content must be written in natural English only."
        case .japan:
            return "あなたはJSON形式の要約を返すAIです。提供されたOCR断片だけを使って保守的に要約し、推測で補ってはいけません。ユーザーに見える内容はすべて自然な日本語のみで書いてください。"
        }
    }

    private func knowledgeSystemInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "你是一個輸出 JSON 格式的知識架構 AI。若當前執行環境沒有即時網路搜尋能力，就不得捏造外部驗證結果。所有對使用者可見的內容都必須使用自然繁體中文。"
        case .unitedStates:
            return "You are an AI that returns knowledge structures in JSON. If the current environment does not have live web search capability, you must not fabricate external verification. All user-visible content must be written in natural English only."
        case .japan:
            return "あなたはJSON形式の知識構造を返すAIです。現在の実行環境にリアルタイム検索能力がない場合、外部検証を捏造してはいけません。ユーザーに見える内容はすべて自然な日本語のみで書いてください。"
        }
    }

    private func ocrRepairSystemInstruction() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "你是一個只輸出 JSON 的 OCR 文件修復 AI。你只能做保守的 OCR 校正、段落重建與版面去噪，不能翻譯、不能摘要、不能捏造缺失內容。"
        case .unitedStates:
            return "You are an OCR document repair AI that outputs JSON only. You may only perform conservative OCR correction, paragraph reconstruction, and layout denoising. Do not translate, summarize, or invent missing content."
        case .japan:
            return "あなたはJSONのみを返すOCR文書修復AIです。保守的なOCR補正、段落再構成、レイアウトのノイズ除去だけを行ってください。翻訳、要約、欠落内容の捏造は禁止です。"
        }
    }

    private func imageFocusInstruction(prioritizeDocumentCover: Bool) -> String {
        if prioritizeDocumentCover {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "這是封面模式。請先看整張封面的最大標題、直排或橫排書名、副標與受眾文案，不要把中央插圖、裝飾圖示或邊角雜物當成主題。"
            case .unitedStates:
                return "This is cover mode. Read the largest visible title, vertical or horizontal book name, subtitle, and audience copy from the full cover first. Do not treat the central illustration, icon, or surrounding clutter as the main subject."
            case .japan:
                return "これは表紙モードです。全体の表紙から最も大きいタイトル、縦書きや横書きの書名、副題、対象読者の文言を優先して読んでください。中央のイラストやアイコン、周辺の雑物を主題として扱わないでください。"
            }
        }

        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "請優先辨識畫面中央主體；若同時提供中央裁切圖與完整圖，請先以前者判斷主體，再用完整圖補上下文。"
        case .unitedStates:
            return "Prioritize the subject near the center of the image. If both a centered crop and a full image are provided, identify the main subject from the crop first, then use the full image for context."
        case .japan:
            return "画面中央に近い主題を優先して判別してください。中央切り抜き画像と全体画像の両方がある場合は、先に切り抜き画像で主題を判断し、その後で全体画像から文脈を補ってください。"
        }
    }

    private func summarizePDFText(_ extractedText: String) async throws -> OCRSummaryResponse? {
        let prompt = """
        以下是一份 PDF 擷取出的文字，內容可能是英文、中文或日文的論文、教材、研究資料或一般說明文件。\(summaryLanguageInstruction(minLength: 100, maxLength: 180))，說明主題、關鍵觀點、方法、結論或重要資訊。不要列點，不要引用原文句子，不要加入猜不到的資訊；若文字片段不完整，請保守描述。
        \(userVisibleLanguageInstruction())

        如果這份內容看起來像可辨識的論文、書籍、教材、章節或文件，而且你在目前執行環境中真的具備即時網路查詢能力，允許你用可靠公開來源做保守交叉比對，協助修正常見 OCR/PDF 抽取錯字或標題誤差。
        如果沒有即時網路查詢能力，就不要假裝查過外部資料，並在 verification_note 明確寫「\(verificationNoteMissingInstruction())」。
        若有進行外部比對，只能在內容高度一致時採用，並在 verification_note 簡短說明比對了什麼；不確定時寧可保守。

        「\(extractedText)」

        請嚴格以 JSON 格式回傳：\(localizedOCRSummaryJSONExample())
        """

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": summarySystemInstruction()],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.2
        ]

        do {
            let (data, response) = try await performProtectedRequest(
                payload: payload,
                requestKind: .pdfSummary
            )
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(statusCode) else {
                throw noteImportError(
                    code: statusCode,
                    responseData: data,
                    fallbackMessage: {
                        switch RegionUIStore.runtimeRegion() {
                        case .taiwan: return "AI 目前無法生成這份 PDF 的摘要。"
                        case .unitedStates: return "AI could not generate a summary for this PDF right now."
                        case .japan: return "現在このPDFの要約を生成できません。"
                        }
                    }()
                )
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let contentString = message["content"] as? String,
                  let contentData = contentString.data(using: .utf8) else {
                throw PDFSummaryPreparationError.aiSummaryUnavailable
            }

            let result = try JSONDecoder().decode(OCRSummaryResponse.self, from: contentData)
            return OCRSummaryResponse(
                ocrSummary: result.ocrSummary?
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                verificationNote: result.verificationNote?
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            throw error
        }
    }

    private func summarizeReferenceOCRText(_ extractedText: String) async throws -> OCRSummaryResponse? {
        let summaryContext = summaryReadyOCRContext(from: extractedText)
        let prompt = """
        以下是從照片 OCR 擷取並整理過的文字片段，可能來自書頁、講義、筆記或文章。
        這些片段可能不完整、順序略有偏差，請嚴格只根據片段本身做保守摘要，不要補出片段裡沒有出現的背景故事、人物、事件或結論。
        \(userVisibleLanguageInstruction())

        如果片段看起來像可辨識的書籍、教材、論文、章節標題或明確主題，而且你在目前執行環境中真的具備即時網路查詢能力，允許你用可靠公開來源做保守交叉比對，協助修正 OCR 常見誤字或主題辨識。
        如果沒有即時網路查詢能力，就不要假裝查過外部資料，並在 verification_note 明確寫「\(verificationNoteMissingInstruction())」。
        若有進行外部比對，只能在片段與外部資訊高度一致時採用，並在 verification_note 簡短說明比對了什麼；不確定時寧可保守。

        可用片段：
        \(summaryContext)

        任務要求：
        1. \(summaryLanguageInstruction(minLength: 70, maxLength: 140))。
        2. 優先描述真正看得出來的主題、概念、論述方向或章節內容。
        3. 如果片段不足以確定細節，就明確用「片段主要提到…」「內容看來圍繞…」這種保守說法。
        4. 不要列點，不要照抄原句，不要加入猜不到的資訊。

        請嚴格以 JSON 格式回傳：\(localizedOCRSummaryJSONExample())
        """

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": conservativeOCRSummarySystemInstruction()],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.05
        ]

        let (data, response) = try await performProtectedRequest(
            payload: payload,
            requestKind: .referenceImageOCR
        )
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw noteImportError(
                code: statusCode,
                responseData: data,
                fallbackMessage: {
                    switch RegionUIStore.runtimeRegion() {
                    case .taiwan: return "AI 目前無法整理這張圖片的 OCR 摘要。"
                    case .unitedStates: return "AI could not prepare an OCR summary for this image right now."
                    case .japan: return "現在この画像のOCR要約を整理できません。"
                    }
                }()
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentString = message["content"] as? String,
              let contentData = contentString.data(using: .utf8) else {
            return nil
        }

        let result = try JSONDecoder().decode(OCRSummaryResponse.self, from: contentData)
        return OCRSummaryResponse(
            ocrSummary: result.ocrSummary?
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            verificationNote: result.verificationNote?
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func normalizedVerificationNote(_ note: String?) -> String? {
        let trimmed = note?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmed, !trimmed.isEmpty else {
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                return "未進行外部比對"
            case .unitedStates:
                return "No external verification performed"
            case .japan:
                return "外部照合は行っていません"
            }
        }
        return trimmed
    }

    private func summaryReadyOCRContext(from extractedText: String) -> String {
        let lines = extractedText
            .components(separatedBy: .newlines)
            .map(normalizedOCRLine)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var selected: [String] = []
        var totalCount = 0

        for line in lines {
            guard seen.insert(line).inserted else { continue }

            let scalarCount = line.unicodeScalars.filter { !$0.properties.isWhitespace }.count
            let cjkCount = line.unicodeScalars.filter { 0x4E00...0x9FFF ~= $0.value }.count
            let hasUsefulLength = scalarCount >= 4 || cjkCount >= 3
            guard hasUsefulLength else { continue }

            selected.append(line)
            totalCount += line.count

            if selected.count >= 18 || totalCount >= 900 {
                break
            }
        }

        if selected.isEmpty {
            return extractedText.prefix(900).description
        }

        return selected.joined(separator: "\n")
    }

    private func shouldCreateReferenceOCR(from text: String, cleaningResult: OCRCleaningResult) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map(normalizedOCRLine)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return false }

        let compact = lines.joined(separator: " ")
        let visibleScalars = compact.unicodeScalars.filter { !$0.properties.isWhitespace }
        let visibleCount = visibleScalars.count
        let letterLikeCount = visibleScalars.filter { CharacterSet.letters.contains($0) }.count
        let cjkCount = visibleScalars.filter { 0x4E00...0x9FFF ~= $0.value }.count
        let digitCount = visibleScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = visibleScalars.filter {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }.count

        guard visibleCount >= 8 else { return false }
        guard letterLikeCount >= 6 || cjkCount >= 6 else { return false }

        let digitRatio = Double(digitCount) / Double(max(visibleCount, 1))
        let punctuationRatio = Double(punctuationCount) / Double(max(visibleCount, 1))
        let meaningfulLineCount = lines.filter { !$0.contains("�") && !$0.contains("?") }.count
        let filteredDominates = cleaningResult.filteredLineCount >= lines.count * 2
        let cjkRatio = Double(cjkCount) / Double(max(visibleCount, 1))
        let cjkFragmentLineCount = lines.filter {
            let scalars = $0.unicodeScalars.filter { !$0.properties.isWhitespace }
            let cjk = scalars.filter { 0x4E00...0x9FFF ~= $0.value }.count
            let punctuation = scalars.filter {
                CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
            }.count
            return cjk >= 2 && Double(punctuation) / Double(max(scalars.count, 1)) < 0.45
        }.count

        if cjkCount >= 20 && compact.count >= 20 && punctuationRatio < 0.4 {
            return true
        }

        if cjkCount >= 12 && meaningfulLineCount >= 2 && compact.count >= 16 && digitRatio < 0.4 {
            return true
        }

        if cjkRatio > 0.45 && compact.count >= 18 && punctuationRatio < 0.36 {
            return true
        }

        if cjkCount >= 6 && compact.count >= 10 && punctuationRatio < 0.42 && digitRatio < 0.45 {
            return true
        }

        if cjkCount >= 10 && cjkFragmentLineCount >= 4 && punctuationRatio < 0.48 && digitRatio < 0.45 {
            return true
        }

        if digitRatio > 0.35 || punctuationRatio > 0.32 {
            return false
        }

        if filteredDominates {
            return false
        }

        if meaningfulLineCount == 0 {
            return false
        }

        if lines.count == 1 && compact.count < 20 {
            return false
        }

        return true
    }

    private func extractMeaningfulPDFText(from fileURL: URL) -> String? {
        guard let document = PDFDocument(url: fileURL) else { return nil }

        var collected: [String] = []
        for pageIndex in 0..<min(document.pageCount, 8) {
            guard let page = document.page(at: pageIndex),
                  let pageText = page.string else { continue }

            let normalized = pageText
                .components(separatedBy: .newlines)
                .map(normalizedOCRLine)
                .filter { !$0.isEmpty && !isLikelyOCRNoiseLine($0) }
                .joined(separator: "\n")

            if !normalized.isEmpty {
                collected.append(normalized)
            }

            if collected.joined(separator: "\n").count > 7000 {
                break
            }
        }

        let merged = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard merged.count >= 500 else { return nil }
        return merged.count > 7000 ? String(merged.prefix(7000)) : merged
    }

    private func extractMeaningfulPDFTextAsync(from fileURL: URL) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: self.extractMeaningfulPDFText(from: fileURL))
            }
        }
    }

    private func extractSummarizablePDFTextAsync(from fileURL: URL) async -> (text: String, source: String)? {
        if let extractedText = await extractMeaningfulPDFTextAsync(from: fileURL),
           extractedText.count >= 220 {
            return (extractedText, "embedded_text")
        }

        if let ocrText = await extractMeaningfulPDFTextViaOCRAsync(from: fileURL),
           ocrText.count >= 180 {
            return (ocrText, "page_ocr")
        }

        if let extractedText = await extractMeaningfulPDFTextAsync(from: fileURL),
           !extractedText.isEmpty {
            return (extractedText, "embedded_text_short")
        }

        return nil
    }

    private func extractMeaningfulPDFTextViaOCRAsync(from fileURL: URL) async -> String? {
        guard let document = PDFDocument(url: fileURL), document.pageCount > 0 else { return nil }

        var collected: [String] = []
        let maxPages = min(document.pageCount, 5)

        for pageIndex in 0..<maxPages {
            guard let page = document.page(at: pageIndex),
                  let pageImage = renderedImage(for: page) else { continue }

            let rawText = (try? await extractBestTextFromImage(image: pageImage)) ?? ""
            let cleaned = cleanedOCRText(from: rawText)
            let candidate = cleaned.cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

            if shouldCreateReferenceOCR(from: candidate, cleaningResult: cleaned) {
                collected.append(candidate)
            }

            if collected.joined(separator: "\n").count > 5000 {
                break
            }
        }

        let merged = collected.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard merged.count >= 120 else { return nil }
        return merged.count > 7000 ? String(merged.prefix(7000)) : merged
    }

    private func renderedImage(for page: PDFPage) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let maxDimension: CGFloat = 1600
        let scale = min(maxDimension / max(bounds.width, bounds.height), 2.0)
        let targetSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: 0, y: targetSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
            context.cgContext.restoreGState()
        }
    }

    private func looksLikeSummarizablePDFDocument(text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let latinCount = scalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }.count
        let cjkCount = scalars.filter {
            (0x4E00...0x9FFF).contains($0.value) ||
            (0x3040...0x30FF).contains($0.value) ||
            (0x31F0...0x31FF).contains($0.value)
        }.count
        let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count

        guard letterCount >= 80 || cjkCount >= 40 else { return false }

        let digitRatio = Double(digitCount) / Double(max(scalars.count, 1))
        if digitRatio > 0.35 {
            return false
        }

        let lowercased = text.lowercased()
        let documentSignals = [
            "abstract", "introduction", "method", "methods", "results",
            "discussion", "conclusion", "references", "study", "participants",
            "materials", "analysis", "experiment", "journal", "doi",
            "摘要", "前言", "研究", "方法", "結果", "討論", "結論", "參考文獻",
            "目的", "實驗", "分析", "資料", "教材", "章節", "作者",
            "要旨", "序論", "研究", "方法", "結果", "考察", "結論", "参考文献",
            "実験", "分析", "資料", "著者"
        ]
        let matchedSignals = documentSignals.filter { lowercased.contains($0) }.count
        if matchedSignals >= 2 {
            return true
        }

        let englishWordCount = lowercased
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 3 }
            .count
        if englishWordCount >= 60 && latinCount > max(cjkCount, 40) {
            return true
        }

        let condensed = text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return cjkCount >= 70 && condensed.count >= 90
    }

    private func cleanedOCRText(from text: String) -> OCRCleaningResult {
        let rawLines = text.components(separatedBy: .newlines)
        var seen = Set<String>()
        var keptLines: [String] = []
        var filteredCount = 0

        for rawLine in rawLines {
            let line = normalizedOCRLine(rawLine)
            guard !line.isEmpty else { continue }

            if isLikelyOCRNoiseLine(line) {
                filteredCount += 1
                continue
            }

            if seen.insert(line).inserted {
                keptLines.append(line)
            }
        }

        let cleanedText = keptLines.joined(separator: "\n")
        let finalText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        if finalText.isEmpty {
            return OCRCleaningResult(
                cleanedText: normalizedOCRLine(text),
                filteredLineCount: filteredCount
            )
        }

        return OCRCleaningResult(
            cleanedText: finalText,
            filteredLineCount: filteredCount
        )
    }

    private func normalizedOCRLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\t", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func isLikelyOCRNoiseLine(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let visibleScalars = line.unicodeScalars.filter { !$0.properties.isWhitespace }
        let visibleCount = visibleScalars.count

        if visibleCount == 0 {
            return true
        }

        let digitCount = visibleScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = visibleScalars.filter { CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0) }.count
        let letterLikeCount = visibleScalars.filter { CharacterSet.letters.contains($0) }.count
        let cjkCount = visibleScalars.filter { 0x4E00...0x9FFF ~= $0.value }.count

        let digitRatio = Double(digitCount) / Double(visibleCount)
        let punctuationRatio = Double(punctuationCount) / Double(visibleCount)

        if cjkCount >= 2 && punctuationRatio < 0.45 && digitRatio < 0.45 {
            return false
        }

        if lowercased.count <= 2 {
            return true
        }

        if CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: line)) {
            return true
        }

        if Self.ocrNoiseFragments.contains(where: { lowercased.contains($0) }) {
            return true
        }

        if digitRatio > 0.55 && letterLikeCount < 4 {
            return true
        }

        if punctuationRatio > 0.38 {
            return true
        }

        if visibleCount < 5 && letterLikeCount < 3 {
            return true
        }

        if repeatedCharacterRun(in: lowercased) >= 5 {
            return true
        }

        return false
    }

    private func salvagedVerticalCJKText(from rawText: String) -> String {
        var seen = Set<String>()
        let keptLines = rawText
            .components(separatedBy: .newlines)
            .map(normalizedOCRLine)
            .filter { line in
                guard !line.isEmpty else { return false }
                let scalars = line.unicodeScalars.filter { !$0.properties.isWhitespace }
                let visibleCount = scalars.count
                guard visibleCount >= 2 else { return false }

                let cjkCount = scalars.filter { 0x4E00...0x9FFF ~= $0.value }.count
                let digitCount = scalars.filter { CharacterSet.decimalDigits.contains($0) }.count
                let punctuationCount = scalars.filter {
                    CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
                }.count

                let digitRatio = Double(digitCount) / Double(max(visibleCount, 1))
                let punctuationRatio = Double(punctuationCount) / Double(max(visibleCount, 1))
                guard cjkCount >= 2 else { return false }
                guard digitRatio < 0.45, punctuationRatio < 0.45 else { return false }
                return seen.insert(line).inserted
            }

        return keptLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func repeatedCharacterRun(in text: String) -> Int {
        var longest = 1
        var current = 1
        var previous: Character?

        for character in text {
            if character == previous {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
                previous = character
            }
        }

        return longest
    }

    private func repairedOCRTextIfNeeded(
        _ cleanedText: String,
        rawText: String?,
        purpose: OCRRepairPurpose
    ) async -> String {
        let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeRepairableDocumentOCR(trimmed) else { return trimmed }

        let repairStart = CFAbsoluteTimeGetCurrent()
        let repaired = try? await repairDocumentOCRText(
            trimmed,
            rawText: rawText,
            purpose: purpose
        )
        let normalized = normalizedAIRepairedDocumentText(repaired?.documentText)
        let finalText = shouldAcceptRepairedOCR(original: trimmed, repaired: normalized) ? normalized : trimmed

        await PerformanceTraceRecorder.shared.record(
            name: "ocr_document_repair",
            durationMs: elapsedDurationMs(since: repairStart),
            metadata: [
                "purpose": repairPurposeLabel(purpose),
                "original_chars": "\(trimmed.count)",
                "repaired_chars": "\(normalized.count)",
                "accepted": finalText == normalized && !normalized.isEmpty ? "true" : "false"
            ]
        )

        return finalText
    }

    private func repairDocumentOCRText(
        _ cleanedText: String,
        rawText: String?,
        purpose: OCRRepairPurpose
    ) async throws -> OCRDocumentRepairResponse? {
        let prompt = ocrDocumentRepairPrompt(
            cleanedText: cleanedText,
            rawText: rawText,
            purpose: purpose
        )

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": ocrRepairSystemInstruction()
                ],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.05
        ]

        let (data, response) = try await performProtectedRequest(
            payload: payload,
            requestKind: .ocrRepair
        )
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else { return nil }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentString = message["content"] as? String,
              let contentData = contentString.data(using: .utf8) else {
            return nil
        }

        return try JSONDecoder().decode(OCRDocumentRepairResponse.self, from: contentData)
    }

    private func ocrDocumentRepairPrompt(
        cleanedText: String,
        rawText: String?,
        purpose: OCRRepairPurpose
    ) -> String {
        let usageInstruction: String
        switch purpose {
        case .knowledgeImport:
            usageInstruction = "這份修復後文字會再送去做知識點辨識，所以請優先保留主題、章節、名詞、關鍵句與可學習內容。"
        case .referenceSummary:
            usageInstruction = "這份修復後文字會再送去做 OCR 摘要，所以請優先保留句子連續性與可閱讀段落。"
        case .pdfSummary:
            usageInstruction = "這份修復後文字會再送去做 PDF 摘要，所以請優先保留標題、段落與研究或文件敘述脈絡。"
        }

        let rawSection = if let rawText, !rawText.isEmpty {
            """
            原始 OCR：
            \(rawText.prefix(5000))
            """
        } else {
            ""
        }

        return """
        以下文字來自 Apple Vision OCR，可能是中文、英文、日文，來源可能是書籍、教科書、書頁、報紙、期刊、雜誌、廣告、型錄、說明書、手冊或研究文件。
        請你做「保守修復」，不要摘要，不要翻譯，不要補寫看不到的句子。

        任務要求：
        1. 只修正常見 OCR 明顯錯字、字元斷裂、段落錯行、跨欄拼接、標題碎裂與重複雜訊。
        2. 優先保留原文語言與混合語言，不要把中文變英文，也不要把日文翻成中文。
        3. 刪除明顯無意義的頁碼、版權尾巴、掃描噪點、重複網址、條碼片段、孤立數字列。
        4. 如果某些地方不確定，就保留原樣，不要猜測。
        5. 若看起來是多欄排版、報章期刊或雜誌文章，請盡量重排成合理閱讀順序。
        6. 若看起來是廣告、商品說明或使用手冊，請保留品牌、產品名、規格、警語、成分、步驟等有資訊價值內容。
        7. \(usageInstruction)

        清洗後 OCR：
        \(cleanedText.prefix(5000))

        \(rawSection)

        請嚴格回傳 JSON：
        {"document_text":"修復後文字","document_type":"book_page | newspaper | journal | magazine | advertisement | manual | mixed_document | unknown","confidence_note":"簡短說明這次只做了哪些保守修復"}
        """
    }

    private func normalizedAIRepairedDocumentText(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeRepairableDocumentOCR(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 48 else { return false }

        let lines = trimmed.components(separatedBy: .newlines).map(normalizedOCRLine).filter { !$0.isEmpty }
        let lowercased = trimmed.lowercased()
        let visibleScalars = trimmed.unicodeScalars.filter { !$0.properties.isWhitespace }
        let cjkCount = visibleScalars.filter {
            (0x4E00...0x9FFF).contains($0.value) ||
            (0x3040...0x30FF).contains($0.value) ||
            (0x31F0...0x31FF).contains($0.value)
        }.count
        let latinCount = visibleScalars.filter { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }.count
        let digitCount = visibleScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let punctuationCount = visibleScalars.filter {
            CharacterSet.punctuationCharacters.contains($0) || CharacterSet.symbols.contains($0)
        }.count
        let visibleCount = visibleScalars.count
        let digitRatio = Double(digitCount) / Double(max(visibleCount, 1))
        let punctuationRatio = Double(punctuationCount) / Double(max(visibleCount, 1))
        let documentKeywordScore = keywordScore(in: lowercased, terms: Self.educationalDocumentTerms + Self.generalDocumentTerms)

        if documentKeywordScore >= 2 {
            return true
        }

        if lines.count >= 4 && (cjkCount >= 18 || latinCount >= 40) && digitRatio < 0.45 {
            return true
        }

        if trimmed.count >= 140 && punctuationRatio < 0.34 && digitRatio < 0.38 {
            return true
        }

        return false
    }

    private func shouldAcceptRepairedOCR(original: String, repaired: String) -> Bool {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRepaired = repaired.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRepaired.isEmpty else { return false }

        let originalScore = cleanedOCRScore(for: trimmedOriginal)
        let repairedScore = cleanedOCRScore(for: trimmedRepaired)
        let originalNoise = estimatedOCRNoisePenalty(for: trimmedOriginal)
        let repairedNoise = estimatedOCRNoisePenalty(for: trimmedRepaired)

        guard repairedScore >= max(24, Int(Double(originalScore) * 0.62)) else {
            return false
        }

        if repairedNoise + 2 < originalNoise {
            return true
        }

        if repairedScore >= originalScore + 18 {
            return true
        }

        return repairedScore >= originalScore && repairedNoise <= originalNoise
    }

    private func estimatedOCRNoisePenalty(for text: String) -> Int {
        let lines = text.components(separatedBy: .newlines).map(normalizedOCRLine).filter { !$0.isEmpty }
        let noiseLines = lines.filter { isLikelyOCRNoiseLine($0) }.count
        let repeatedPenalty = max(0, repeatedCharacterRun(in: text.lowercased()) - 3)
        return (noiseLines * 4) + repeatedPenalty
    }

    private func repairPurposeLabel(_ purpose: OCRRepairPurpose) -> String {
        switch purpose {
        case .knowledgeImport:
            return "knowledge_import"
        case .referenceSummary:
            return "reference_summary"
        case .pdfSummary:
            return "pdf_summary"
        }
    }

    private func normalizedOCRSummary(_ summary: String?, fallbackFrom cleanedText: String) -> String? {
        let normalized = summary?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalized, normalized.count >= 24 {
            return normalized
        }

        guard cleanedText.count > 220 else { return nil }
        let compact = cleanedText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return compact.count <= 160 ? compact : String(compact.prefix(160)) + "…"
    }

    private func normalizedSourceSummary(_ summary: String?) -> String? {
        let normalized = summary?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalized, normalized.count >= 12 else { return nil }
        return normalized
    }

    private func shouldPreferOCRPrimaryPath(cleanedText: String, cleaningResult: OCRCleaningResult) -> Bool {
        let trimmed = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard shouldCreateReferenceOCR(from: trimmed, cleaningResult: cleaningResult) else { return false }
        return trimmed.count >= 24 || trimmed.components(separatedBy: .newlines).count >= 2
    }

    private func buildKnowledgeImportPreview(
        result: AIKnowledgeResponse,
        recognitionMode: ImportRecognitionMode,
        existingTitles: Set<String>,
        source: KnowledgeImportSourceKind,
        extractedText: String?,
        sourceSummary: String?,
        filteredNoiseLineCount: Int
    ) -> KnowledgeImportPreview {
        var dedupingTitles = existingTitles
        var candidates: [KnowledgeImportCandidate] = []
        var rejected: [RejectedKnowledgeImportCandidate] = []
        let contextText = [
            extractedText ?? "",
            sourceSummary ?? "",
            result.sourceSummary ?? ""
        ]
        .joined(separator: "\n")

        for dto in result.nodes {
            if let incidentalReason = rejectionReasonForIncidentalScene(
                title: dto.title,
                content: dto.content,
                recognitionMode: recognitionMode,
                source: source,
                contextText: contextText
            ) {
                rejected.append(
                    RejectedKnowledgeImportCandidate(
                        title: dto.title,
                        reason: incidentalReason
                    )
                )
                continue
            }

            let validation = KnowledgeNodeCleaner.validate(
                title: dto.title,
                content: dto.content,
                categoryRaw: dto.category,
                source: .ai,
                existingTitles: dedupingTitles
            )

            guard let draft = validation.draft else {
                rejected.append(
                    RejectedKnowledgeImportCandidate(
                        title: dto.title,
                        reason: validation.rejectionReason ?? localizedKnowledgeRuleRejection()
                    )
                )
                continue
            }

            candidates.append(KnowledgeImportCandidate(draft: draft, source: .ai))
            dedupingTitles.insert(KnowledgeNodeCleaner.normalizedKey(for: draft.title))
        }

        return KnowledgeImportPreview(
            recognitionMode: recognitionMode,
            source: source,
            extractedText: extractedText,
            sourceSummary: sourceSummary,
            filteredNoiseLineCount: filteredNoiseLineCount,
            candidates: candidates,
            rejected: rejected
        )
    }

    private func rejectionReasonForIncidentalScene(
        title: String,
        content: String,
        recognitionMode: ImportRecognitionMode,
        source: KnowledgeImportSourceKind,
        contextText: String
    ) -> String? {
        let _ = title
        let _ = content
        let _ = recognitionMode
        let _ = source
        let _ = contextText
        return nil
    }

    private func localizedKnowledgeRuleRejection() -> String {
        switch RegionUIStore.runtimeRegion() {
        case .taiwan:
            return "不符合知識點規則"
        case .unitedStates:
            return "This does not meet the knowledge entry rules."
        case .japan:
            return "知識点のルールに合いません。"
        }
    }

    private func keywordScore(in text: String, terms: [String]) -> Int {
        let normalized = text.lowercased()
        return terms.reduce(into: 0) { score, term in
            if normalized.contains(term.lowercased()) {
                score += 1
            }
        }
    }

    private func ocrKnowledgePrompt(for extractedText: String, mode: ImportRecognitionMode) -> String {
        let _ = mode
        return """
        你是一位擅長把影像文字整理成知識點的 AI。以下文字是我透過 Apple Vision OCR 從照片中擷取並清洗後得到的內容，可能來自中文、英文或日文的教科書封面、書頁、講義、論文、報紙、期刊、雜誌、廣告、商品說明、使用手冊、標示牌或一般物件：

        「\(extractedText)」

        任務絕對要求：
        0. \(userVisibleLanguageInstruction()) 其中 title、content、source_summary 都必須使用該語言；只有 category 必須維持下面指定的 6 個中文值。
        1. 優先理解畫面中央主體最可能代表的主題、物件、概念、用途、學科或內容焦點。
        2. 可產生 1 到 4 個真正可用的知識點。若像教材、書頁、報刊、期刊、雜誌或論文，請整理成概念、主題、課程背景、章節入口或論述重點；若像廣告、型錄、說明書、手冊、商品或一般物件，請整理成用途、成分、規格、限制、警語、背景或重要特徵。
        3. 若同一畫面有多個東西，只聚焦最可能位於中央的主體，不要把周邊雜物混進來。
        4. 標題必須可讀、具體，不能只是碎片字、頁碼、版權資訊、價格、條碼或空泛詞。
        5. 內容必須是整理後對學習有意義的說明，不要只重複標題。
        6. 門類必須從這 6 個值擇一：自然科學、數學科學、系統科學、思維科學、人體科學、社會科學。
        7. 請提供一段 80 到 180 字的「source_summary」，說明這張圖大意與可學到什麼；若可辨識為教材或教科書，請補一句背景說明。
        8. 請忽略 OCR 雜訊、網址、版權資訊、價格、條碼、出版頁碎片與明顯無意義內容。
        9. 若目前執行環境真的具備即時網路查詢能力，才允許用可靠來源做保守交叉比對；沒有的話不能假裝查過。
        10. 即使有網路資訊，也只能導入已被當前 OCR 線索高度支撐的內容；不確定時寧可保守。

        請嚴格以 JSON 格式回傳：\(localizedKnowledgeJSONExample())
        """
    }

    private func requestKnowledgeFromOCRText(
        _ extractedText: String,
        mode: ImportRecognitionMode
    ) async throws -> AIKnowledgeResponse {
        let prompt = ocrKnowledgePrompt(for: extractedText, mode: mode)

        let payload: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": knowledgeSystemInstruction()],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        return try await executeKnowledgeRequest(
            payload: payload,
            requestKind: .smartScan,
            failureMessage: {
                switch RegionUIStore.runtimeRegion() {
                case .taiwan: return "AI 服務目前無法分析這份 OCR 內容。"
                case .unitedStates: return "AI could not analyze this OCR content right now."
                case .japan: return "現在このOCR内容をAIで分析できません。"
                }
            }()
        )
    }

    private func imageKnowledgePrompt(
        for mode: ImportRecognitionMode,
        supportingOCRText: String?,
        prioritizeDocumentCover: Bool
    ) -> String {
        let _ = mode
        var sections: [String] = [
        """
        你是一位擅長從圖片整理知識點的 AI。請直接觀看這張圖片本身，從畫面中的構圖、主體、文字、版面、封面、包裝、標示、場景與上下文，判斷最值得整理的知識。圖片可能包含中文、英文或日文。
        """
        ]

        if prioritizeDocumentCover {
            sections.append(
        """
        這張圖高度疑似是書籍、教材、講義或手冊封面。請優先辨識封面主標題、學習主題、適用對象與封面明確寫出的定位；不要腦補內頁章節、延伸概念或未直接看見的應用內容。
        """
            )
        }

        if let supportingOCRText, !supportingOCRText.isEmpty {
            sections.append(
        """
        可作為輔助線索的 OCR 片段如下，只能當作次要提示，仍須以圖片實際看見的封面內容為主：

        「\(supportingOCRText)」
        """
            )
        }

        sections.append(
        """

        任務絕對要求：
        0. \(userVisibleLanguageInstruction()) 其中 title、content、source_summary 都必須使用該語言；只有 category 必須維持下面指定的 6 個中文值。
        1. \(prioritizeDocumentCover
            ? "若這是封面，優先根據整體版面中的最大標題、書名、副標與受眾文案判斷主題，不要把中央插圖或裝飾元素當成主體。"
            : "優先聚焦最接近畫面中央的主體。")
        2. 可產生 1 到 4 個真正可用的知識點。若主體像教材、書頁、投影片或教科書，請整理成主題、概念、章節入口或學習背景；若主體像商品、器材、標示或一般物件，請整理成用途、規格、成分、背景或重要特徵。若明顯是封面，優先整理「這是什麼書/教材」與「它在教什麼」，不要擴寫出看不見的章節概念。
        3. 若周圍還有其他物件，不要把邊角雜物混進主要判斷。
        4. 標題必須具體可讀，不能只是碎片字、空泛詞或單純的拍照描述。
        5. 內容要整理成對使用者有價值的知識，而不是只描述照片。
        6. 門類仍然必須從自然科學、數學科學、系統科學、思維科學、人體科學、社會科學中選最接近的一類。
        7. 請提供一段 80 到 160 字的「source_summary」，說明這張圖大意與可學到什麼；若可辨識為教材或教科書，請補一句背景說明。
        8. 若目前執行環境真的具備即時網路查詢能力，才允許用可靠來源保守交叉比對；沒有的話不能假裝查過。

        請嚴格以 JSON 格式回傳：\(localizedKnowledgeJSONExample())
        """
        )

        return sections.joined(separator: "\n\n")
    }

    private func imageRequestContent(
        prompt: String,
        fullImageDataURL: String,
        centeredImage: UIImage?,
        profile: ImagePayloadProfile,
        prioritizeDocumentCover: Bool
    ) -> [[String: Any]] {
        var content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "text", "text": imageFocusInstruction(prioritizeDocumentCover: prioritizeDocumentCover)]
        ]

        if !prioritizeDocumentCover,
           let centeredImage,
           let centeredDataURL = makeAIAnalysisImageDataURL(
            from: centeredImage,
            maxDimension: profile.maxDimension,
            maxBytes: profile.maxBytes
           ) {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": centeredDataURL,
                    "detail": profile.detail
                ]
            ])
        }

        content.append([
            "type": "image_url",
            "image_url": [
                "url": fullImageDataURL,
                "detail": profile.detail
            ]
        ])

        return content
    }

    private func requestKnowledgeFromImage(
        _ image: UIImage,
        mode: ImportRecognitionMode,
        supportingOCRText: String? = nil,
        prioritizeDocumentCover: Bool = false
    ) async throws -> AIKnowledgeResponse {
        let prompt = imageKnowledgePrompt(
            for: mode,
            supportingOCRText: supportingOCRText,
            prioritizeDocumentCover: prioritizeDocumentCover
        )

        let payloadProfiles = [
            ImagePayloadProfile(maxDimension: 960, maxBytes: 150_000, detail: "low"),
            ImagePayloadProfile(maxDimension: 768, maxBytes: 90_000, detail: "low")
        ]
        let centeredImage = prioritizeDocumentCover ? nil : centerPriorityImages(from: image).first

        var last413Data = Data()
        for profile in payloadProfiles {
            guard let imageDataURL = makeAIAnalysisImageDataURL(
                from: image,
                maxDimension: profile.maxDimension,
                maxBytes: profile.maxBytes
            ) else {
                continue
            }

            let payload: [String: Any] = [
                "model": "gpt-4o",
                "response_format": ["type": "json_object"],
                "messages": [
                    ["role": "system", "content": knowledgeSystemInstruction()],
                    [
                        "role": "user",
                        "content": imageRequestContent(
                            prompt: prompt,
                            fullImageDataURL: imageDataURL,
                            centeredImage: centeredImage,
                            profile: profile,
                            prioritizeDocumentCover: prioritizeDocumentCover
                        )
                    ]
                ],
                "temperature": 0.3
            ]

            do {
                return try await executeKnowledgeRequest(
                    payload: payload,
                    requestKind: .smartScan,
                    failureMessage: {
                        switch RegionUIStore.runtimeRegion() {
                        case .taiwan: return "AI 服務暫時無法處理這張圖片。"
                        case .unitedStates: return "AI cannot process this image right now."
                        case .japan: return "現在この画像をAIで処理できません。"
                        }
                    }()
                )
            } catch let error as NSError where error.code == 413 {
                last413Data = Data((error.userInfo["response_data"] as? Data) ?? Data())
                continue
            }
        }

        throw noteImportError(
            code: 413,
            responseData: last413Data,
            fallbackMessage: {
                switch RegionUIStore.runtimeRegion() {
                case .taiwan: return "圖片資訊量太大，AI 服務目前吃不下這張圖。請裁切重點區域後再試。"
                case .unitedStates: return "This image carries too much information for the AI service right now. Please crop the key area and try again."
                case .japan: return "この画像は情報量が多すぎて現在のAIサービスでは処理できません。重要な部分を切り抜いて再度お試しください。"
                }
            }()
        )
    }

    private func executeKnowledgeRequest(
        payload: [String: Any],
        requestKind: ProtectedRequestKind,
        failureMessage: String
    ) async throws -> AIKnowledgeResponse {
        let aiStart = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await performProtectedRequest(
            payload: payload,
            requestKind: requestKind
        )
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        await PerformanceTraceRecorder.shared.record(
            name: "note_import_ai_request",
            durationMs: elapsedDurationMs(since: aiStart),
            metadata: [
                "payload_bytes": "\(requestBodyBytes(for: payload))",
                "response_bytes": "\(data.count)",
                "status": "\(statusCode)"
            ]
        )

        print("🌍 伺服器狀態碼: \(statusCode)")

        guard (200...299).contains(statusCode) else {
            throw noteImportError(code: statusCode, responseData: data, fallbackMessage: failureMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentString = message["content"] as? String,
              let contentData = contentString.data(using: .utf8) else {
            throw NSError(
                domain: "KnowledgeExtractionService",
                code: statusCode,
                userInfo: [NSLocalizedDescriptionKey: {
                    switch RegionUIStore.runtimeRegion() {
                    case .taiwan: return "AI 服務回傳了非 JSON 內容，這次無法完成知識提取。"
                    case .unitedStates: return "The AI service returned non-JSON content, so extraction could not be completed."
                    case .japan: return "AIサービスがJSON以外の内容を返したため、知識抽出を完了できませんでした。"
                    }
                }()]
            )
        }

        return try JSONDecoder().decode(AIKnowledgeResponse.self, from: contentData)
    }

    private func makeProtectedRequest(
        payload: [String: Any],
        requestKind: ProtectedRequestKind
    ) async throws -> URLRequest {
        let appUserID = SubscriptionIdentityStore.shared.appUserID
        let requestTarget = try await ProtectedServiceAuthStore.shared.requestTarget(
            legacyURL: Self.serverURL,
            appUserID: appUserID,
            entitlementID: configuredEntitlementID,
            requestKind: requestKind.rawValue,
            timeout: Self.requestTimeout
        )

        var request = URLRequest(url: requestTarget.url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appUserID, forHTTPHeaderField: "X-CogniSphere-App-User-ID")
        request.setValue(configuredEntitlementID, forHTTPHeaderField: "X-CogniSphere-Entitlement-ID")
        request.setValue(requestKind.rawValue, forHTTPHeaderField: "X-CogniSphere-Request-Kind")
        if let bearerToken = requestTarget.bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return request
    }

    private func performProtectedRequest(
        payload: [String: Any],
        requestKind: ProtectedRequestKind
    ) async throws -> (Data, URLResponse) {
        let request = try await makeProtectedRequest(payload: payload, requestKind: requestKind)
        let response = try await performURLRequest(request)
        if shouldRefreshProtectedSession(after: response, request: request) {
            await ProtectedServiceAuthStore.shared.invalidateSession()
            let retryRequest = try await makeProtectedRequest(payload: payload, requestKind: requestKind)
            return try await performURLRequest(retryRequest)
        }
        return response
    }

    private func performURLRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            guard shouldRetryProtectedRequest(after: error) else {
                throw error
            }

            try? await Task.sleep(for: .milliseconds(600))
            return try await URLSession.shared.data(for: request)
        }
    }

    private func shouldRefreshProtectedSession(
        after response: (Data, URLResponse),
        request: URLRequest
    ) -> Bool {
        guard request.value(forHTTPHeaderField: "Authorization") != nil,
              let httpResponse = response.1 as? HTTPURLResponse else {
            return false
        }
        return httpResponse.statusCode == 401
    }

    private func shouldRetryProtectedRequest(after error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        guard nsError.domain == "KnowledgeExtractionService" else {
            return false
        }
        return Self.retryableStatusCodes.contains(nsError.code)
    }

    private var configuredEntitlementID: String {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: "RevenueCatEntitlementID") as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "pro" : trimmed
    }

    private func requestBodyBytes(for payload: [String: Any]) -> Int {
        (try? JSONSerialization.data(withJSONObject: payload).count) ?? 0
    }

    private func makeAIAnalysisImageDataURL(from image: UIImage, maxDimension: CGFloat, maxBytes: Int) -> String? {
        let resizedImage = resizedImageForAI(image, maxDimension: maxDimension)
        let qualities: [CGFloat] = [0.52, 0.42, 0.34, 0.28, 0.22]

        for quality in qualities {
            if let data = resizedImage.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return "data:image/jpeg;base64,\(data.base64EncodedString())"
            }
        }

        return nil
    }

    private func resizedImageForAI(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func noteImportError(code: Int, responseData: Data, fallbackMessage: String) -> NSError {
        let serverMessage = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let message: String
        if let serverMessage,
           !serverMessage.isEmpty,
           serverMessage.count <= 180,
           !serverMessage.lowercased().contains("<html"),
           !serverMessage.lowercased().contains("<!doctype"),
           !serverMessage.lowercased().contains("<body") {
            message = "\(fallbackMessage)\n\(serverMessage)"
        } else {
            message = fallbackMessage
        }

        return NSError(
            domain: "KnowledgeExtractionService",
            code: code,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                "response_data": responseData
            ]
        )
    }

    private func ocrSummaryReferenceTitle(for source: KnowledgeImportSourceKind) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = RegionUIStore.runtimeLocale()
        let date = formatter.string(from: Date())

        switch source {
        case .imageAI:
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "AI 摘要 \(date)"
            case .unitedStates: return "AI Summary \(date)"
            case .japan: return "AI要約 \(date)"
            }
        case .imageOCR:
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "OCR 摘要 \(date)"
            case .unitedStates: return "OCR Summary \(date)"
            case .japan: return "OCR要約 \(date)"
            }
        case .text:
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "文字摘要 \(date)"
            case .unitedStates: return "Text Summary \(date)"
            case .japan: return "テキスト要約 \(date)"
            }
        }
    }

    private func imageOCRSummaryReferenceTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = RegionUIStore.runtimeLocale()
        let date = formatter.string(from: Date())
        switch RegionUIStore.runtimeRegion() {
        case .taiwan: return "OCR 摘要 \(date)"
        case .unitedStates: return "OCR Summary \(date)"
        case .japan: return "OCR要約 \(date)"
        }
    }

    private func pdfSummaryReferenceTitle() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = RegionUIStore.runtimeLocale()
        let date = formatter.string(from: Date())
        switch RegionUIStore.runtimeRegion() {
        case .taiwan: return "PDF 摘要 \(date)"
        case .unitedStates: return "PDF Summary \(date)"
        case .japan: return "PDF要約 \(date)"
        }
    }
}

private struct OCRCleaningResult {
    let cleanedText: String
    let filteredLineCount: Int
}
