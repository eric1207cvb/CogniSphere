import Foundation
import SwiftData

@MainActor
enum AttachmentSyncBackfillService {
    static func backfillMissingAttachmentDataIfNeeded(modelContext: ModelContext) {
        let descriptor = FetchDescriptor<KnowledgeReference>()
        guard let references = try? modelContext.fetch(descriptor) else {
            return
        }

        var didChange = false
        for reference in references where reference.isFileAttachment {
            let existingData = reference.attachmentData ?? Data()
            if !existingData.isEmpty {
                continue
            }

            guard let fileName = reference.attachmentLocalFileName,
                  let attachment = try? AttachmentStorageController.storedAttachment(
                    named: fileName,
                    originalFileName: reference.attachmentOriginalFileName ?? fileName,
                    explicitMimeType: reference.attachmentMimeType
                  ) else {
                continue
            }

            reference.attachmentData = attachment.data
            if reference.attachmentOriginalFileName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                reference.attachmentOriginalFileName = attachment.originalFileName
            }
            if reference.attachmentMimeType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                reference.attachmentMimeType = attachment.mimeType
            }
            didChange = true
        }

        guard didChange else { return }
        try? modelContext.save()
    }
}
