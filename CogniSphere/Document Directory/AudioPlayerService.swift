import Foundation
import AVFoundation
import Combine

class AudioPlayerService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    var audioPlayer: AVAudioPlayer?
    @Published var isPlaying = false
    
    func playAudio(fileURL: URL) {
        do {
            if isPlaying {
                audioPlayer?.stop()
            }
            
            // 💡 關鍵設定：這行能確保即使手機切換到「靜音模式」，錄音依然能從喇叭播出來
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.delegate = self
            audioPlayer?.play()
            isPlaying = true
            print("▶️ 開始播放錄音: \(fileURL.lastPathComponent)")
            
        } catch {
            print("❌ 播放失敗: \(error)")
        }
    }
    
    // 手動停止播放
    func stopAudio() {
        audioPlayer?.stop()
        isPlaying = false
    }
    
    // 檔案自然播完時，系統會自動呼叫這裡
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
    }
}
