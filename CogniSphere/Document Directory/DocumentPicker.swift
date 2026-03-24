import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct StoredAttachment {
    let fileName: String
    let originalFileName: String
    let mimeType: String
    let data: Data
}

struct DocumentPicker: UIViewControllerRepresentable {
    var onDocumentPicked: ((StoredAttachment) -> Void)?
    var onFailure: ((String) -> Void)?
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // 只允許選擇 PDF 檔案
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let selectedURL = urls.first else { return }
            
            // 🚨 核心安全機制：取得安全存取權限
            let canAccess = selectedURL.startAccessingSecurityScopedResource()
            defer {
                if canAccess { selectedURL.stopAccessingSecurityScopedResource() }
            }
            
            do {
                let result = try AttachmentStorageController.storePDFCopy(from: selectedURL)
                print("✅ PDF 複製成功: \(result.fileName)")
                parent.onDocumentPicked?(result)
            } catch {
                print("❌ PDF 複製失敗: \(error)")
                parent.onFailure?(AttachmentStorageController.userFacingErrorMessage(for: error, action: RegionUIStore.runtimeCopy().importPDF))
            }
        }
    }
}

enum AttachmentStorageError: LocalizedError {
    case imageEncodingFailed
    case fileTooLarge(kind: String, limitBytes: Int64)
    case storageQuotaExceeded(limitBytes: Int64)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "圖片無法處理，請換一張再試一次。"
            case .unitedStates: return "This image could not be processed. Please try another one."
            case .japan: return "画像を処理できません。別の画像でお試しください。"
            }
        case let .fileTooLarge(kind, limitBytes):
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "\(kind) 超過大小限制（\(AttachmentStorageController.formattedByteCount(limitBytes))）。"
            case .unitedStates: return "\(kind) exceeds the size limit (\(AttachmentStorageController.formattedByteCount(limitBytes)))."
            case .japan: return "\(kind) がサイズ上限（\(AttachmentStorageController.formattedByteCount(limitBytes))）を超えています。"
            }
        case let .storageQuotaExceeded(limitBytes):
            switch RegionUIStore.runtimeRegion() {
            case .taiwan: return "附件空間已接近上限（\(AttachmentStorageController.formattedByteCount(limitBytes))），請先刪除舊附件。"
            case .unitedStates: return "Attachment storage is nearly full (\(AttachmentStorageController.formattedByteCount(limitBytes))). Please delete old files first."
            case .japan: return "添付ストレージが上限に近づいています（\(AttachmentStorageController.formattedByteCount(limitBytes))）。古いファイルを先に削除してください。"
            }
        }
    }
}

enum AttachmentStorageController {
    static let maxTotalStorageBytes: Int64 = 1_500_000_000
    static let maxPDFBytes: Int64 = 25_000_000
    static let maxImageBytes: Int64 = 10_000_000
    static let shortAudioReservationBytes: Int64 = 2_000_000
    private static let maxImageLongestSide: CGFloat = 2200

