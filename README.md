# CogniSphere

CogniSphere 是一個以 SwiftUI 建構的 iOS 知識圖譜 App。使用者可以拍攝筆記或從相簿選圖，App 先在裝置端用 Vision 做 OCR，再把整理後的文字送到 AI 服務產生知識節點候選，經人工確認後寫入 SwiftData，最後以互動式圖譜呈現。

## 目前功能

- 拍照或從相簿匯入筆記圖片
- 裝置端 OCR 文字辨識
- AI 產生知識節點候選，支援匯入前人工勾選
- 手動新增知識節點
- SwiftData 本地持久化
- 互動式知識圖譜，支援拖曳、縮放、兩種佈局模式
- 節點附加資源：網頁、文字筆記、圖片、PDF、語音備忘錄
- 圖片與 PDF 附件可直接在 App 內預覽
- 最新加入的知識節點會在圖譜上被特別標示

## 技術棧

- SwiftUI
- SwiftData
- Vision
- PDFKit
- AVFoundation
- UIKit bridge (`UIImagePickerController`, `UIDocumentPickerViewController`)

## 專案結構

- `CogniSphere/CogniSphereApp.swift`
  App 入口與 SwiftData `ModelContainer`
- `CogniSphere/Models/KnowledgeModel.swift`
  知識節點、參考資料、清洗與驗證規則
- `CogniSphere/Models/KnowledgeImportModels.swift`
  匯入預覽用 model
- `CogniSphere/Services/KnowledgeExtractionService.swift`
  OCR、AI request、候選建立與寫入
- `CogniSphere/Services/ProtectedServiceAuthStore.swift`
  AI / OCR 後端短效 token 與 protected endpoint 切換
- `CogniSphere/Views/ContentView.swift`
  主畫面、匯入流程與狀態管理
- `CogniSphere/Views/InteractiveGraphView.swift`
  圖譜繪製、佈局計算、節點互動
- `CogniSphere/Views/NodeDetailView.swift`
  節點細節與附件管理/預覽
- `CogniSphere/Document Directory/`
  本地檔案附件與錄音相關服務

## 資料流

1. 使用者拍照或選圖。
2. `KnowledgeExtractionService` 先用 Vision 擷取文字。
3. OCR 結果送到 AI chat endpoint 產生 JSON 節點候選。
4. App 依清洗規則去除雜訊、重複與低品質條目。
5. 使用者在匯入確認畫面勾選要寫入的候選。
6. 節點寫入 SwiftData，圖譜立即更新。

## AI 服務

目前 App 不是直接把圖片送到本地 `8080` 後端，而是：

- 先在本機做 OCR
- 再把純文字送到 `KnowledgeExtractionService.swift` 內設定的 chat API

現行 legacy endpoint：

```swift
private let serverURL = URL(string: "https://wonderkidai-server.onrender.com/api/chat")!
```

若 `Info.plist` 同時設定：

- `ProtectedSessionURL`
- `ProtectedChatURL`

App 會改成先向 `ProtectedSessionURL` 換短效 token，再帶 `Authorization: Bearer <token>` 打 `ProtectedChatURL`。兩個值都留空時，才會退回 legacy endpoint。

目前 request payload 為文字 prompt，不是 README 舊版描述的 image payload。回應仍需符合以下資料結構：

```json
{
  "choices": [
    {
      "message": {
        "content": "{\"nodes\":[{\"title\":\"...\",\"content\":\"...\",\"category\":\"自然科學\"}]}"
      }
    }
  ]
}
```

其中 `content` 必須能 decode 成：

```json
{
  "nodes": [
    {
      "title": "知識點標題",
      "content": "知識摘要",
      "category": "自然科學"
    }
  ]
}
```

可用分類：

- 自然科學
- 數學科學
- 系統科學
- 思維科學
- 人體科學
- 社會科學

## 本地附件

節點可掛載下列附件，實體檔案儲存在 app sandbox 的 Documents 目錄：

- 圖片
- PDF
- 語音備忘錄
- 文字筆記
- 網頁連結

圖片與 PDF 已支援 App 內預覽；語音備忘錄可直接播放。

## 開發需求

- 最新版 Xcode
- 專案目前 deployment target 設為 `iOS 26.1`
- 真機建議用於相機與麥克風測試

> 註：相機在 Simulator 不可用，專案已在模擬器改成從相簿選圖。

## 權限

專案目前透過 Xcode build settings 產生 Info.plist，已包含：

- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`

## 建置

1. 用 Xcode 開啟 `CogniSphere.xcodeproj`
2. 確認簽章設定可用
3. Build and Run

CLI 驗證範例：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CogniSphere.xcodeproj \
  -scheme CogniSphere \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath ./.derivedData \
  build
```

## 已知限制

- SwiftData store 初始化失敗時，App 目前會刪除舊 store 後重建
- AI 與 OCR 相關流程仍缺少自動化測試
- UI tests 目前仍是預設骨架

## 測試現況

- `CogniSphereTests/` 目前只有空白示例測試
- `CogniSphereUITests/` 目前只有基本啟動測試
