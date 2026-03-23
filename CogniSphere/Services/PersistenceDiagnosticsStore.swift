import Combine
import Foundation

@MainActor
final class PersistenceDiagnosticsStore: ObservableObject {
    struct AlertContent: Identifiable {
        let id = UUID()
        let message: String
    }

    @Published var startupAlert: AlertContent?
    @Published private(set) var isPersistentStoreAvailable = true

    func presentPersistentStoreFailure(underlyingError: Error) {
        isPersistentStoreAvailable = false
        let message: String
        switch SupportedRegionUI.detect() {
        case .taiwan:
            message = "CogniSphere 目前無法開啟本機資料庫，已改用暫時記憶體模式啟動。這次新增或修改的內容在關閉 App 後不會保留；原有資料未被刪除。請稍後重新啟動，再檢查資料庫狀態。\n\n系統訊息：\(underlyingError.localizedDescription)"
        case .unitedStates:
            message = "CogniSphere could not open the local database and started in temporary in-memory mode instead. Changes made in this session will not persist after the app closes; the original local store was not deleted. Restart the app later and check the database state again.\n\nSystem message: \(underlyingError.localizedDescription)"
        case .japan:
            message = "CogniSphere は端末内データベースを開けなかったため、一時的なメモリモードで起動しました。このセッションで追加・変更した内容は App を閉じると保存されません。既存データは削除していません。しばらくしてから再起動し、データベース状態を確認してください。\n\nシステムメッセージ: \(underlyingError.localizedDescription)"
        }

        startupAlert = AlertContent(message: message)
    }

    func blockedMutationMessage(for region: SupportedRegionUI) -> String {
        switch region {
        case .taiwan:
            return "目前正以暫時記憶體模式執行，為避免資料在關閉 App 後消失，已暫停新增、編輯、匯入與附件寫入。請先重新啟動 App。"
        case .unitedStates:
            return "The app is currently running in temporary in-memory mode. To avoid losing data when the app closes, creating, editing, importing, and attachment writes are temporarily disabled. Please restart the app first."
        case .japan:
            return "現在は一時的なメモリモードで動作しています。App を閉じたときにデータが消えるのを防ぐため、追加・編集・取り込み・添付の保存を一時停止しています。先に App を再起動してください。"
        }
    }
}
