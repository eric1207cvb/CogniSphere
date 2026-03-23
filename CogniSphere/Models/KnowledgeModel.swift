import Foundation
import SwiftData
import SwiftUI

@Model
final class KnowledgeLibrary {
    var id: String = UUID().uuidString
    var name: String = ""
    var createdAt: Date = Date()
    var archivedAt: Date?

    init(id: String = UUID().uuidString, name: String, createdAt: Date = Date(), archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

// MARK: - 知識門類枚舉
enum KnowledgeCategory: String, Codable, CaseIterable {
    case naturalScience = "自然科學"
    case mathematicalScience = "數學科學"
    case systemicScience = "系統科學"
    case thinkingScience = "思維科學"
    case humanScience = "人體科學"
    case socialScience = "社會科學"
}

extension KnowledgeCategory {
    var localizedName: String {
        switch (self, RegionUIStore.runtimeRegion()) {
        case (.naturalScience, .taiwan):
            return "自然科學"
        case (.naturalScience, .unitedStates):
            return "Natural Science"
        case (.naturalScience, .japan):
            return "自然科学"
        case (.mathematicalScience, .taiwan):
            return "數學科學"
        case (.mathematicalScience, .unitedStates):
            return "Mathematical Science"
        case (.mathematicalScience, .japan):
            return "数学科学"
        case (.systemicScience, .taiwan):
            return "系統科學"
        case (.systemicScience, .unitedStates):
            return "Systems Science"
        case (.systemicScience, .japan):
            return "システム科学"
        case (.thinkingScience, .taiwan):
            return "思維科學"
        case (.thinkingScience, .unitedStates):
            return "Thinking Science"
        case (.thinkingScience, .japan):
            return "思考科学"
        case (.humanScience, .taiwan):
            return "人體科學"
        case (.humanScience, .unitedStates):
            return "Human Science"
        case (.humanScience, .japan):
            return "人体科学"
        case (.socialScience, .taiwan):
            return "社會科學"
        case (.socialScience, .unitedStates):
            return "Social Science"
        case (.socialScience, .japan):
            return "社会科学"
        }
    }

    var accentColor: Color {
        switch self {
        case .naturalScience:
            return Color(red: 0.39, green: 0.80, blue: 0.45)
        case .mathematicalScience:
            return Color(red: 0.44, green: 0.76, blue: 0.96)
        case .systemicScience:
            return Color(red: 0.98, green: 0.60, blue: 0.42)
        case .thinkingScience:
            return Color(red: 0.79, green: 0.60, blue: 0.94)
        case .humanScience:
            return Color(red: 0.92, green: 0.54, blue: 0.54)
        case .socialScience:
            return Color(red: 0.94, green: 0.74, blue: 0.38)
        }
    }

    var softBackgroundColor: Color {
        accentColor.opacity(0.14)
    }
}

enum KnowledgeCategoryResolver {
    private struct RuleSet {
        let category: KnowledgeCategory
        let keywords: [String]
    }

    private struct MatchScore {
        let category: KnowledgeCategory
        let score: Int
    }

    // Central subject mapping table. Local rules decide first; if ambiguous, fall back to AI.
    private static let ruleSets: [RuleSet] = [
        RuleSet(category: .naturalScience, keywords: [
            "自然科學", "物理學", "化學", "生物學", "生物化學", "分子生物學", "細胞生物學",
            "遺傳學", "微生物學", "生態學", "演化生物學", "有機化學", "無機化學", "分析化學",
            "物理化學", "環境科學", "地球科學", "地質學", "天文學", "海洋學", "氣象學",
            "材料科學", "材料化學", "量子化學", "量子物理", "熱力學", "光譜學",
            "physics", "chemistry", "biology", "biochemistry", "molecular biology",
            "cell biology", "genetics", "microbiology", "ecology", "evolution",
            "organic chemistry", "inorganic chemistry", "analytical chemistry",
            "physical chemistry", "environmental science", "earth science", "geology",
            "astronomy", "oceanography", "meteorology", "materials science"
        ]),
        RuleSet(category: .mathematicalScience, keywords: [
            "數學科學", "數學", "統計學", "機率論", "代數", "幾何", "微積分", "拓樸",
            "數值分析", "離散數學", "微分方程", "最佳化", "線性代數", "圖論", "組合學",
            "測度論", "實分析", "複分析", "數理統計", "隨機過程", "密碼學",
            "mathematics", "math", "statistics", "probability", "algebra", "geometry",
            "calculus", "topology", "numerical analysis", "discrete mathematics",
            "differential equations", "optimization", "linear algebra", "graph theory",
            "combinatorics", "real analysis", "complex analysis", "stochastic processes",
            "cryptography"
        ]),
        RuleSet(category: .systemicScience, keywords: [
            "系統科學", "系統工程", "控制理論", "控制工程", "資訊科學", "資訊工程", "電腦科學",
            "人工智慧", "機器學習", "深度學習", "資料科學", "資料工程", "軟體工程", "網路科學",
            "網路工程", "演算法", "作業系統", "資料庫", "分散式系統", "訊號處理", "機器人",
            "資訊理論", "控制系統", "系統動力學", "賽局模擬", "運籌學", "系統分析", "控制論",
            "computer science", "information science", "systems engineering", "control theory",
            "control engineering", "artificial intelligence", "machine learning",
            "deep learning", "data science", "data engineering", "software engineering",
            "network science", "algorithms", "operating systems", "database", "databases",
            "distributed systems", "signal processing", "robotics", "information theory",
            "system dynamics", "operations research", "cybernetics"
        ]),
        RuleSet(category: .thinkingScience, keywords: [
            "思維科學", "哲學", "邏輯學", "知識論", "科學哲學", "心智哲學", "方法論",
            "語言學", "語意學", "語用學", "句法學", "認知科學", "推理", "決策理論",
            "形式邏輯", "符號邏輯", "心理語言學", "認知心理學", "思考方法", "批判思考",
            "philosophy", "logic", "epistemology", "philosophy of science", "philosophy of mind",
            "methodology", "linguistics", "semantics", "pragmatics", "syntax",
            "cognitive science", "reasoning", "decision theory", "formal logic",
            "symbolic logic", "psycholinguistics", "critical thinking"
        ]),
        RuleSet(category: .humanScience, keywords: [
            "人體科學", "醫學", "臨床醫學", "解剖學", "生理學", "病理學", "藥理學", "神經科學",
            "免疫學", "內分泌學", "營養學", "護理學", "牙醫學", "公衛", "公共衛生", "流行病學",
            "復健", "醫療", "藥學", "兒科", "心臟學", "腫瘤學", "神經醫學", "精神醫學",
            "medicine", "clinical medicine", "anatomy", "physiology", "pathology",
            "pharmacology", "neuroscience", "immunology", "endocrinology", "nutrition",
            "nursing", "dentistry", "public health", "epidemiology", "rehabilitation",
            "pharmacy", "pediatrics", "cardiology", "oncology", "psychiatry"
        ]),
        RuleSet(category: .socialScience, keywords: [
            "社會科學", "經濟學", "社會學", "政治學", "人類學", "法學", "教育學", "傳播學",
            "管理學", "行銷學", "財務金融", "金融學", "國際關係", "公共政策", "行政學",
            "歷史學", "文化研究", "媒體研究", "地理學", "社會心理學", "組織行為", "市場學",
            "economics", "sociology", "political science", "anthropology", "law", "education",
            "communication", "management", "marketing", "finance", "international relations",
            "public policy", "public administration", "history", "cultural studies",
            "media studies", "geography", "social psychology", "organizational behavior"
        ])
    ]

    static func resolve(title: String, content: String) -> KnowledgeCategory? {
        let normalized = normalizedText(title + " " + content)
        guard !normalized.isEmpty else { return nil }

        let rankedScores = ruleSets
            .map { ruleSet in
                MatchScore(category: ruleSet.category, score: score(for: ruleSet.keywords, in: normalized))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                return lhs.score > rhs.score
            }

        guard let best = rankedScores.first, best.score > 0 else { return nil }
        if let second = rankedScores.dropFirst().first, best.score - second.score <= 1 {
            return nil
        }
        return best.category
    }

    private static func score(for keywords: [String], in text: String) -> Int {
        keywords.reduce(into: 0) { partialResult, keyword in
            let normalizedKeyword = keyword.lowercased()
            guard text.contains(normalizedKeyword) else { return }
            partialResult += normalizedKeyword.count >= 8 ? 3 : 2
        }
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// 💡 錄音類型
enum ReferenceType: String, Codable, CaseIterable {
    case web = "網頁連結"
    case image = "圖片"
    case pdf = "PDF 文件"
    case text = "補充筆記"
    case audio = "語音備忘錄"
}

extension ReferenceType {
    var localizedName: String {
        switch (self, RegionUIStore.runtimeRegion()) {
        case (.web, .taiwan):
            return "網頁連結"
        case (.web, .unitedStates):
            return "Web Link"
        case (.web, .japan):
            return "Webリンク"
        case (.image, .taiwan):
            return "圖片"
        case (.image, .unitedStates):
            return "Image"
        case (.image, .japan):
            return "画像"
        case (.pdf, .taiwan):
            return "PDF 文件"
        case (.pdf, .unitedStates):
            return "PDF Document"
        case (.pdf, .japan):
            return "PDFファイル"
        case (.text, .taiwan):
            return "補充筆記"
        case (.text, .unitedStates):
            return "Text Note"
        case (.text, .japan):
            return "補足メモ"
        case (.audio, .taiwan):
            return "語音備忘錄"
        case (.audio, .unitedStates):
            return "Voice Memo"
        case (.audio, .japan):
            return "音声メモ"
        }
    }
}

enum KnowledgeNodeInputSource {
    case ai
    case manual
}

struct SanitizedKnowledgeDraft {
    let title: String
    let content: String
    let category: KnowledgeCategory
}

struct KnowledgeNodeValidationResult {
    let draft: SanitizedKnowledgeDraft?
    let rejectionReason: String?
}

enum KnowledgeNodeCleaner {
    private static let disallowedExactTitles: Set<String> = [
        "ok", "gotop", "isbn", "index", "chapter", "cover", "simple", "easy",
        "世界", "簡單", "簡單的", "屬於", "目錄", "封面", "作者", "出版社", "頁碼",
        "筆記", "內容", "教材", "照片", "圖片", "書名", "定價", "售價", "版權頁",
        "序", "前言", "附錄", "索引", "自序", "譯者", "審訂", "出版資訊", "catalog"
    ]

    private static let disallowedFragments: [String] = [
        "http://", "https://", "www.", ".com", ".tw", "版權所有", "copyright", "printed in",
        "all rights reserved", "國際標準書號", "版權頁", "未經授權", "scan me", "qr code"
    ]

    private static let publicationMetadataTerms: Set<String> = [
        "isbn", "issn", "doi", "cip", "gotop", "oreilly", "packt", "apress", "springer",
        "出版社", "出版", "出版者", "發行人", "作者", "編者", "譯者", "審訂", "校閱",
        "版權", "版權頁", "封面", "書名", "書系", "定價", "售價", "電話", "地址", "網址",
        "頁碼", "頁", "第頁", "章節", "第章", "目錄", "索引", "附錄", "再版", "初版", "修訂版",
        "印行", "印刷", "發行", "出版日期", "刷次", "書號", "國際標準書號", "catalog", "contents"
    ]

    private static let titleNoiseTerms: Set<String> = [
        "世界", "簡單", "簡單的", "開始", "入門", "筆記", "封面", "教材", "範例", "習題",
        "作者", "出版社", "出版", "頁碼", "目錄", "附錄", "索引", "前言", "推薦", "導讀"
    ]

    static func validate(
        title rawTitle: String,
        content rawContent: String,
        categoryRaw: String,
        source: KnowledgeNodeInputSource,
        existingTitles: Set<String>
    ) -> KnowledgeNodeValidationResult {
        let title = normalizedText(rawTitle)
        let content = normalizedText(rawContent)
        let titleKey = normalizedKey(for: title)
        let aiSuggestedCategory = KnowledgeCategory(rawValue: categoryRaw)
        let category: KnowledgeCategory
        switch source {
        case .ai:
            category = KnowledgeCategoryResolver.resolve(title: title, content: content)
                ?? aiSuggestedCategory
                ?? .thinkingScience
        case .manual:
            category = aiSuggestedCategory ?? .thinkingScience
        }

        guard !title.isEmpty else {
            return .init(draft: nil, rejectionReason: localizedRejection(.emptyTitle))
        }

        guard !content.isEmpty else {
            return .init(draft: nil, rejectionReason: localizedRejection(.emptyContent))
        }

        if existingTitles.contains(titleKey) {
            return .init(draft: nil, rejectionReason: localizedRejection(.duplicate, title: title))
        }

        if disallowedExactTitles.contains(titleKey) {
            return .init(draft: nil, rejectionReason: localizedRejection(.genericTitle, title: title))
        }

        if disallowedFragments.contains(where: { fragment in
            title.lowercased().contains(fragment) || content.lowercased().contains(fragment)
        }) {
            return .init(draft: nil, rejectionReason: localizedRejection(.copyrightNoise, title: title))
        }

        if isLikelyPublicationMetadata(title: title, content: content) {
            return .init(draft: nil, rejectionReason: localizedRejection(.publicationMetadata, title: title))
        }

        let titleStats = characterStats(for: title)
        let contentStats = characterStats(for: content)

        guard titleStats.letterLikeCount > 0 else {
            return .init(draft: nil, rejectionReason: localizedRejection(.missingLetters, title: title))
        }

        if titleStats.digitRatio > 0.45 {
            return .init(draft: nil, rejectionReason: localizedRejection(.tooManyDigits, title: title))
        }

        if source == .ai {
            if titleStats.visibleCount < 2 {
                return .init(draft: nil, rejectionReason: localizedRejection(.titleTooShort, title: title))
            }

            if contentStats.visibleCount < 12 {
                return .init(draft: nil, rejectionReason: localizedRejection(.contentTooShort, title: title))
            }

            if titleStats.isAllUppercaseLatin && titleStats.visibleCount <= 6 {
                return .init(draft: nil, rejectionReason: localizedRejection(.ocrNoise, title: title))
            }

            if isLikelyGenericAITitle(titleKey, title: title, stats: titleStats) {
                return .init(draft: nil, rejectionReason: localizedRejection(.notKnowledgeLike, title: title))
            }
        }

        let draft = SanitizedKnowledgeDraft(
            title: title,
            content: content,
            category: category
        )
        return .init(draft: draft, rejectionReason: nil)
    }

    static func normalizedKey(for text: String) -> String {
        normalizedText(text)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func isLikelyGenericAITitle(_ key: String, title: String, stats: CharacterStats) -> Bool {
        if key.count <= 3 && stats.cjkCount > 0 {
            return true
        }

        let weakTerms: Set<String> = [
            "世界", "概念", "知識", "方法", "系統", "理論", "設計", "工程", "模型"
        ]
        if weakTerms.contains(key) && stats.visibleCount <= 2 {
            return true
        }

        let titleTokens = metadataTokens(from: title)
        let weakCount = titleTokens.filter { titleNoiseTerms.contains($0) || weakTerms.contains($0) }.count
        return weakCount >= 1 && titleTokens.count <= 2
    }

    private static func isLikelyPublicationMetadata(title: String, content: String) -> Bool {
        let titleTokens = metadataTokens(from: title)
        let contentTokens = metadataTokens(from: content)
        let titleHits = titleTokens.filter(publicationMetadataTerms.contains).count
        let contentHits = contentTokens.filter(publicationMetadataTerms.contains).count
        let combinedText = (title + " " + content).lowercased()

        if titleHits >= 1 && titleTokens.count <= 3 {
            return true
        }

        if contentHits >= 3 {
            return true
        }

        if containsISBN(in: combinedText) {
            return true
        }

        if containsPageLikePattern(in: combinedText) && contentHits >= 2 {
            return true
        }

        if containsPublisherLine(in: content) {
            return true
        }

        return false
    }

    private static func metadataTokens(from text: String) -> [String] {
        normalizedText(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func containsISBN(in text: String) -> Bool {
        text.contains("isbn") || text.contains("issn") || text.contains("doi")
    }

    private static func containsPageLikePattern(in text: String) -> Bool {
        let patterns = [
            "p.", "pp.", "page", "頁", "頁碼", "chapter", "第1章", "第2章", "第3章"
        ]
        return patterns.contains { text.contains($0) }
    }

    private static func containsPublisherLine(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        return lines.contains { line in
            let lowered = line.lowercased()
            let hits = publicationMetadataTerms.filter { lowered.contains($0) }.count
            return hits >= 2
        }
    }

    private static func characterStats(for text: String) -> CharacterStats {
        let visibleScalars = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        let visibleCount = visibleScalars.count
        let digitCount = visibleScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let latinLetters = visibleScalars.filter { CharacterSet.letters.contains($0) && !isCJK($0) }
        let uppercaseLatinCount = latinLetters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        let lowercaseLatinCount = latinLetters.filter { CharacterSet.lowercaseLetters.contains($0) }.count
        let cjkCount = visibleScalars.filter(isCJK).count
        let letterLikeCount = latinLetters.count + cjkCount

        return CharacterStats(
            visibleCount: visibleCount,
            digitRatio: visibleCount == 0 ? 0 : Double(digitCount) / Double(visibleCount),
            letterLikeCount: letterLikeCount,
            cjkCount: cjkCount,
            isAllUppercaseLatin: uppercaseLatinCount > 0 && lowercaseLatinCount == 0 && cjkCount == 0
        )
    }

    nonisolated private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private struct CharacterStats {
        let visibleCount: Int
        let digitRatio: Double
        let letterLikeCount: Int
        let cjkCount: Int
        let isAllUppercaseLatin: Bool
    }

    private enum RejectionKey {
        case emptyTitle
        case emptyContent
        case duplicate
        case genericTitle
        case copyrightNoise
        case publicationMetadata
        case missingLetters
        case tooManyDigits
        case titleTooShort
        case contentTooShort
        case ocrNoise
        case notKnowledgeLike
    }

    private static func localizedRejection(_ key: RejectionKey, title: String? = nil) -> String {
        let suffix = title.map { "：\($0)" } ?? ""
        switch (RegionUIStore.runtimeRegion(), key) {
        case (.taiwan, .emptyTitle):
            return "標題是空的"
        case (.taiwan, .emptyContent):
            return "內容是空的"
        case (.taiwan, .duplicate):
            return "重複知識點\(suffix)"
        case (.taiwan, .genericTitle):
            return "標題過於空泛\(suffix)"
        case (.taiwan, .copyrightNoise):
            return "內容像是網址或版權雜訊\(suffix)"
        case (.taiwan, .publicationMetadata):
            return "內容像是書封或出版資訊\(suffix)"
        case (.taiwan, .missingLetters):
            return "標題缺少有效文字\(suffix)"
        case (.taiwan, .tooManyDigits):
            return "標題數字比例過高\(suffix)"
        case (.taiwan, .titleTooShort):
            return "標題太短\(suffix)"
        case (.taiwan, .contentTooShort):
            return "內容太短\(suffix)"
        case (.taiwan, .ocrNoise):
            return "標題像 OCR 雜訊\(suffix)"
        case (.taiwan, .notKnowledgeLike):
            return "標題不夠像知識點\(suffix)"

        case (.unitedStates, .emptyTitle):
            return "The title is empty."
        case (.unitedStates, .emptyContent):
            return "The content is empty."
        case (.unitedStates, .duplicate):
            return "Duplicate knowledge entry\(suffix)"
        case (.unitedStates, .genericTitle):
            return "The title is too generic\(suffix)"
        case (.unitedStates, .copyrightNoise):
            return "The content looks like a URL or copyright noise\(suffix)"
        case (.unitedStates, .publicationMetadata):
            return "The content looks like cover or publication metadata\(suffix)"
        case (.unitedStates, .missingLetters):
            return "The title is missing meaningful text\(suffix)"
        case (.unitedStates, .tooManyDigits):
            return "The title contains too many digits\(suffix)"
        case (.unitedStates, .titleTooShort):
            return "The title is too short\(suffix)"
        case (.unitedStates, .contentTooShort):
            return "The content is too short\(suffix)"
        case (.unitedStates, .ocrNoise):
            return "The title looks like OCR noise\(suffix)"
        case (.unitedStates, .notKnowledgeLike):
            return "The title does not look enough like a knowledge entry\(suffix)"

        case (.japan, .emptyTitle):
            return "タイトルが空です。"
        case (.japan, .emptyContent):
            return "内容が空です。"
        case (.japan, .duplicate):
            return "重複した知識点です\(suffix)"
        case (.japan, .genericTitle):
            return "タイトルが抽象的すぎます\(suffix)"
        case (.japan, .copyrightNoise):
            return "内容がURLや著作権ノイズに見えます\(suffix)"
        case (.japan, .publicationMetadata):
            return "内容が表紙や出版情報に見えます\(suffix)"
        case (.japan, .missingLetters):
            return "タイトルに有効な文字が不足しています\(suffix)"
        case (.japan, .tooManyDigits):
            return "タイトルの数字比率が高すぎます\(suffix)"
        case (.japan, .titleTooShort):
            return "タイトルが短すぎます\(suffix)"
        case (.japan, .contentTooShort):
            return "内容が短すぎます\(suffix)"
        case (.japan, .ocrNoise):
            return "タイトルがOCRノイズのようです\(suffix)"
        case (.japan, .notKnowledgeLike):
            return "タイトルが知識点らしくありません\(suffix)"
        }
    }
}

// MARK: - 參考資料模型
@Model
final class KnowledgeReference {
    // 🐛 修復：移除 @Attribute(.unique)，讓 SwiftData 順暢接管主鍵
    var id: UUID = UUID()
    var title: String = ""
    var typeRaw: String = ReferenceType.text.rawValue
    var payload: String = ""
    @Attribute(.externalStorage) var attachmentData: Data?
    var attachmentOriginalFileName: String?
    var attachmentMimeType: String?
    var summaryOutline: String?
    var summaryVerificationNote: String?
    var summaryLocalizationRaw: String?
    var summaryUpdatedAt: Date?
    var createdAt: Date = Date()
    
    var node: KnowledgeNode?

    init(
        title: String,
        type: ReferenceType,
        payload: String,
        attachmentData: Data? = nil,
        attachmentOriginalFileName: String? = nil,
        attachmentMimeType: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.typeRaw = type.rawValue
        self.payload = payload
        self.attachmentData = attachmentData
        self.attachmentOriginalFileName = attachmentOriginalFileName
        self.attachmentMimeType = attachmentMimeType
        self.summaryOutline = nil
        self.summaryVerificationNote = nil
        self.summaryLocalizationRaw = nil
        self.summaryUpdatedAt = nil
        self.createdAt = Date()
    }
    
    var type: ReferenceType {
        ReferenceType(rawValue: typeRaw) ?? .text
    }

    var attachmentLocalFileName: String? {
        switch type {
        case .image, .pdf, .audio:
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .web, .text:
            return nil
        }
    }

    var isFileAttachment: Bool {
        attachmentLocalFileName != nil
    }

    var attachmentDisplayFileName: String {
        let original = attachmentOriginalFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !original.isEmpty {
            return original
        }
        return attachmentLocalFileName ?? title
    }
}

// MARK: - 知識節點模型
@Model
final class KnowledgeNode {
    // 🐛 修復：移除 @Attribute(.unique)
    var id: UUID = UUID()
    var title: String = ""
    var content: String = ""
    var category: String = KnowledgeCategory.thinkingScience.rawValue
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0
    var createdAt: Date = Date()
    var libraryID: String?
    var libraryName: String?
    
    // 🐛 修復：移除 "= []"，不要給 Optional 陣列預設值，完美避開 SwiftData Crash
    @Relationship(deleteRule: .cascade, inverse: \KnowledgeReference.node)
    var references: [KnowledgeReference]?

    init(
        title: String,
        content: String,
        category: KnowledgeCategory,
        x: Double,
        y: Double,
        z: Double,
        libraryID: String? = nil,
        libraryName: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.category = category.rawValue
        self.x = x
        self.y = y
        self.z = z
        self.createdAt = Date()
        self.libraryID = libraryID
        self.libraryName = libraryName
    }
}

extension KnowledgeNode {
    var categoryEnum: KnowledgeCategory {
        KnowledgeCategory(rawValue: category) ?? .thinkingScience
    }
}
