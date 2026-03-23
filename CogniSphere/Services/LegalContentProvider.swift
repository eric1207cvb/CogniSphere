import Foundation

enum LegalDocumentKind: String, CaseIterable, Identifiable {
    case eula
    case privacy
    case aiUsage

    var id: String { rawValue }

    func title(for region: SupportedRegionUI) -> String {
        switch (self, region) {
        case (.eula, .taiwan):
            return "EULA"
        case (.eula, .unitedStates):
            return "EULA"
        case (.eula, .japan):
            return "EULA"
        case (.privacy, .taiwan):
            return "隱私權政策"
        case (.privacy, .unitedStates):
            return "Privacy Policy"
        case (.privacy, .japan):
            return "プライバシーポリシー"
        case (.aiUsage, .taiwan):
            return "AI 使用說明"
        case (.aiUsage, .unitedStates):
            return "AI Use Notice"
        case (.aiUsage, .japan):
            return "AI利用ガイド"
        }
    }

    func shortTitle(for region: SupportedRegionUI) -> String {
        switch (self, region) {
        case (.eula, _):
            return "EULA"
        case (.privacy, .taiwan):
            return "隱私"
        case (.privacy, .unitedStates):
            return "Privacy"
        case (.privacy, .japan):
            return "プライバシー"
        case (.aiUsage, .taiwan):
            return "AI"
        case (.aiUsage, .unitedStates):
            return "AI"
        case (.aiUsage, .japan):
            return "AI"
        }
    }

    var iconName: String {
        switch self {
        case .eula:
            return "doc.text"
        case .privacy:
            return "lock.shield"
        case .aiUsage:
            return "sparkles.rectangle.stack"
        }
    }
}

struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

struct LegalExternalLink: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

struct LegalDocumentContent {
    let title: String
    let summary: String
    let sections: [LegalSection]
    let links: [LegalExternalLink]
    let footerNote: String
}

enum LegalContentProvider {
    static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let openAIPrivacyURL = URL(string: "https://openai.com/policies/privacy-policy/")!
    static let openAITermsURL = URL(string: "https://openai.com/policies/terms-of-use/")!

