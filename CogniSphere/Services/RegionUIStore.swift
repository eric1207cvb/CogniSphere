import Combine
import Foundation
import SwiftUI

enum SupportedRegionUI: String, CaseIterable, Identifiable {
    case taiwan
    case unitedStates
    case japan

    var id: String { rawValue }

    nonisolated static func detect(from locale: Locale = .autoupdatingCurrent) -> SupportedRegionUI {
        let regionCode: String
        if #available(iOS 16.0, *) {
            regionCode = locale.region?.identifier.uppercased() ?? ""
        } else {
            regionCode = (locale as NSLocale).object(forKey: .countryCode) as? String ?? ""
        }

        switch regionCode {
        case "TW":
            return .taiwan
        case "JP":
            return .japan
        default:
            return .unitedStates
        }
    }

    nonisolated var localeIdentifier: String {
        switch self {
        case .taiwan:
            return "zh_TW"
        case .unitedStates:
            return "en_US"
        case .japan:
            return "ja_JP"
        }
    }
}

struct RegionTheme {
    let canvas: Color
    let card: Color
    let cardSecondary: Color
    let accent: Color
    let accentSoft: Color
    let chipFill: Color
    let chipText: Color
    let outline: Color
}

struct RegionCopy {
    let appTitle: String
    let libraryTitle: String
    let addNodeTitle: String
    let importReviewTitle: String
    let currentWriting: String
    let archived: String
    let reviewing: String
    let archiveAction: String
    let archiveFooter: String
    let done: String
    let cancel: String
    let save: String
    let knowledgeNodeInfo: String
    let noteDetail: String
    let stageWithNode: String
    let sameEntry: String
    let noReferences: String
    let editLibraryTitle: String
    let editLibraryPlaceholder: String
    let editLibraryMessage: String
    let defaultActiveLibraryName: String
    let learningMaterialsSection: String
    let generalObjectsSection: String
    let recognizeStudyCamera: String
    let recognizeStudyLibrary: String
    let recognizeObjectCamera: String
    let recognizeObjectLibrary: String
    let exportAllKnowledge: String
    let exportKnowledgeNetwork: String
    let importResultTitle: String
    let loadingKnowledgeTitle: String
    let loadingKnowledgeSubtitle: String
    let graphRecentSubsetPrefix: String
    let newestAdded: String
    let newestBadge: String
    let formTitleLabel: String
    let formTitlePlaceholder: String
    let formCategoryLabel: String
    let formContentLabel: String
    let emptyTitleValidation: String
    let emptyContentValidation: String
    let noDirectCandidatesMessage: String
    let candidateEntriesTitle: String
    let aiSummarySection: String
    let webLinksSection: String
    let attachmentsSection: String
    let noWebLinks: String
    let noAttachments: String
    let importPDF: String
    let pickPhoto: String
    let takePhoto: String
    let addTextNote: String
    let addWebLink: String
    let voiceMemo30s: String
    let cameraUnavailableTitle: String
    let cameraUnavailableMessage: String
    let attachmentResultTitle: String
    let ok: String
    let editKnowledgeNode: String
    let createFromSummary: String
    let addKnowledgeNode: String
    let close: String
    let notFoundImage: String
    let notFoundPDF: String
    let cannotPreviewLink: String
    let addLinkTitle: String
    let addLinkHint: String
    let addLinkButton: String
    let alreadyAdded: String
    let noLinksYet: String
    let invalidLinkTitle: String
    let invalidLinkMessage: String
    let keyboardDismiss: String
    let addNoteTitle: String
    let autoTimestampHint: String
    let noNotesYet: String
    let invalidNoteTitle: String
    let invalidNoteMessage: String
    let linkDefaultTitle: String
    let imageOCRAction: String
    let imageOCRRefresh: String
    let pdfSummaryAction: String
    let pdfSummaryRefresh: String
    let convertToKnowledgeNode: String
    let previewOCRSummary: String
    let previewPDFSummary: String
    let previewSummary: String
    let ocrSummaryLabel: String
    let pdfSummaryLabel: String
    let genericSummaryLabel: String
    let localAudioFile: String
    let localFileSaved: String
    let audioPlaying: String
    let imageMissingForOCR: String
    let imageOCRRejected: String
    let pdfMissingForSummary: String
    let pdfSummaryUnavailable: String
    let summaryUpdated: String
    let summaryUpdateFailed: String
    let createdFromSummary: String
    let createdFromSummarySwitched: String
    let createKnowledgeNodeFailed: String
    let deleteAttachmentFailed: String
    let deleteLinkFailed: String

