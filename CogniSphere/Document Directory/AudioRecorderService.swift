import Foundation
import AVFoundation
import Combine

class AudioRecorderService: NSObject, ObservableObject, AVAudioRecorderDelegate {
    static let maximumRecordingDuration: TimeInterval = 30

    var audioRecorder: AVAudioRecorder?
    
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0 // ⏱️ 新增：記錄目前的錄音秒數，推播給 UI
    
    private var timer: Timer?
    var onRecordingFinished: ((String?) -> Void)?
    private var currentFileName: String = ""

    var clampedRecordingDuration: TimeInterval {
        min(recordingDuration, Self.maximumRecordingDuration)
    }

    var formattedRecordingDuration: String {
        let totalSeconds = Int(clampedRecordingDuration.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d / 00:%02d", minutes, seconds, Int(Self.maximumRecordingDuration))
    }
    
    func startRecording(completion: @escaping (String?) -> Void) {
        self.onRecordingFinished = completion
        stopTimer()
        
        // 1. 取得 Document Directory 路徑
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        currentFileName = UUID().uuidString + ".m4a"
        let audioFilename = documentPath.appendingPathComponent(currentFileName)
        
        // 2. 設定錄音音質與格式
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            // 請求麥克風權限 (記得在 Info.plist 加上 Privacy - Microphone Usage Description)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            
            // 💡 依然設定最多錄音 30 秒，保護使用者的容量
            audioRecorder?.record(forDuration: Self.maximumRecordingDuration)
            isRecording = true
            recordingDuration = 0
            
            // ⏱️ 啟動計時器，每 0.1 秒刷新一次 currentTime 給畫面的 UI 顯示
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self, let recorder = self.audioRecorder else { return }
                let currentTime = min(recorder.currentTime, Self.maximumRecordingDuration)
                self.recordingDuration = currentTime

                // `record(forDuration:)` 的完成回呼偶爾會比 UI timer 晚到，這裡再加一道硬停止。
                if recorder.currentTime >= (Self.maximumRecordingDuration - 0.05) {
                    self.stopRecording()
                }
            }
            
            print("🎙️ 開始錄音...")
            
        } catch {
            print("錄音啟動失敗: \(error)")
            completion(nil)
        }
    }
    
    // 🛑 新增：讓使用者隨時可以手動停止
    func stopRecording() {
        recordingDuration = min(audioRecorder?.currentTime ?? recordingDuration, Self.maximumRecordingDuration)
        audioRecorder?.stop() // 提早中止錄音
        isRecording = false
        stopTimer()
    }
    
    // 當 30 秒時間到，或手動呼叫 stopRecording() 時，系統會自動呼叫這裡
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        recordingDuration = min(recorder.currentTime, Self.maximumRecordingDuration)
        isRecording = false
        stopTimer()
        
        if flag {
            print("✅ 錄音完成，存檔為: \(currentFileName)")
            onRecordingFinished?(currentFileName)
        } else {
            onRecordingFinished?(nil)
        }
    }
    
    // 輔助函數：清除計時器
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopTimer()
    }
}