    private static func localizedAppleEULATitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "Apple 標準 EULA"
        case .unitedStates:
            return "Apple Standard EULA"
        case .japan:
            return "Apple 標準 EULA"
        }
    }

    private static func localizedOpenAIPrivacyTitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "OpenAI 隱私權政策"
        case .unitedStates:
            return "OpenAI Privacy Policy"
        case .japan:
            return "OpenAI プライバシーポリシー"
        }
    }

    private static func localizedOpenAITermsTitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "OpenAI 使用條款"
        case .unitedStates:
            return "OpenAI Terms of Use"
        case .japan:
            return "OpenAI 利用規約"
        }
    }

    static func content(for kind: LegalDocumentKind, region: SupportedRegionUI) -> LegalDocumentContent {
        switch (kind, region) {
        case (.eula, .taiwan):
            return LegalDocumentContent(
                title: "終端使用者授權條款",
                summary: "本 app 依 Apple App Store 授權模式提供，而非出售。除本頁補充條款外，亦適用 Apple 標準 EULA。",
                sections: [
                    LegalSection(
                        title: "授權範圍",
                        body: "你可在自己擁有或控制的 Apple 裝置上使用 CogniSphere，並依 App Store 使用規則安裝與執行。本 app、介面、模型設定與內容結構均受著作權與相關法規保護。未經允許，你不得反向工程、再散布、轉售、出租、或以未授權方式提供本 app。"
                    ),
                    LegalSection(
                        title: "使用者內容與責任",
                        body: "你需對自己建立、匯入、OCR 擷取、上傳或同步的內容負責，並確認你有權處理相關文字、圖片、PDF、音訊與連結。你不得利用本 app 處理違法、侵權、騷擾、誹謗、個資濫用或其他不當內容。"
                    ),
                    LegalSection(
                        title: "AI 與外部服務",
                        body: "本 app 的部分功能會連接外部服務，包括 Apple 提供的系統能力、CloudKit 同步、網站預覽，以及由應用提供者設定的遠端 AI 服務。這些外部服務可能暫時中斷、內容不完整，或因地區、帳號、網路與第三方政策而不可用。"
                    ),
                    LegalSection(
                        title: "訂閱與付費功能",
                        body: "若你購買訂閱，交易、續訂、退款與取消均由 Apple App Store 處理。未訂閱時，AI / OCR 功能可能僅提供有限額度；訂閱後可依方案解鎖更高或無限制的使用權限。價格、期間與方案內容以 App Store 顯示為準。"
                    ),
                    LegalSection(
                        title: "免責與責任限制",
                        body: "本 app 與 AI / OCR 結果按現況提供，不保證永不中斷、完全正確、或適合任何特定用途。對於資料遺失、推論錯誤、學習判斷失準、第三方服務中斷或衍生損害，於適用法律允許範圍內，本 app 提供者僅在法律要求範圍內承擔責任。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedAppleEULATitle(for: .taiwan), url: appleStandardEULAURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .taiwan), url: openAITermsURL)
                ],
                footerNote: "本頁為 App 內摘要與補充說明，若與 Apple Standard EULA 或強制法律規定衝突，以適用法與 Apple 標準 EULA 為準。"
            )
        case (.eula, .unitedStates):
            return LegalDocumentContent(
                title: "End User License Agreement",
                summary: "This app is licensed, not sold. Apple’s Standard EULA applies together with the supplemental terms below.",
                sections: [
                    LegalSection(
                        title: "License Scope",
                        body: "You may use CogniSphere on Apple-branded devices you own or control, subject to the App Store Usage Rules. The app, interface, information architecture, and related materials are protected by applicable intellectual property laws. You may not reverse engineer, redistribute, resell, lease, or provide unauthorized access to the app."
                    ),
                    LegalSection(
                        title: "User Content and Responsibility",
                        body: "You are responsible for the notes, images, PDFs, audio, OCR results, links, and other materials you create, upload, sync, or process through the app. You must have the rights and permissions needed to handle that content, and you may not use the app for unlawful, infringing, abusive, defamatory, or otherwise harmful purposes."
                    ),
                    LegalSection(
                        title: "AI and External Services",
                        body: "Some features rely on external services, including Apple system services, CloudKit sync, website preview, and remote AI services configured by the app provider. These services may be unavailable, incomplete, rate-limited, or restricted by geography, connectivity, account status, or third-party policies."
                    ),
                    LegalSection(
                        title: "Subscriptions and Paid Features",
                        body: "If you purchase a subscription, billing, renewal, cancellation, and refunds are handled through the App Store. Non-subscribers may receive limited AI / OCR usage. Subscribers may receive expanded or unlimited access according to the plan shown in the App Store listing and purchase flow."
                    ),
                    LegalSection(
                        title: "Disclaimers and Liability Limits",
                        body: "The app and its AI / OCR outputs are provided on an “as is” and “as available” basis. We do not guarantee uninterrupted availability, error-free operation, or perfectly accurate results. To the maximum extent permitted by law, the app provider is not liable for indirect, incidental, consequential, or special damages arising from your use of the app or connected services."
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedAppleEULATitle(for: .unitedStates), url: appleStandardEULAURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .unitedStates), url: openAITermsURL)
                ],
                footerNote: "This screen is a product-facing summary and supplement. If any term conflicts with mandatory law or Apple’s Standard EULA, the controlling law and the Standard EULA govern."
            )
        case (.eula, .japan):
            return LegalDocumentContent(
                title: "エンドユーザー使用許諾契約",
                summary: "本アプリは販売ではなくライセンス提供です。本ページの補足条項に加え、Apple Standard EULA が適用されます。",
                sections: [
                    LegalSection(
                        title: "ライセンス範囲",
                        body: "CogniSphere は、App Store の利用規則に従い、あなたが所有または管理する Apple 製デバイス上で利用できます。本アプリ、UI、情報構造、および関連資料は知的財産法により保護されています。無断での逆コンパイル、再配布、再販売、貸与、共有提供はできません。"
                    ),
                    LegalSection(
                        title: "ユーザーコンテンツと責任",
                        body: "あなたは、アプリ上で作成・取り込み・同期・OCR処理するメモ、画像、PDF、音声、リンク等の内容に責任を負います。対象コンテンツを扱うための権利や許諾を自ら確保し、違法、権利侵害、嫌がらせ、中傷、個人情報濫用などの目的で利用してはなりません。"
                    ),
                    LegalSection(
                        title: "AI と外部サービス",
                        body: "本アプリの一部機能は、Apple のシステムサービス、CloudKit 同期、Web プレビュー、アプリ提供者が設定する遠隔 AI サービスなどの外部サービスを利用します。これらは地域、通信環境、第三者ポリシー、アカウント状態などにより利用不可または不完全となる場合があります。"
                    ),
                    LegalSection(
                        title: "サブスクリプションと有料機能",
                        body: "サブスクリプションの課金、更新、解約、返金は App Store を通じて行われます。未購読ユーザーには AI / OCR の利用回数制限が適用される場合があります。購読ユーザーには、購入画面に表示された内容に応じて拡張または無制限の利用権が提供されます。"
                    ),
                    LegalSection(
                        title: "免責および責任制限",
                        body: "本アプリおよび AI / OCR の出力は現状有姿で提供されます。継続的な利用可能性、完全な正確性、または特定目的への適合性は保証されません。適用法が認める最大限の範囲で、アプリ提供者は本アプリまたは外部サービスの利用から生じる間接的・付随的・特別な損害について責任を負いません。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedAppleEULATitle(for: .japan), url: appleStandardEULAURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .japan), url: openAITermsURL)
                ],
                footerNote: "本ページはアプリ内向けの要約と補足です。Apple Standard EULA または強行法規と抵触する場合は、それらが優先します。"
            )
        case (.privacy, .taiwan):
            return LegalDocumentContent(
                title: "隱私權政策",
                summary: "CogniSphere 會在裝置端保存知識內容，並在你主動使用 AI / OCR / 同步功能時處理必要資料。",
                sections: [
                    LegalSection(
                        title: "我們收集的資料",
                        body: "本 app 會保存你建立的知識條目、知識網絡名稱、分類、文字內容、網站連結、附件索引、訂閱狀態快取與必要的本機診斷資訊。附件實體檔案目前主要儲存在你的裝置沙盒中。"
                    ),
                    LegalSection(
                        title: "何時會傳送到外部服務",
                        body: "當你主動使用智慧辨識、圖片 OCR、PDF 摘要、網站預覽或雲端同步時，相關內容可能被傳送到外部服務。例如文字、OCR 結果、影像縮圖、裁切後圖片、PDF 擷取文字、雲端同步紀錄，以及訂閱驗證所需資料。"
                    ),
                    LegalSection(
                        title: "AI 與 OpenAI 相關處理",
                        body: "本 app 的部分 AI 功能由應用提供者設定的遠端 AI 服務處理，該服務可能使用 OpenAI 模型或 OpenAI 相容能力分析你提交的文字、圖片與 PDF 內容。你應避免在未必要時提交敏感個資、醫療、金融、法律或其他高度機密資訊。"
                    ),
                    LegalSection(
                        title: "同步與第三方服務",
                        body: "知識點、知識網絡清單與你主動加入的附件檔案可透過 Apple CloudKit / iCloud 同步到同一 Apple ID 的其他裝置。Apple、RevenueCat、以及 AI 服務供應方可能依其角色處理必要資料。同步速度、可用性與最終狀態仍會受網路、帳號與 Apple 雲端服務狀態影響。"
                    ),
                    LegalSection(
                        title: "使用、保存與控制",
                        body: "我們使用資料來提供知識整理、OCR、摘要、同步、訂閱驗證、錯誤排查與產品改善。你可透過刪除知識點、附件或刪除 app 來移除大部分本機資料；若資料已同步到 iCloud，其刪除可能需要一段時間傳播。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .taiwan), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedAppleEULATitle(for: .taiwan), url: appleStandardEULAURL)
                ],
                footerNote: "若你要在商業、研究或教育場景使用本 app，建議先確認自己對教材、圖片與文件具備合法處理權限。"
            )
        case (.privacy, .unitedStates):
            return LegalDocumentContent(
                title: "Privacy Policy",
                summary: "CogniSphere stores most knowledge content on your device and only uses external services when you invoke AI, OCR, sync, or related features.",
                sections: [
                    LegalSection(
                        title: "Data We Handle",
                        body: "The app stores your knowledge entries, network names, categories, notes, links, attachment metadata, attachment files, cached subscription state, and limited diagnostic information needed to operate the product. Attachment files are written to the app sandbox locally and may also be synced through iCloud when CloudKit sync is available."
                    ),
                    LegalSection(
                        title: "When Data Leaves the Device",
                        body: "If you use Smart Scan, image OCR, PDF summaries, website preview, cloud sync, or subscription validation, relevant data may be transmitted to external services. This can include text, OCR output, cropped images, resized photos, extracted PDF text, sync metadata, and purchase verification data."
                    ),
                    LegalSection(
                        title: "AI Processing and OpenAI-Related Services",
                        body: "Some AI features are processed by a remote AI service configured by the app provider. That service may use OpenAI models or OpenAI-compatible capabilities to analyze submitted text, images, and PDFs. You should avoid submitting highly sensitive personal, medical, legal, financial, or confidential information unless you have a clear need and authority to do so."
                    ),
                    LegalSection(
                        title: "Sync and Third Parties",
                        body: "Knowledge entries, knowledge network records, and attachment files may sync through Apple CloudKit / iCloud across devices using the same Apple ID. Apple, RevenueCat, and AI service providers may process limited information as needed for sync, subscription checks, or AI responses. Sync timing and availability still depend on network conditions, account state, and Apple cloud services."
                    ),
                    LegalSection(
                        title: "Retention and Your Controls",
                        body: "We use data to provide knowledge organization, OCR, summarization, sync, purchase validation, diagnostics, and quality improvements. You can remove most local data by deleting entries, attachments, or the app. If records are synced through iCloud, deletion may take time to propagate across devices and services."
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .unitedStates), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedAppleEULATitle(for: .unitedStates), url: appleStandardEULAURL)
                ],
                footerNote: "If you use the app in academic, business, or institutional contexts, make sure you have the rights and approvals needed for the materials you process."
            )
        case (.privacy, .japan):
            return LegalDocumentContent(
                title: "プライバシーポリシー",
                summary: "CogniSphere は、主に端末内に知識データを保存し、AI / OCR / 同期などを利用したときに必要な範囲で外部サービスを使用します。",
                sections: [
                    LegalSection(
                        title: "取り扱うデータ",
                        body: "本アプリは、知識項目、知識ネットワーク名、分類、メモ本文、リンク、添付メタデータ、添付ファイル本体、購読状態のキャッシュ、および運用上必要な最小限の診断情報を保存します。添付ファイルは端末内のアプリ領域に保存され、CloudKit 同期が利用可能な場合は iCloud 経由で他端末へ同期されることがあります。"
                    ),
                    LegalSection(
                        title: "外部送信が発生する場面",
                        body: "スマート認識、画像OCR、PDF要約、Webプレビュー、クラウド同期、購読確認などを実行すると、必要なデータが外部サービスへ送信される場合があります。これには文字列、OCR結果、切り抜き画像、縮小画像、PDF抽出テキスト、同期メタデータ、購入確認情報などが含まれます。"
                    ),
                    LegalSection(
                        title: "AI 処理と OpenAI 関連サービス",
                        body: "一部の AI 機能は、アプリ提供者が設定した遠隔 AI サービスで処理されます。そのサービスは、OpenAI モデルまたは OpenAI 互換機能を利用して、送信されたテキスト、画像、PDF を解析する場合があります。高い機密性を持つ個人情報、医療、法務、財務情報などは、必要性と権限を十分確認したうえで扱ってください。"
                    ),
                    LegalSection(
                        title: "同期と第三者",
                        body: "知識項目、知識ネットワーク一覧、および添付ファイルは Apple CloudKit / iCloud を通じて同一 Apple ID の他端末へ同期される場合があります。Apple、RevenueCat、AI サービス提供者は、それぞれの役割に応じて必要最小限の情報を処理します。同期速度や利用可否は、通信状況、アカウント状態、Apple のクラウドサービス状況に左右されます。"
                    ),
                    LegalSection(
                        title: "保存期間と管理方法",
                        body: "データは、知識整理、OCR、要約、同期、購読確認、障害解析、品質改善のために使用されます。多くのローカルデータは、知識項目・添付・アプリを削除することで消去できます。iCloud に同期された情報は、削除が他端末に反映されるまで時間がかかることがあります。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .japan), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedAppleEULATitle(for: .japan), url: appleStandardEULAURL)
                ],
                footerNote: "教育機関、研究、業務利用では、教材・画像・文書を処理する権限と許諾を事前に確認してください。"
            )
        case (.aiUsage, .taiwan):
            return LegalDocumentContent(
                title: "AI 使用說明",
                summary: "AI、OCR、PDF 摘要與知識提取可協助整理內容，但結果不保證完全正確，使用者必須自行審核。",
                sections: [
                    LegalSection(
                        title: "結果僅供輔助",
                        body: "AI 輸出、OCR 文字、PDF 摘要、網路比對說明與自動分類皆可能出現誤判、漏字、幻覺、過時或不完整資訊。你不應把任何 AI 輸出視為唯一真實來源，也不應取代專業意見、原始教材或正式文件。"
                    ),
                    LegalSection(
                        title: "適合的使用方式",
                        body: "本 app 適合用於學習、研究整理、閱讀筆記、教材封面與書頁歸檔、參考資料摘要與知識網絡建構。對於考試、醫療、法律、金融、公共安全或其他高風險判斷，你應回到原始來源自行驗證。"
                    ),
                    LegalSection(
                        title: "如何提高準確度",
                        body: "建議將你真正想辨識的主體放在畫面中央，避開雜亂背景，並拍得清楚、平整、光線充足。若是書頁、封面或商品包裝，可先裁切重點區域。PDF 若為掃描版，頁面越清晰，摘要越穩定。"
                    ),
                    LegalSection(
                        title: "版權、機密與敏感資料",
                        body: "請避免上傳未經授權的機密文件、受限制教材、內部商業資料，或不必要的個人敏感資訊。若你必須處理受保護內容，應先確認法律、授權與組織政策是否允許。"
                    ),
                    LegalSection(
                        title: "外部比對與限制",
                        body: "某些摘要或說明可能顯示外部資訊比對結果；若執行環境沒有可用的外部搜尋能力，系統不應假裝查過資料。即使有比對，也應視為輔助線索而非最終定論。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .taiwan), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .taiwan), url: openAITermsURL)
                ],
                footerNote: "使用 AI 功能即表示你理解：結果可能有誤，且你會在加入知識點、分享或依賴前自行審核。"
            )
        case (.aiUsage, .unitedStates):
            return LegalDocumentContent(
                title: "AI Use Notice",
                summary: "AI extraction, OCR, PDF summaries, and automatic knowledge drafting are assistive features. You must review results before relying on them.",
                sections: [
                    LegalSection(
                        title: "Outputs Are Assistive, Not Authoritative",
                        body: "AI outputs, OCR text, PDF summaries, external verification notes, and auto-categorization may be inaccurate, incomplete, outdated, or fabricated. You should not treat them as the sole source of truth or as a substitute for professional judgment, source materials, or official documents."
                    ),
                    LegalSection(
                        title: "Appropriate Use Cases",
                        body: "The app is designed for study support, research organization, textbook capture, note-taking, reference summaries, and knowledge mapping. For medical, legal, financial, exam-critical, safety-critical, or other high-stakes decisions, you should review the original source materials and confirm the facts independently."
                    ),
                    LegalSection(
                        title: "How to Improve Accuracy",
                        body: "Place the intended subject near the center of the frame, reduce visual clutter, and capture a clear, well-lit image. Crop book covers, pages, or product labels when possible. For scanned PDFs, cleaner pages and better contrast generally improve OCR and summarization quality."
                    ),
                    LegalSection(
                        title: "Copyright, Confidentiality, and Sensitive Data",
                        body: "Avoid submitting confidential business records, restricted educational materials, or unnecessary sensitive personal data unless you have a legitimate need and the rights to do so. Make sure your use complies with applicable law, licensing terms, and institutional policies."
                    ),
                    LegalSection(
                        title: "External Verification Limits",
                        body: "Some summaries may reference external verification. If live web verification is unavailable in the current runtime, the app should not imply that external checking occurred. Even when external sources are available, that verification should be treated as an aid rather than a final conclusion."
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .unitedStates), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .unitedStates), url: openAITermsURL)
                ],
                footerNote: "By using AI features, you acknowledge that outputs may be wrong and that you are responsible for reviewing them before storing, sharing, or relying on them."
            )
        case (.aiUsage, .japan):
            return LegalDocumentContent(
                title: "AI利用ガイド",
                summary: "AI、OCR、PDF要約、自動知識化は補助機能です。結果をそのまま事実として扱わず、利用者自身が確認してください。",
                sections: [
                    LegalSection(
                        title: "出力は補助情報です",
                        body: "AI 出力、OCR テキスト、PDF 要約、外部照合メモ、自動分類には誤り、欠落、古い情報、推測が含まれる場合があります。唯一の真実源として扱ったり、専門家の助言や原資料の代替としたりしてはいけません。"
                    ),
                    LegalSection(
                        title: "想定される利用場面",
                        body: "本アプリは、学習支援、研究整理、教科書・資料の記録、読書ノート、参考資料要約、知識ネットワーク構築に適しています。医療、法務、金融、試験、公共安全など高リスクな判断では、原資料を確認し、自分で事実確認を行ってください。"
                    ),
                    LegalSection(
                        title: "精度を高める方法",
                        body: "認識したい対象を画面中央に置き、背景のノイズを減らし、明るく鮮明に撮影してください。表紙、書頁、商品ラベルは必要部分を切り抜くと安定しやすくなります。スキャン PDF は、文字がはっきりしているほど OCR と要約が改善します。"
                    ),
                    LegalSection(
                        title: "著作権・機密・センシティブ情報",
                        body: "機密文書、権利制限のある教材、不要な個人の機微情報は、正当な必要性と権限がある場合を除き送信しないでください。利用にあたっては、法令、ライセンス条件、所属組織の方針を確認してください。"
                    ),
                    LegalSection(
                        title: "外部照合の限界",
                        body: "一部の要約や説明には外部情報との照合結果が表示されることがあります。ただし、実行環境にライブ検索機能がない場合は、外部確認が行われたかのように扱うべきではありません。照合結果がある場合でも、最終判断ではなく補助情報として扱ってください。"
                    )
                ],
                links: [
                    LegalExternalLink(title: localizedOpenAIPrivacyTitle(for: .japan), url: openAIPrivacyURL),
                    LegalExternalLink(title: localizedOpenAITermsTitle(for: .japan), url: openAITermsURL)
                ],
                footerNote: "AI 機能を利用することで、出力に誤りがあり得ることを理解し、保存・共有・依拠する前に自ら確認する責任を負うことに同意したものとみなされます。"
            )
        }
    }

    static func legalCenterTitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "法律與 AI 說明"
        case .unitedStates:
            return "Legal & AI"
        case .japan:
            return "法務とAI案内"
        }
    }

    static func legalCenterSubtitle(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "請在使用 AI、OCR、同步與訂閱功能前閱讀。"
        case .unitedStates:
            return "Read before using AI, OCR, sync, and subscription features."
        case .japan:
            return "AI、OCR、同期、購読機能を使う前に確認してください。"
        }
    }
}