    func nodeCountText(_ count: Int) -> String {
        switch appTitle {
        case "CogniSphere US":
            return "\(count) knowledge entries"
        case "CogniSphere JP":
            return "知識項目 \(count) 件"
        default:
            return "\(count) 個知識點"
        }
    }

    func archiveSummary(count: Int, archivedAt: String) -> String {
        switch appTitle {
        case "CogniSphere US":
            return "\(count) entries • archived \(archivedAt)"
        case "CogniSphere JP":
            return "知識項目 \(count) 件 ・ \(archivedAt) に保存"
        default:
            return "\(count) 個知識點 ・ 封存於 \(archivedAt)"
        }
    }

    func createdSummary(count: Int, createdAt: String) -> String {
        switch appTitle {
        case "CogniSphere US":
            return "\(count) entries • created \(createdAt)"
        case "CogniSphere JP":
            return "知識項目 \(count) 件 ・ \(createdAt) に作成"
        default:
            return "\(count) 個知識點 ・ 建立於 \(createdAt)"
        }
    }

    func archivedLibraryName(dateText: String) -> String {
        switch appTitle {
        case "CogniSphere US":
            return "Knowledge Network \(dateText)"
        case "CogniSphere JP":
            return "知識ネットワーク \(dateText)"
        default:
            return "知識網絡 \(dateText)"
        }
    }

    func graphSubsetNotice(shown: Int, total: Int) -> String {
        switch appTitle {
        case "CogniSphere US":
            return "Showing the latest \(shown) of \(total) entries for speed"
        case "CogniSphere JP":
            return "速度優先のため最新 \(shown) / \(total) 件のみ表示しています"
        default:
            return "圖譜為了速度只顯示最近 \(shown) / \(total) 筆"
        }
    }
}

@MainActor
final class RegionUIStore: ObservableObject {
    private nonisolated static let regionOverrideKey = "RegionUIStore.regionOverride"

    @Published private(set) var region: SupportedRegionUI
    @Published private(set) var usesAutomaticRegion: Bool

    private var cancellables = Set<AnyCancellable>()