    static func userFacingErrorMessage(for error: Error, action: String) -> String {
        let region = RegionUIStore.runtimeRegion()
        if let storageError = error as? AttachmentStorageError {
            switch storageError {
            case .imageEncodingFailed:
                switch region {
                case .taiwan: return "\(action)失敗，圖片目前無法處理，請換一張再試一次。"
                case .unitedStates: return "\(action) failed. This image cannot be processed right now. Please try another one."
                case .japan: return "\(action)に失敗しました。画像を処理できないため、別の画像でお試しください。"
                }
            case let .fileTooLarge(kind, limitBytes):
                switch region {
                case .taiwan: return "\(action)失敗，\(kind) 太大了。上限是 \(formattedByteCount(limitBytes))。"
                case .unitedStates: return "\(action) failed. \(kind) is too large. The limit is \(formattedByteCount(limitBytes))."
                case .japan: return "\(action)に失敗しました。\(kind) が大きすぎます。上限は \(formattedByteCount(limitBytes)) です。"
                }
            case let .storageQuotaExceeded(limitBytes):
                switch region {
                case .taiwan: return "\(action)失敗，附件空間已接近上限（\(formattedByteCount(limitBytes))），請先刪除部分舊附件。"
                case .unitedStates: return "\(action) failed. Attachment storage is nearly full (\(formattedByteCount(limitBytes))). Please remove old attachments first."
                case .japan: return "\(action)に失敗しました。添付ストレージが上限に近づいています（\(formattedByteCount(limitBytes))）。先に古い添付を削除してください。"
                }
            }
        }

        let fallback = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            switch region {
            case .taiwan: return "\(action)失敗，請再試一次。"
            case .unitedStates: return "\(action) failed. Please try again."
            case .japan: return "\(action)に失敗しました。もう一度お試しください。"
            }
        }
        switch region {
        case .taiwan: return "\(action)失敗，\(fallback)"
        case .unitedStates: return "\(action) failed. \(fallback)"
        case .japan: return "\(action)に失敗しました。\(fallback)"
        }
    }

    static func documentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func localFileURL(for fileName: String) -> URL {
        documentsDirectory().appendingPathComponent(fileName)
    }

    static func fileExistsLocally(named fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: localFileURL(for: fileName).path)
    }

    static func saveImage(_ image: UIImage) throws -> StoredAttachment {
        let start = CFAbsoluteTimeGetCurrent()
        let preparedImage = resizedImageIfNeeded(image)
        let imageData = try compressedJPEGData(from: preparedImage)
        try ensureCapacity(forAdditionalBytes: Int64(imageData.count))

        let fileName = UUID().uuidString + ".jpg"
        let fileURL = localFileURL(for: fileName)
        try imageData.write(to: fileURL, options: .atomic)
        let totalUsage = currentUsageBytes()
        Task {
            await PerformanceTraceRecorder.shared.record(
                name: "attachment_save_image",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "bytes": "\(imageData.count)",
                    "total_usage_bytes": "\(totalUsage)"
                ]
            )
        }
        return StoredAttachment(
            fileName: fileName,
            originalFileName: fileName,
            mimeType: mimeType(forFileName: fileName),
            data: imageData
        )
    }

    static func storePDFCopy(from selectedURL: URL) throws -> StoredAttachment {
        let start = CFAbsoluteTimeGetCurrent()
        let resourceValues = try selectedURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = Int64(resourceValues.fileSize ?? 0)

        if fileSize > maxPDFBytes {
            throw AttachmentStorageError.fileTooLarge(kind: RegionUIStore.runtimeCopy().importPDF, limitBytes: maxPDFBytes)
        }

        try ensureCapacity(forAdditionalBytes: fileSize)

        let originalName = selectedURL.lastPathComponent
        let newFileName = UUID().uuidString + "_" + originalName
        let destinationURL = localFileURL(for: newFileName)
        try FileManager.default.copyItem(at: selectedURL, to: destinationURL)
        let data = try Data(contentsOf: destinationURL)
        let totalUsage = currentUsageBytes()
        Task {
            await PerformanceTraceRecorder.shared.record(
                name: "attachment_save_pdf",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "bytes": "\(fileSize)",
                    "total_usage_bytes": "\(totalUsage)"
                ]
            )
        }
        return StoredAttachment(
            fileName: newFileName,
            originalFileName: originalName,
            mimeType: mimeType(forFileName: originalName),
            data: data
        )
    }

    static func storedAttachment(
        named fileName: String,
        originalFileName: String? = nil,
        explicitMimeType: String? = nil
    ) throws -> StoredAttachment {
        let trimmedName = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileURL = localFileURL(for: trimmedName)
        let data = try Data(contentsOf: fileURL)
        let resolvedOriginalName = originalFileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? originalFileName!.trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmedName
        return StoredAttachment(
            fileName: trimmedName,
            originalFileName: resolvedOriginalName,
            mimeType: explicitMimeType ?? mimeType(forFileName: resolvedOriginalName),
            data: data
        )
    }

    static func storeGeneratedFile(
        data: Data,
        preferredFileName: String,
        explicitMimeType: String? = nil
    ) throws -> StoredAttachment {
        let trimmedOriginalName = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalFileName = trimmedOriginalName.isEmpty ? UUID().uuidString : trimmedOriginalName
        let resolvedMimeType = explicitMimeType ?? mimeType(forFileName: originalFileName)
        let fileSize = Int64(data.count)

        if resolvedMimeType == "application/pdf" || originalFileName.lowercased().hasSuffix(".pdf") {
            if fileSize > maxPDFBytes {
                throw AttachmentStorageError.fileTooLarge(kind: RegionUIStore.runtimeCopy().importPDF, limitBytes: maxPDFBytes)
            }
        }

        try ensureCapacity(forAdditionalBytes: fileSize)

        let storedFileName = UUID().uuidString + "_" + originalFileName
        let destinationURL = localFileURL(for: storedFileName)
        try data.write(to: destinationURL, options: .atomic)
        return StoredAttachment(
            fileName: storedFileName,
            originalFileName: originalFileName,
            mimeType: resolvedMimeType,
            data: data
        )
    }

    static func restoredLocalFileURL(for reference: KnowledgeReference) -> URL? {
        guard let fileName = reference.attachmentLocalFileName else { return nil }
        let fileURL = localFileURL(for: fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        guard let data = reference.attachmentData, !data.isEmpty else {
            return nil
        }
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    static func image(for reference: KnowledgeReference) -> UIImage? {
        if let fileURL = restoredLocalFileURL(for: reference),
           let image = UIImage(contentsOfFile: fileURL.path) {
            return image
        }
        guard let data = reference.attachmentData else {
            return nil
        }
        return UIImage(data: data)
    }

    static func ensureCapacity(forAdditionalBytes additionalBytes: Int64) throws {
        let projected = currentUsageBytes() + max(0, additionalBytes)
        if projected > maxTotalStorageBytes {
            throw AttachmentStorageError.storageQuotaExceeded(limitBytes: maxTotalStorageBytes)
        }
    }

    static func deleteStoredFileIfPresent(named fileName: String) {
        let start = CFAbsoluteTimeGetCurrent()
        let fileURL = localFileURL(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.removeItem(at: fileURL)
        let totalUsage = currentUsageBytes()
        Task {
            await PerformanceTraceRecorder.shared.record(
                name: "attachment_delete_file",
                durationMs: elapsedDurationMs(since: start),
                metadata: [
                    "file_name": fileName,
                    "total_usage_bytes": "\(totalUsage)"
                ]
            )
        }
    }

    static func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func mimeType(forFileName fileName: String) -> String {
        let fileExtension = URL(fileURLWithPath: fileName).pathExtension
        if let utType = UTType(filenameExtension: fileExtension),
           let mimeType = utType.preferredMIMEType {
            return mimeType
        }
        return "application/octet-stream"
    }

    private static func currentUsageBytes() -> Int64 {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: documentsDirectory(),
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.reduce(0) { partial, url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { return partial }
            return partial + Int64(values?.fileSize ?? 0)
        }
    }

    private static func resizedImageIfNeeded(_ image: UIImage) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxImageLongestSide, longestSide > 0 else {
            return image
        }

        let scale = maxImageLongestSide / longestSide
        let targetSize = CGSize(
            width: floor(image.size.width * scale),
            height: floor(image.size.height * scale)
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func compressedJPEGData(from image: UIImage) throws -> Data {
        for quality in stride(from: 0.72, through: 0.32, by: -0.1) {
            if let data = image.jpegData(compressionQuality: quality), Int64(data.count) <= maxImageBytes {
                return data
            }
        }

        if let fallback = image.jpegData(compressionQuality: 0.24), Int64(fallback.count) <= maxImageBytes {
            return fallback
        }

        if image.jpegData(compressionQuality: 0.24) != nil {
            let imageKind: String
            switch RegionUIStore.runtimeRegion() {
            case .taiwan:
                imageKind = "圖片"
            case .unitedStates:
                imageKind = "Image"
            case .japan:
                imageKind = "画像"
            }
            throw AttachmentStorageError.fileTooLarge(kind: imageKind, limitBytes: maxImageBytes)
        }

        throw AttachmentStorageError.imageEncodingFailed
    }
}
