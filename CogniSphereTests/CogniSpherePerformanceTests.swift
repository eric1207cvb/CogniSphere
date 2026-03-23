import XCTest
import UIKit
@testable import CogniSphere

@MainActor
final class CogniSpherePerformanceTests: XCTestCase {
    override func setUp() async throws {
        try? FileManager.default.removeItem(at: PerformanceTraceRecorder.traceFileURL())
    }

    func testGraphLayoutStressConstellation() {
        runGraphLayoutStress(mode: .constellation, sizes: [60, 120, 180], averageThresholdMs: 1500)
    }

    func testGraphLayoutStressPathway() {
        runGraphLayoutStress(mode: .pathway, sizes: [60, 120, 180], averageThresholdMs: 4000)
    }

    func testAttachmentStorageCompressionBudget() throws {
        let image = makeSyntheticImage(size: CGSize(width: 4200, height: 3200))
        let attachment = try AttachmentStorageController.saveImage(image)
        defer {
            AttachmentStorageController.deleteStoredFileIfPresent(named: attachment.fileName)
        }

        let fileURL = AttachmentStorageController.localFileURL(for: attachment.fileName)
        let fileSize = try XCTUnwrap(
            (try fileURL.resourceValues(forKeys: [URLResourceKey.fileSizeKey])).fileSize
        )

        NSLog("ATTACHMENT_BUDGET image_bytes=%d limit_bytes=%lld", fileSize, AttachmentStorageController.maxImageBytes)
        XCTAssertLessThanOrEqual(Int64(fileSize), AttachmentStorageController.maxImageBytes)
    }

    func testPerformanceTraceRecorderWritesJsonl() async throws {
        await PerformanceTraceRecorder.shared.record(
            name: "unit_test_trace",
            durationMs: 12.5,
            metadata: ["suite": "CogniSpherePerformanceTests"]
        )

        let contents = try String(contentsOf: PerformanceTraceRecorder.traceFileURL(), encoding: .utf8)
        XCTAssertTrue(contents.contains("unit_test_trace"))
        NSLog("TRACE_FILE path=%@", PerformanceTraceRecorder.traceFilePathDescription())
    }

    private func runGraphLayoutStress(
        mode: GraphLayoutMode,
        sizes: [Int],
        averageThresholdMs: Double
    ) {
        for size in sizes {
            let nodes = makeNodes(count: size)
            var durations: [Double] = []

            for _ in 0..<5 {
                let engine = GraphLayoutEngine()
                let startedAt = CFAbsoluteTimeGetCurrent()
                engine.sync(with: nodes, mode: mode, newestNodeID: nodes.last?.id)
                let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
                durations.append(durationMs)

                XCTAssertEqual(engine.visNodes.count, nodes.count)
                XCTAssertFalse(engine.edges.isEmpty)
            }

            let average = durations.reduce(0, +) / Double(durations.count)
            let maxDuration = durations.max() ?? 0
            NSLog(
                "GRAPH_STRESS mode=%@ nodes=%d avg_ms=%.2f max_ms=%.2f",
                mode == .pathway ? "pathway" : "constellation",
                size,
                average,
                maxDuration
            )
            XCTAssertLessThan(average, averageThresholdMs)
        }
    }

    private func makeNodes(count: Int) -> [KnowledgeNode] {
        let categories = KnowledgeCategory.allCases

        return (0..<count).map { index in
            let category = categories[index % categories.count]
            let cluster = index % 12
            let topic = "topic\(cluster)"
            let concept = "concept\(index % 24)"
            return KnowledgeNode(
                title: "研究節點 \(index) \(topic) \(concept)",
                content: """
                \(topic) \(concept) methodology analysis synthesis framework dataset observation
                \(category.rawValue) cluster \(cluster) literature review experiment comparison
                """,
                category: category,
                x: 0, y: 0, z: 0
            )
        }
    }

    private func makeSyntheticImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            for stripe in stride(from: 0, to: Int(size.height), by: 140) {
                let color = stripe % 280 == 0 ? UIColor.darkGray : UIColor.systemBlue
                color.setFill()
                context.fill(CGRect(x: 0, y: stripe, width: Int(size.width), height: 56))
            }

            let paragraph = String(repeating: "博士研究資料與圖譜筆記 OCR 壓測 ", count: 120)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .medium),
                .foregroundColor: UIColor.black
            ]
            paragraph.draw(
                in: CGRect(x: 120, y: 180, width: size.width - 240, height: size.height - 360),
                withAttributes: attributes
            )
        }
    }
}