    init(locale: Locale = .autoupdatingCurrent) {
        let overrideRegion = Self.storedRegionOverride()
        self.region = overrideRegion ?? SupportedRegionUI.detect(from: locale)
        self.usesAutomaticRegion = overrideRegion == nil

        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshFromSystemLocale()
            }
            .store(in: &cancellables)
    }

    var theme: RegionTheme {
        Self.theme(for: region)
    }

    var copy: RegionCopy {
        Self.copy(for: region)
    }

    var locale: Locale {
        Self.locale(for: region)
    }

    func setRegionOverride(_ overrideRegion: SupportedRegionUI?) {
        if let overrideRegion {
            UserDefaults.standard.set(overrideRegion.rawValue, forKey: Self.regionOverrideKey)
            region = overrideRegion
            usesAutomaticRegion = false
        } else {
            UserDefaults.standard.removeObject(forKey: Self.regionOverrideKey)
            region = SupportedRegionUI.detect()
            usesAutomaticRegion = true
        }
    }

    private func refreshFromSystemLocale() {
        guard usesAutomaticRegion else { return }
        region = SupportedRegionUI.detect()
    }

    nonisolated static func theme(for region: SupportedRegionUI) -> RegionTheme {
        switch region {
        case .taiwan:
            return RegionTheme(
                canvas: Color(red: 0.96, green: 0.97, blue: 0.95),
                card: Color(red: 0.99, green: 0.99, blue: 0.97),
                cardSecondary: Color(red: 0.93, green: 0.96, blue: 0.93),
                accent: Color(red: 0.10, green: 0.47, blue: 0.34),
                accentSoft: Color(red: 0.79, green: 0.90, blue: 0.82),
                chipFill: Color(red: 0.89, green: 0.95, blue: 0.90),
                chipText: Color(red: 0.08, green: 0.41, blue: 0.29),
                outline: Color(red: 0.76, green: 0.86, blue: 0.78)
            )
        case .unitedStates:
            return RegionTheme(
                canvas: Color(red: 0.95, green: 0.96, blue: 0.98),
                card: Color.white,
                cardSecondary: Color(red: 0.92, green: 0.95, blue: 0.99),
                accent: Color(red: 0.08, green: 0.25, blue: 0.52),
                accentSoft: Color(red: 0.79, green: 0.86, blue: 0.97),
                chipFill: Color(red: 0.88, green: 0.92, blue: 0.98),
                chipText: Color(red: 0.08, green: 0.23, blue: 0.48),
                outline: Color(red: 0.78, green: 0.84, blue: 0.93)
            )
        case .japan:
            return RegionTheme(
                canvas: Color(red: 0.98, green: 0.96, blue: 0.94),
                card: Color(red: 1.0, green: 0.99, blue: 0.98),
                cardSecondary: Color(red: 0.97, green: 0.93, blue: 0.90),
                accent: Color(red: 0.67, green: 0.19, blue: 0.15),
                accentSoft: Color(red: 0.95, green: 0.84, blue: 0.80),
                chipFill: Color(red: 0.98, green: 0.90, blue: 0.87),
                chipText: Color(red: 0.54, green: 0.16, blue: 0.13),
                outline: Color(red: 0.89, green: 0.80, blue: 0.76)
            )
        }
    }

    nonisolated static func copy(for region: SupportedRegionUI) -> RegionCopy {
        switch region {
        case .taiwan:
            return RegionCopy(
                appTitle: "CogniSphere",
                libraryTitle: "知識網絡",
                addNodeTitle: "新增知識",
                importReviewTitle: "登入知識項目",
                currentWriting: "目前寫入",
                archived: "封存",
                reviewing: "複習",
                archiveAction: "封存目前知識網絡並開新庫",
                archiveFooter: "封存後，現有知識點會留在舊知識網絡供複習；之後新增的知識點會寫入全新的目前知識庫。",
                done: "完成",
                cancel: "取消",
                save: "儲存",
                knowledgeNodeInfo: "知識節點資訊",
                noteDetail: "詳細筆記內容",
                stageWithNode: "建立時先加入",
                sameEntry: "與節點詳情同一套入口",
                noReferences: "目前還沒有附加參考資料",
                editLibraryTitle: "編輯知識網絡名稱",
                editLibraryPlaceholder: "輸入名稱",
                editLibraryMessage: "封存知識網絡可重新命名，方便之後複習。",
                defaultActiveLibraryName: "目前知識庫",
                learningMaterialsSection: "智慧辨識",
                generalObjectsSection: "智慧辨識",
                recognizeStudyCamera: "拍照智慧辨識",
                recognizeStudyLibrary: "從相簿智慧辨識",
                recognizeObjectCamera: "拍照智慧辨識",
                recognizeObjectLibrary: "從相簿智慧辨識",
                exportAllKnowledge: "匯出全部知識點",
                exportKnowledgeNetwork: "匯出這個知識網絡",
                importResultTitle: "匯入結果",
                loadingKnowledgeTitle: "AI 正在提取知識",
                loadingKnowledgeSubtitle: "分析畫面結構、主題與可登入條目",
                graphRecentSubsetPrefix: "圖譜為了速度只顯示最近",
                newestAdded: "最新加入",
                newestBadge: "最新",
                formTitleLabel: "標題",
                formTitlePlaceholder: "輸入知識標題",
                formCategoryLabel: "門類",
                formContentLabel: "內容",
                emptyTitleValidation: "標題不能是空的。",
                emptyContentValidation: "內容不能是空的。",
                noDirectCandidatesMessage: "這次沒有可直接加入的知識點。你可以改用 OCR / 摘要結果先建立草稿，再自行修改後加入。",
                candidateEntriesTitle: "候選知識項目",
                aiSummarySection: "AI 知識摘要",
                webLinksSection: "網頁連結",
                attachmentsSection: "附加參考資源",
                noWebLinks: "尚未新增任何網頁連結",
                noAttachments: "尚未新增任何參考資源",
                importPDF: "匯入 PDF",
                pickPhoto: "從相簿選圖",
                takePhoto: "拍照",
                addTextNote: "新增文字筆記",
                addWebLink: "新增網頁連結",
                voiceMemo30s: "30秒語音備忘錄",
                cameraUnavailableTitle: "無法開啟相機",
                cameraUnavailableMessage: "目前裝置沒有可用的相機，因此不會改成開啟相簿。",
                attachmentResultTitle: "附件處理結果",
                ok: "好",
                editKnowledgeNode: "編輯知識節點",
                createFromSummary: "從摘要建立知識點",
                addKnowledgeNode: "加入知識點",
                close: "關閉",
                notFoundImage: "找不到圖片",
                notFoundPDF: "找不到 PDF",
                cannotPreviewLink: "無法預覽這個連結",
                addLinkTitle: "新增網頁連結",
                addLinkHint: "不用填標題，系統會自動用網域當名稱。",
                addLinkButton: "加入連結",
                alreadyAdded: "目前已加入",
                noLinksYet: "目前還沒有網頁連結",
                invalidLinkTitle: "無法加入連結",
                invalidLinkMessage: "有些網址格式不正確，請檢查後再試一次。",
                keyboardDismiss: "收合",
                addNoteTitle: "新增文字筆記",
                autoTimestampHint: "標題會自動使用時間戳記，你只需要寫內容。",
                noNotesYet: "目前還沒有文字筆記",
                invalidNoteTitle: "無法加入筆記",
                invalidNoteMessage: "請先輸入筆記內容。",
                linkDefaultTitle: "網頁連結",
                imageOCRAction: "OCR",
                imageOCRRefresh: "更新 OCR",
                pdfSummaryAction: "摘要",
                pdfSummaryRefresh: "更新摘要",
                convertToKnowledgeNode: "轉成知識點",
                previewOCRSummary: "查看 OCR 摘要",
                previewPDFSummary: "查看 PDF 摘要",
                previewSummary: "查看摘要",
                ocrSummaryLabel: "OCR 摘要大綱",
                pdfSummaryLabel: "PDF 摘要大綱",
                genericSummaryLabel: "摘要大綱",
                localAudioFile: "本機語音檔",
                localFileSaved: "本機檔案已儲存",
                audioPlaying: "播放中...",
                imageMissingForOCR: "找不到這張圖片，無法進行 OCR。",
                imageOCRRejected: "這張圖片沒有可用的 OCR 內容，或內容被判定為雜訊。",
                pdfMissingForSummary: "找不到這份 PDF，無法生成摘要。",
                pdfSummaryUnavailable: "這份 PDF 目前沒有產生摘要。",
                summaryUpdated: "已更新這份參考資料的摘要大綱。",
                summaryUpdateFailed: "摘要更新失敗，請再試一次。",
                createdFromSummary: "已從摘要建立新的知識點。",
                createdFromSummarySwitched: "已從摘要建立新的知識點，並切回目前知識庫。",
                createKnowledgeNodeFailed: "建立知識點失敗，請再試一次。",
                deleteAttachmentFailed: "刪除附件失敗，請再試一次。",
                deleteLinkFailed: "刪除連結失敗，請再試一次。"
            )
        case .unitedStates:
            return RegionCopy(
                appTitle: "CogniSphere US",
                libraryTitle: "Knowledge Network",
                addNodeTitle: "New Entry",
                importReviewTitle: "Review Import",
                currentWriting: "Active",
                archived: "Archived",
                reviewing: "Review",
                archiveAction: "Archive Current Network and Start New",
                archiveFooter: "Archived entries stay in the previous knowledge network for review. New entries go into a fresh active library.",
                done: "Done",
                cancel: "Cancel",
                save: "Save",
                knowledgeNodeInfo: "Knowledge Entry",
                noteDetail: "Detailed Notes",
                stageWithNode: "Attach While Creating",
                sameEntry: "Same entry points as detail view",
                noReferences: "No references attached yet",
                editLibraryTitle: "Rename Knowledge Network",
                editLibraryPlaceholder: "Enter name",
                editLibraryMessage: "Archived knowledge networks can be renamed for easier review.",
                defaultActiveLibraryName: "Active Library",
                learningMaterialsSection: "Smart Scan",
                generalObjectsSection: "Smart Scan",
                recognizeStudyCamera: "Scan with Camera",
                recognizeStudyLibrary: "Scan from Photos",
                recognizeObjectCamera: "Scan with Camera",
                recognizeObjectLibrary: "Scan from Photos",
                exportAllKnowledge: "Export All Entries",
                exportKnowledgeNetwork: "Export This Knowledge Network",
                importResultTitle: "Import Result",
                loadingKnowledgeTitle: "AI is extracting knowledge",
                loadingKnowledgeSubtitle: "Analyzing structure, topics, and importable entries",
                graphRecentSubsetPrefix: "Showing latest entries for speed",
                newestAdded: "Recently Added",
                newestBadge: "NEW",
                formTitleLabel: "Title",
                formTitlePlaceholder: "Enter a knowledge title",
                formCategoryLabel: "Category",
                formContentLabel: "Content",
                emptyTitleValidation: "Title cannot be empty.",
                emptyContentValidation: "Content cannot be empty.",
                noDirectCandidatesMessage: "No entries can be added directly from this result. You can create a draft from OCR or the summary, then revise it before adding.",
                candidateEntriesTitle: "Candidate Entries",
                aiSummarySection: "AI Summary",
                webLinksSection: "Web Links",
                attachmentsSection: "Attachments",
                noWebLinks: "No web links yet",
                noAttachments: "No attachments yet",
                importPDF: "Import PDF",
                pickPhoto: "Choose from Photos",
                takePhoto: "Take Photo",
                addTextNote: "Add Text Note",
                addWebLink: "Add Web Link",
                voiceMemo30s: "30s Voice Memo",
                cameraUnavailableTitle: "Camera Unavailable",
                cameraUnavailableMessage: "No usable camera is available on this device.",
                attachmentResultTitle: "Attachment Result",
                ok: "OK",
                editKnowledgeNode: "Edit Knowledge Entry",
                createFromSummary: "Create from Summary",
                addKnowledgeNode: "Add Entry",
                close: "Close",
                notFoundImage: "Image Not Found",
                notFoundPDF: "PDF Not Found",
                cannotPreviewLink: "Cannot preview this link",
                addLinkTitle: "Add Web Link",
                addLinkHint: "No title needed. The domain will be used automatically.",
                addLinkButton: "Add Link",
                alreadyAdded: "Already Added",
                noLinksYet: "No web links yet",
                invalidLinkTitle: "Cannot Add Link",
                invalidLinkMessage: "Some URLs are invalid. Please review and try again.",
                keyboardDismiss: "Hide",
                addNoteTitle: "Add Note",
                autoTimestampHint: "The title uses a timestamp automatically. You only need to write the note.",
                noNotesYet: "No text notes yet",
                invalidNoteTitle: "Cannot Add Note",
                invalidNoteMessage: "Please enter note content first.",
                linkDefaultTitle: "Web Link",
                imageOCRAction: "OCR",
                imageOCRRefresh: "Refresh OCR",
                pdfSummaryAction: "Summarize",
                pdfSummaryRefresh: "Refresh Summary",
                convertToKnowledgeNode: "Make Entry",
                previewOCRSummary: "View OCR Summary",
                previewPDFSummary: "View PDF Summary",
                previewSummary: "View Summary",
                ocrSummaryLabel: "OCR Summary",
                pdfSummaryLabel: "PDF Summary",
                genericSummaryLabel: "Summary",
                localAudioFile: "Stored audio file",
                localFileSaved: "Stored locally",
                audioPlaying: "Playing...",
                imageMissingForOCR: "This image could not be found for OCR.",
                imageOCRRejected: "No usable OCR content was found in this image, or it was filtered as noise.",
                pdfMissingForSummary: "This PDF could not be found for summarization.",
                pdfSummaryUnavailable: "No summary is currently available for this PDF.",
                summaryUpdated: "The summary for this reference has been updated.",
                summaryUpdateFailed: "Failed to update summary. Please try again.",
                createdFromSummary: "A new knowledge entry was created from the summary.",
                createdFromSummarySwitched: "A new knowledge entry was created from the summary, and the active library was restored.",
                createKnowledgeNodeFailed: "Failed to create the knowledge entry. Please try again.",
                deleteAttachmentFailed: "Failed to delete attachment. Please try again.",
                deleteLinkFailed: "Failed to delete link. Please try again."
            )
        case .japan:
            return RegionCopy(
                appTitle: "CogniSphere JP",
                libraryTitle: "知識ネットワーク",
                addNodeTitle: "知識を追加",
                importReviewTitle: "知識項目を追加",
                currentWriting: "現在書き込み中",
                archived: "保存済み",
                reviewing: "復習",
                archiveAction: "現在の知識ネットワークを保存して新規作成",
                archiveFooter: "保存後は既存の知識点を復習用に残し、新しい知識点は新規ライブラリへ追加されます。",
                done: "完了",
                cancel: "キャンセル",
                save: "保存",
                knowledgeNodeInfo: "知識ノード情報",
                noteDetail: "詳細メモ",
                stageWithNode: "作成時に追加",
                sameEntry: "詳細画面と同じ入口",
                noReferences: "参考資料はまだありません",
                editLibraryTitle: "知識ネットワーク名を編集",
                editLibraryPlaceholder: "名前を入力",
                editLibraryMessage: "保存した知識ネットワークは後から名前を変えて復習しやすくできます。",
                defaultActiveLibraryName: "現在の知識ライブラリ",
                learningMaterialsSection: "スマート認識",
                generalObjectsSection: "スマート認識",
                recognizeStudyCamera: "撮影してスマート認識",
                recognizeStudyLibrary: "写真からスマート認識",
                recognizeObjectCamera: "撮影してスマート認識",
                recognizeObjectLibrary: "写真からスマート認識",
                exportAllKnowledge: "すべての知識点を書き出す",
                exportKnowledgeNetwork: "この知識ネットワークを書き出す",
                importResultTitle: "取り込み結果",
                loadingKnowledgeTitle: "AIが知識を抽出しています",
                loadingKnowledgeSubtitle: "画面構造、主題、取り込み可能な項目を分析しています",
                graphRecentSubsetPrefix: "速度優先で最新項目のみ表示",
                newestAdded: "最新追加",
                newestBadge: "最新",
                formTitleLabel: "タイトル",
                formTitlePlaceholder: "知識タイトルを入力",
                formCategoryLabel: "分類",
                formContentLabel: "内容",
                emptyTitleValidation: "タイトルは空にできません。",
                emptyContentValidation: "内容は空にできません。",
                noDirectCandidatesMessage: "この結果から直接追加できる知識点はありません。OCR や要約から下書きを作成し、編集してから追加できます。",
                candidateEntriesTitle: "候補知識項目",
                aiSummarySection: "AI 要約",
                webLinksSection: "Webリンク",
                attachmentsSection: "参考資料",
                noWebLinks: "Webリンクはまだありません",
                noAttachments: "参考資料はまだありません",
                importPDF: "PDFを読み込む",
                pickPhoto: "写真ライブラリから選ぶ",
                takePhoto: "撮影",
                addTextNote: "テキストメモを追加",
                addWebLink: "Webリンクを追加",
                voiceMemo30s: "30秒音声メモ",
                cameraUnavailableTitle: "カメラを開けません",
                cameraUnavailableMessage: "この端末では利用できるカメラがありません。",
                attachmentResultTitle: "添付処理結果",
                ok: "OK",
                editKnowledgeNode: "知識ノードを編集",
                createFromSummary: "要約から知識点を作成",
                addKnowledgeNode: "知識点を追加",
                close: "閉じる",
                notFoundImage: "画像が見つかりません",
                notFoundPDF: "PDFが見つかりません",
                cannotPreviewLink: "このリンクはプレビューできません",
                addLinkTitle: "Webリンクを追加",
                addLinkHint: "タイトルは不要です。ドメイン名が自動で使われます。",
                addLinkButton: "リンクを追加",
                alreadyAdded: "追加済み",
                noLinksYet: "Webリンクはまだありません",
                invalidLinkTitle: "リンクを追加できません",
                invalidLinkMessage: "URL形式が正しくない項目があります。確認してもう一度お試しください。",
                keyboardDismiss: "閉じる",
                addNoteTitle: "テキストメモを追加",
                autoTimestampHint: "タイトルには自動でタイムスタンプが入ります。内容だけ入力してください。",
                noNotesYet: "テキストメモはまだありません",
                invalidNoteTitle: "メモを追加できません",
                invalidNoteMessage: "先にメモ内容を入力してください。",
                linkDefaultTitle: "Webリンク",
                imageOCRAction: "OCR",
                imageOCRRefresh: "OCR更新",
                pdfSummaryAction: "要約",
                pdfSummaryRefresh: "要約更新",
                convertToKnowledgeNode: "知識点にする",
                previewOCRSummary: "OCR要約を見る",
                previewPDFSummary: "PDF要約を見る",
                previewSummary: "要約を見る",
                ocrSummaryLabel: "OCR要約",
                pdfSummaryLabel: "PDF要約",
                genericSummaryLabel: "要約",
                localAudioFile: "端末内の音声ファイル",
                localFileSaved: "端末内に保存済み",
                audioPlaying: "再生中...",
                imageMissingForOCR: "OCRに使う画像が見つかりません。",
                imageOCRRejected: "この画像から使えるOCR内容を取得できないか、ノイズとして除外されました。",
                pdfMissingForSummary: "要約するPDFが見つかりません。",
                pdfSummaryUnavailable: "このPDFの要約はまだ生成されていません。",
                summaryUpdated: "この参考資料の要約を更新しました。",
                summaryUpdateFailed: "要約の更新に失敗しました。もう一度お試しください。",
                createdFromSummary: "要約から新しい知識点を作成しました。",
                createdFromSummarySwitched: "要約から新しい知識点を作成し、現在のライブラリへ戻しました。",
                createKnowledgeNodeFailed: "知識点の作成に失敗しました。もう一度お試しください。",
                deleteAttachmentFailed: "添付の削除に失敗しました。もう一度お試しください。",
                deleteLinkFailed: "リンクの削除に失敗しました。もう一度お試しください。"
            )
        }
    }

    nonisolated static func locale(for region: SupportedRegionUI) -> Locale {
        Locale(identifier: region.localeIdentifier)
    }

    nonisolated static func storedRegionOverride() -> SupportedRegionUI? {
        guard let rawValue = UserDefaults.standard.string(forKey: regionOverrideKey) else {
            return nil
        }
        return SupportedRegionUI(rawValue: rawValue)
    }

    nonisolated static func runtimeRegion() -> SupportedRegionUI {
        storedRegionOverride() ?? SupportedRegionUI.detect()
    }

    nonisolated static func runtimeCopy() -> RegionCopy {
        copy(for: runtimeRegion())
    }

    nonisolated static func runtimeLocale() -> Locale {
        locale(for: runtimeRegion())
    }
}
