import Foundation
import os

actor PerformanceTraceRecorder {
    static let shared = PerformanceTraceRecorder()

    private let logger = Logger(subsystem: "tw.yian.CogniSphere", category: "Performance")

    func record(name: String, durationMs: Double, metadata: [String: String] = [:]) {
        persist(name: name, durationMs: durationMs, metadata: metadata)
        logger.info("perf \(name, privacy: .public) \(durationMs, privacy: .public)ms \(self.metadataDescription(metadata), privacy: .public)")
    }

    nonisolated static func traceFileURL() -> URL {
        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cachesDirectory.appendingPathComponent("performance-traces.jsonl")
    }

    nonisolated static func traceFilePathDescription() -> String {
        traceFileURL().path
    }

    private func persist(name: String, durationMs: Double, metadata: [String: String]) {
        let payload: [String: Any] = [
            "id": UUID().uuidString,
            "name": name,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "duration_ms": durationMs,
            "metadata": metadata
        ]

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let lineBreak = Data([0x0A])
        let fileURL = Self.traceFileURL()

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            var initialData = Data()
            initialData.append(data)
            initialData.append(lineBreak)
            FileManager.default.createFile(atPath: fileURL.path, contents: initialData)
            return
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.write(contentsOf: lineBreak)
        } catch {
            logger.error("perf persist failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func metadataDescription(_ metadata: [String: String]) -> String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
    }
}

@inline(__always)
func measureDurationMs(_ work: () throws -> Void) rethrows -> Double {
    let start = CFAbsoluteTimeGetCurrent()
    try work()
    return (CFAbsoluteTimeGetCurrent() - start) * 1000
}

@inline(__always)
func elapsedDurationMs(since start: CFAbsoluteTime) -> Double {
    (CFAbsoluteTimeGetCurrent() - start) * 1000
}
