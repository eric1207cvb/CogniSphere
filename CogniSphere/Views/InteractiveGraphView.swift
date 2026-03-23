import SwiftUI
import SwiftData
import Combine

enum GraphLayoutMode {
    case constellation
    case pathway
}

enum EdgeStyle {
    case solid
    case dashed
    case dotted
}

struct VisNode: Identifiable {
    let id: UUID
    let title: String
    let categoryRaw: String
    let position: CGPoint
    let isHub: Bool
    let isBridge: Bool
    let isNewest: Bool
    let bridgeStrength: CGFloat
    let relatedCategoryRaws: [String]
    let labelOffset: CGSize

    var color: Color {
        colorForCategory(categoryRaw)
    }
}

struct GraphEdge: Identifiable {
    let id: UUID
    let from: UUID
    let to: UUID
    let style: EdgeStyle
    let color: Color
    let strength: CGFloat
    let isCrossDomain: Bool
}

private func colorForCategory(_ category: String) -> Color {
    KnowledgeCategory(rawValue: category)?.accentColor ?? .gray
}

final class GraphLayoutEngine: ObservableObject {
    @Published var visNodes: [VisNode] = []
    @Published var edges: [GraphEdge] = []
    @Published var categoryAnchors: [String: CGPoint] = [:]

    private let pathwayCategoryAngles: [String: CGFloat] = [
        "自然科學": -.pi * 0.55,
        "數學科學": -.pi * 0.18,
        "系統科學": .pi * 0.08,
        "思維科學": .pi * 0.42,
        "人體科學": .pi * 0.72,
        "社會科學": .pi * 1.12
    ]

    private let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "that", "this", "are", "was",
        "were", "have", "has", "had", "will", "your", "their", "about", "than",
        "http", "https", "www", "com", "org", "net", "ok"
    ]

    private let lowSignalRelationTokens: Set<String> = [
        "安全", "系統", "科學", "研究", "資料", "資訊", "方法", "理論", "原理", "設計",
        "science", "system", "systems", "research", "study", "data", "information",
        "method", "methods", "theory", "design", "analysis"
    ]

    private let foundationalKeywords: Set<String> = [
        "基礎", "入門", "導論", "概論", "原理", "理論", "概念", "總論", "架構",
        "fundamental", "fundamentals", "foundation", "foundations", "introduction",
        "intro", "overview", "principle", "principles", "concept", "concepts"
    ]

    private let applicationKeywords: Set<String> = [
        "應用", "實務", "檢核", "治理", "管理", "分析", "實作", "部署", "防護", "評估",
        "application", "applications", "applied", "practice", "implementation",
        "audit", "auditing", "governance", "management", "deployment", "protection", "assessment"
    ]

    private let exampleKeywords: Set<String> = [
        "案例", "產品", "樣本", "品牌", "設備", "器材", "工具", "濕紙巾", "試劑", "套件",
        "example", "examples", "case", "cases", "product", "products", "device",
        "devices", "tool", "tools", "kit", "kits", "wipe", "wipes"
    ]

    private struct LayoutSeed {
        let id: UUID
        let title: String
        let categoryRaw: String
        let titleTokens: Set<String>
        let textTokens: Set<String>
        let semanticTokens: Set<String>
        let abstractionScore: CGFloat
        let applicationScore: CGFloat
        let exampleScore: CGFloat
    }

    private struct LayoutNodeInput {
        let id: UUID
        let title: String
        let contentPreview: String
        let category: String
        let createdAt: Date
    }

    private struct InferredEdge {
        let from: UUID
        let to: UUID
        let strength: CGFloat
        let sameCategory: Bool
        let hierarchyKind: HierarchyKind?
        let hierarchyParentID: UUID?
        let hierarchyChildID: UUID?
    }

    private struct BridgeProfile {
        let nodeID: UUID
        let relatedCategories: [String]
        let averageAngle: CGFloat
        let bridgeStrength: CGFloat
    }

    private enum HierarchyKind {
        case prerequisite
        case application
        case example
    }

    func sync(with dbNodes: [KnowledgeNode], mode: GraphLayoutMode, newestNodeID: UUID?) {
        let syncStart = CFAbsoluteTimeGetCurrent()
        let snapshot = dbNodes.map(makeLayoutInput)

        guard !snapshot.isEmpty else {
            visNodes = []
            edges = []
            categoryAnchors = [:]
            Task {
                await PerformanceTraceRecorder.shared.record(
                    name: "graph_sync",
                    durationMs: elapsedDurationMs(since: syncStart),
                    metadata: ["nodes": "0", "mode": mode == .pathway ? "pathway" : "constellation"]
                )
            }
            return
        }

        let groupedNodes = Dictionary(grouping: snapshot, by: \.category)
        let seeds = snapshot.map(makeSeed)
        let inferredEdges = inferEdges(from: seeds, mode: mode)
        let bridgeProfiles = bridgeProfiles(from: inferredEdges, seeds: seeds)
        let weightedDegree = makeWeightedDegreeMap(from: inferredEdges)

        switch mode {
        case .constellation:
            visNodes = makeBranchLayout(
                groupedNodes: groupedNodes,
                bridgeProfiles: bridgeProfiles,
                weightedDegree: weightedDegree,
                newestNodeID: newestNodeID
            )
            edges = makeBranchEdges(nodes: visNodes, inferredEdges: inferredEdges)
        case .pathway:
            let laidOutNodes = makeNetworkLayout(
                seeds: seeds,
                edges: inferredEdges,
                bridgeProfiles: bridgeProfiles,
                mode: mode,
                newestNodeID: newestNodeID
            )

            categoryAnchors = [:]
            visNodes = laidOutNodes
            edges = inferredEdges.map { edge in
                GraphEdge(
                    id: UUID(),
                    from: edge.from,
                    to: edge.to,
                    style: edge.sameCategory ? (edge.strength > 0.42 ? .solid : .dashed) : .dotted,
                    color: edge.sameCategory
                        ? colorForCategory(nodeCategory(for: edge.from, in: laidOutNodes)).opacity(0.55)
                        : Color.black.opacity(0.36),
                    strength: edge.strength,
                    isCrossDomain: !edge.sameCategory
                )
            }
        }

        Task {
            await PerformanceTraceRecorder.shared.record(
                name: "graph_sync",
                durationMs: elapsedDurationMs(since: syncStart),
                metadata: [
                    "nodes": "\(snapshot.count)",
                    "edges": "\(edges.count)",
                    "mode": mode == .pathway ? "pathway" : "constellation"
                ]
            )
        }
    }

    private func makeBranchLayout(
        groupedNodes: [String: [LayoutNodeInput]],
        bridgeProfiles: [UUID: BridgeProfile],
        weightedDegree: [UUID: CGFloat],
        newestNodeID: UUID?
    ) -> [VisNode] {
        let categoryOrder = KnowledgeCategory.allCases.map(\.rawValue)
        var anchors: [String: CGPoint] = [:]
        var result: [VisNode] = []

        for category in categoryOrder {
            let sortedNodes = (groupedNodes[category] ?? []).sorted {
                let lhsBridge = bridgeProfiles[$0.id]?.bridgeStrength ?? 0
                let rhsBridge = bridgeProfiles[$1.id]?.bridgeStrength ?? 0
                let lhsDegree = weightedDegree[$0.id, default: 0]
                let rhsDegree = weightedDegree[$1.id, default: 0]

                if lhsDegree == rhsDegree {
                    if lhsBridge == rhsBridge {
                        return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    }
                    return lhsBridge > rhsBridge
                }
                return lhsDegree > rhsDegree
            }

            let angle = pathwayCategoryAngles[category] ?? 0
            let direction = CGPoint(x: cos(angle), y: sin(angle) * 0.86)
            let normal = normalized(CGPoint(x: -direction.y, y: direction.x))
            let anchor = direction * 92
            anchors[category] = anchor

            for (index, node) in sortedNodes.enumerated() {
                let bridgeProfile = bridgeProfiles[node.id]
                let lane = index == 0 ? 0 : (index % 2 == 0 ? 1 : -1)
                let tier = CGFloat(index / 2)
                let branchDistance = 80 + tier * 84 + (index == 0 ? 0 : 34)
                let branchSideOffset = index == 0 ? 0 : CGFloat(lane) * (34 + tier * 11)
                let branchPosition = anchor + direction * branchDistance + normal * branchSideOffset

                let position: CGPoint
                let labelVector: CGPoint
                if let bridgeProfile, index > 0 {
                    let bridgeAngle = bridgeProfile.averageAngle
                    let bridgeDirection = normalized(CGPoint(x: cos(bridgeAngle), y: sin(bridgeAngle) * 0.84))
                    let bridgeNormal = normalized(CGPoint(x: -bridgeDirection.y, y: bridgeDirection.x))
                    let inwardDistance = 92 + min(2, tier) * 34
                    let bridgeOffset = CGFloat(lane == 0 ? 1 : lane) * 18
                    let bridgePosition = bridgeDirection * inwardDistance + bridgeNormal * bridgeOffset
                    let blend = min(0.78, 0.42 + bridgeProfile.bridgeStrength * 0.48)
                    position = branchPosition * (1 - blend) + bridgePosition * blend
                    labelVector = normalized(bridgeDirection + bridgeNormal * CGFloat(lane == 0 ? 1 : lane) * 0.32)
                } else {
                    position = branchPosition
                    labelVector = normalized(direction + normal * CGFloat(lane) * 0.35)
                }

                result.append(
                    VisNode(
                        id: node.id,
                        title: shortLabel(for: node.title, maxLength: index == 0 ? 12 : 10),
                        categoryRaw: node.category,
                        position: position,
                        isHub: index == 0,
                        isBridge: bridgeProfile != nil,
                        isNewest: node.id == newestNodeID,
                        bridgeStrength: bridgeProfile?.bridgeStrength ?? 0,
                        relatedCategoryRaws: bridgeProfile?.relatedCategories ?? [],
                        labelOffset: CGSize(
                            width: labelVector.x * (bridgeProfile == nil ? 13 : 15),
                            height: (index == 0 ? 20 : 17) + max(0, labelVector.y) * 7
                        )
                    )
                )
            }
        }

        result = relaxConstellationLayout(result)
        categoryAnchors = anchors
        return result
    }

    private func makeBranchEdges(nodes: [VisNode], inferredEdges: [InferredEdge]) -> [GraphEdge] {
        let grouped = Dictionary(grouping: nodes, by: \.categoryRaw)
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var result: [GraphEdge] = []

        for (category, categoryNodes) in grouped {
            let orderedNodes = categoryNodes.sorted { lhs, rhs in
                length(of: lhs.position) < length(of: rhs.position)
            }
            let rankByID = Dictionary(uniqueKeysWithValues: orderedNodes.enumerated().map { ($1.id, $0) })
            let intraCategoryCandidates = inferredEdges
                .filter { edge in
                    guard edge.sameCategory, edge.strength >= 0.22,
                          edge.hierarchyParentID != nil,
                          edge.hierarchyChildID != nil,
                          let from = nodeMap[edge.from],
                          let to = nodeMap[edge.to] else { return false }
                    return from.categoryRaw == category && to.categoryRaw == category
                }
                .sorted { lhs, rhs in
                    if lhs.strength == rhs.strength {
                        return edgeKey(lhs.from, lhs.to) < edgeKey(rhs.from, rhs.to)
                    }
                    return lhs.strength > rhs.strength
                }

            var connectedChildren = Set<UUID>()
            for edge in intraCategoryCandidates {
                guard let parentID = edge.hierarchyParentID,
                      let childID = edge.hierarchyChildID,
                      let parentRank = rankByID[parentID],
                      let childRank = rankByID[childID],
                      parentRank != childRank else { continue }

                guard !connectedChildren.contains(childID),
                      let parent = nodeMap[parentID],
                      let child = nodeMap[childID] else { continue }

                result.append(
                    GraphEdge(
                        id: UUID(),
                        from: parent.id,
                        to: child.id,
                        style: .solid,
                        color: colorForCategory(category).opacity(0.58),
                        strength: min(0.88, 0.28 + edge.strength),
                        isCrossDomain: false
                    )
                )
                connectedChildren.insert(childID)
            }
        }

        let bridgeCandidates = inferredEdges
            .filter { !$0.sameCategory && $0.strength >= 0.19 }
            .sorted { lhs, rhs in
                if lhs.strength == rhs.strength {
                    return edgeKey(lhs.from, lhs.to) < edgeKey(rhs.from, rhs.to)
                }
                return lhs.strength > rhs.strength
            }

        var bridgeDegree: [UUID: Int] = [:]
        var addedBridgeKeys = Set<String>()

        for edge in bridgeCandidates {
            guard let from = nodeMap[edge.from], let to = nodeMap[edge.to] else { continue }
            guard from.isBridge || to.isBridge || from.isHub || to.isHub else { continue }

            let key = edgeKey(edge.from, edge.to)
            guard !addedBridgeKeys.contains(key) else { continue }
            guard bridgeDegree[edge.from, default: 0] < 2, bridgeDegree[edge.to, default: 0] < 2 else { continue }
            guard canPlaceBridgeEdge(edge, existing: result, nodeMap: nodeMap) else { continue }

            result.append(
                GraphEdge(
                    id: UUID(),
                    from: edge.from,
                    to: edge.to,
                    style: .dotted,
                    color: Color.black.opacity(0.34),
                    strength: min(0.9, edge.strength),
                    isCrossDomain: true
                )
            )
            bridgeDegree[edge.from, default: 0] += 1
            bridgeDegree[edge.to, default: 0] += 1
            addedBridgeKeys.insert(key)
        }

        return result
    }

    private func relaxConstellationLayout(_ nodes: [VisNode]) -> [VisNode] {
        guard nodes.count > 1 else { return nodes }

        let originalPositions = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.position) })
        var positions = originalPositions
        let iterations = min(18, max(8, nodes.count / 2))

        for _ in 0..<iterations {
            var displacement = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, CGPoint.zero) })

            for index in nodes.indices {
                for nextIndex in nodes.indices where nextIndex > index {
                    let lhs = nodes[index]
                    let rhs = nodes[nextIndex]
                    let lhsPosition = positions[lhs.id] ?? lhs.position
                    let rhsPosition = positions[rhs.id] ?? rhs.position
                    let delta = lhsPosition - rhsPosition
                    let distance = max(length(of: delta), 0.001)
                    let minimumDistance = constellationMinimumDistance(between: lhs, and: rhs)
                    guard distance < minimumDistance else { continue }

                    let direction: CGPoint
                    if distance < 0.01 {
                        let seed = CGFloat(abs(edgeKey(lhs.id, rhs.id).hashValue % 360))
                        let angle = (seed / 180) * .pi
                        direction = CGPoint(x: cos(angle), y: sin(angle) * 0.86)
                    } else {
                        direction = normalized(delta)
                    }

                    let correction = direction * ((minimumDistance - distance) * 0.5)
                    displacement[lhs.id, default: .zero] = displacement[lhs.id, default: .zero] + correction * constellationMobility(for: lhs)
                    displacement[rhs.id, default: .zero] = displacement[rhs.id, default: .zero] - correction * constellationMobility(for: rhs)
                }
            }

            for node in nodes {
                let original = originalPositions[node.id] ?? node.position
                let current = positions[node.id] ?? node.position
                let spring = (original - current) * constellationAnchorStrength(for: node)
                displacement[node.id, default: .zero] = displacement[node.id, default: .zero] + spring
            }

            for node in nodes {
                let move = displacement[node.id, default: .zero]
                let limitedMove = normalized(move) * min(length(of: move), node.isHub ? 8 : 12)
                positions[node.id] = (positions[node.id] ?? node.position) + limitedMove
            }
        }

        return nodes.map { node in
            VisNode(
                id: node.id,
                title: node.title,
                categoryRaw: node.categoryRaw,
                position: positions[node.id] ?? node.position,
                isHub: node.isHub,
                isBridge: node.isBridge,
                isNewest: node.isNewest,
                bridgeStrength: node.bridgeStrength,
                relatedCategoryRaws: node.relatedCategoryRaws,
                labelOffset: node.labelOffset
            )
        }
    }

    private func constellationMinimumDistance(between lhs: VisNode, and rhs: VisNode) -> CGFloat {
        if lhs.categoryRaw != rhs.categoryRaw {
            if lhs.isBridge || rhs.isBridge {
                return 52
            }
            return 42
        }
        if lhs.isHub || rhs.isHub {
            return 48
        }
        if lhs.isBridge || rhs.isBridge {
            return 42
        }
        return 34
    }

    private func constellationMobility(for node: VisNode) -> CGFloat {
        if node.isHub { return 0.42 }
        if node.isBridge { return 0.82 }
        return 1.0
    }

    private func constellationAnchorStrength(for node: VisNode) -> CGFloat {
        if node.isHub { return 0.18 }
        if node.isBridge { return 0.11 }
        return 0.08
    }

    private func makeSeed(from node: LayoutNodeInput) -> LayoutSeed {
        let titleTokens = tokens(from: node.title)
        let mergedText = node.title + " " + node.contentPreview
        let textTokens = titleTokens.union(tokens(from: mergedText))
        let semanticTokens = textTokens.subtracting(lowSignalRelationTokens)

        return LayoutSeed(
            id: node.id,
            title: node.title,
            categoryRaw: node.category,
            titleTokens: titleTokens,
            textTokens: textTokens,
            semanticTokens: semanticTokens,
            abstractionScore: abstractionScore(for: mergedText),
            applicationScore: keywordScore(in: mergedText, keywords: applicationKeywords),
            exampleScore: keywordScore(in: mergedText, keywords: exampleKeywords)
        )
    }

    private func makeLayoutInput(from node: KnowledgeNode) -> LayoutNodeInput {
        LayoutNodeInput(
            id: node.id,
            title: node.title,
            contentPreview: String(node.content.prefix(140)),
            category: node.category,
            createdAt: node.createdAt
        )
    }

    private func inferEdges(from seeds: [LayoutSeed], mode: GraphLayoutMode) -> [InferredEdge] {
        guard seeds.count > 1 else { return [] }

        var candidates: [InferredEdge] = []
        let candidatePairs = mode == .pathway
            ? selectiveCandidatePairs(for: seeds)
            : exhaustiveCandidatePairs(for: seeds)

        for (lhsIndex, rhsIndex) in candidatePairs {
            let lhs = seeds[lhsIndex]
            let rhs = seeds[rhsIndex]
            let strength = similarity(between: lhs, and: rhs)
            if strength < 0.08 { continue }
            let hierarchy = lhs.categoryRaw == rhs.categoryRaw
                ? classifyHierarchy(between: lhs, and: rhs)
                : nil

            candidates.append(
                InferredEdge(
                    from: lhs.id,
                    to: rhs.id,
                    strength: strength,
                    sameCategory: lhs.categoryRaw == rhs.categoryRaw,
                    hierarchyKind: hierarchy?.kind,
                    hierarchyParentID: hierarchy?.parentID,
                    hierarchyChildID: hierarchy?.childID
                )
            )
        }

        if mode == .pathway && candidates.isEmpty {
            for (lhsIndex, rhsIndex) in exhaustiveCandidatePairs(for: seeds) {
                let lhs = seeds[lhsIndex]
                let rhs = seeds[rhsIndex]
                let strength = similarity(between: lhs, and: rhs)
                if strength < 0.08 { continue }
                let hierarchy = lhs.categoryRaw == rhs.categoryRaw
                    ? classifyHierarchy(between: lhs, and: rhs)
                    : nil

                candidates.append(
                    InferredEdge(
                        from: lhs.id,
                        to: rhs.id,
                        strength: strength,
                        sameCategory: lhs.categoryRaw == rhs.categoryRaw,
                        hierarchyKind: hierarchy?.kind,
                        hierarchyParentID: hierarchy?.parentID,
                        hierarchyChildID: hierarchy?.childID
                    )
                )
            }
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.strength == rhs.strength {
                return lhs.from.uuidString < rhs.from.uuidString
            }
            return lhs.strength > rhs.strength
        }

        var chosen: [InferredEdge] = []
        var degree: [UUID: Int] = [:]
        var seenKeys = Set<String>()
        let maxDegree = mode == .pathway ? 5 : 4
        let threshold: CGFloat = mode == .pathway ? 0.18 : 0.15

        for seed in seeds {
            if let best = sortedCandidates.first(where: { $0.from == seed.id || $0.to == seed.id }) {
                addEdge(best, to: &chosen, degree: &degree, seenKeys: &seenKeys, maxDegree: maxDegree, ignoreDegreeLimit: true)
            }
        }

        for candidate in sortedCandidates where candidate.strength >= threshold {
            addEdge(candidate, to: &chosen, degree: &degree, seenKeys: &seenKeys, maxDegree: maxDegree, ignoreDegreeLimit: false)
        }

        let desiredEdgeCount = max(seeds.count + 2, Int(CGFloat(seeds.count) * 1.6))
        for candidate in sortedCandidates where chosen.count < desiredEdgeCount {
            addEdge(candidate, to: &chosen, degree: &degree, seenKeys: &seenKeys, maxDegree: maxDegree + 1, ignoreDegreeLimit: false)
        }

        return chosen
    }

    private func addEdge(
        _ edge: InferredEdge,
        to chosen: inout [InferredEdge],
        degree: inout [UUID: Int],
        seenKeys: inout Set<String>,
        maxDegree: Int,
        ignoreDegreeLimit: Bool
    ) {
        let key = edgeKey(edge.from, edge.to)
        guard !seenKeys.contains(key) else { return }
        if !ignoreDegreeLimit {
            if degree[edge.from, default: 0] >= maxDegree || degree[edge.to, default: 0] >= maxDegree {
                return
            }
        }

        chosen.append(edge)
        seenKeys.insert(key)
        degree[edge.from, default: 0] += 1
        degree[edge.to, default: 0] += 1
    }

    private func makeNetworkLayout(
        seeds: [LayoutSeed],
        edges: [InferredEdge],
        bridgeProfiles: [UUID: BridgeProfile],
        mode: GraphLayoutMode,
        newestNodeID: UUID?
    ) -> [VisNode] {
        let weightedDegree = makeWeightedDegreeMap(from: edges)
        let hubIDs = hubIdentifiers(from: seeds, weightedDegree: weightedDegree, mode: mode)
        let sortedSeeds = seeds.sorted {
            if weightedDegree[$0.id, default: 0] == weightedDegree[$1.id, default: 0] {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return weightedDegree[$0.id, default: 0] > weightedDegree[$1.id, default: 0]
        }

        var positions: [UUID: CGPoint]
        if mode == .pathway {
            positions = makeFastPathwayPositions(
                seeds: sortedSeeds,
                edges: edges,
                weightedDegree: weightedDegree,
                hubIDs: hubIDs,
                bridgeProfiles: bridgeProfiles
            )
        } else {
            positions = makeInitialPositions(for: sortedSeeds, weightedDegree: weightedDegree, mode: mode)
            applyForceLayout(to: &positions, seeds: sortedSeeds, edges: edges, weightedDegree: weightedDegree, hubIDs: hubIDs, mode: mode)
        }
        normalizePositions(&positions, mode: mode)

        return sortedSeeds.map { seed in
            let position = positions[seed.id] ?? .zero
            let direction = normalized(position)

            return VisNode(
                id: seed.id,
                title: shortLabel(for: seed.title, maxLength: hubIDs.contains(seed.id) ? 11 : 10),
                categoryRaw: seed.categoryRaw,
                position: position,
                isHub: hubIDs.contains(seed.id),
                isBridge: bridgeProfiles[seed.id] != nil,
                isNewest: seed.id == newestNodeID,
                bridgeStrength: bridgeProfiles[seed.id]?.bridgeStrength ?? 0,
                relatedCategoryRaws: bridgeProfiles[seed.id]?.relatedCategories ?? [],
                labelOffset: CGSize(
                    width: direction.x * 10,
                    height: (hubIDs.contains(seed.id) ? 26 : 20) + max(0, direction.y) * 4
                )
            )
        }
    }

    private func makeWeightedDegreeMap(from edges: [InferredEdge]) -> [UUID: CGFloat] {
        var result: [UUID: CGFloat] = [:]
        for edge in edges {
            result[edge.from, default: 0] += edge.strength
            result[edge.to, default: 0] += edge.strength
        }
        return result
    }

    private func exhaustiveCandidatePairs(for seeds: [LayoutSeed]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for index in seeds.indices {
            for nextIndex in seeds.indices where nextIndex > index {
                result.append((index, nextIndex))
            }
        }
        return result
    }

    private func selectiveCandidatePairs(for seeds: [LayoutSeed]) -> [(Int, Int)] {
        var result = Set<String>()
        let indexedSeeds = Array(seeds.enumerated())
        var categoryBuckets: [String: [(Int, LayoutSeed)]] = [:]
        var tokenBuckets: [String: [Int]] = [:]

        for (index, seed) in indexedSeeds {
            categoryBuckets[seed.categoryRaw, default: []].append((index, seed))

            let prioritizedTokens = Array(
                seed.titleTokens
                    .union(seed.textTokens.filter { $0.count >= 4 })
                    .filter { $0.count >= 2 }
                    .sorted()
                    .prefix(10)
            )

            for token in prioritizedTokens {
                tokenBuckets[token, default: []].append(index)
            }
        }

        for (_, bucket) in categoryBuckets {
            let sortedBucket = bucket.sorted { lhs, rhs in
                if lhs.1.title == rhs.1.title {
                    return lhs.0 < rhs.0
                }
                return lhs.1.title.localizedStandardCompare(rhs.1.title) == .orderedAscending
            }

            for index in sortedBucket.indices {
                let upperBound = min(sortedBucket.count, index + 4)
                guard index + 1 < upperBound else { continue }
                for nextIndex in (index + 1)..<upperBound {
                    result.insert(pairKey(sortedBucket[index].0, sortedBucket[nextIndex].0))
                }
            }
        }

        for (_, bucket) in tokenBuckets where bucket.count >= 2 && bucket.count <= 16 {
            let sorted = bucket.sorted()
            for index in sorted.indices {
                let upperBound = min(sorted.count, index + 6)
                guard index + 1 < upperBound else { continue }
                for nextIndex in (index + 1)..<upperBound {
                    result.insert(pairKey(sorted[index], sorted[nextIndex]))
                }
            }
        }

        let sortedByDegree = indexedSeeds.sorted {
            let lhsScore = ($0.1.titleTokens.count + $0.1.textTokens.count)
            let rhsScore = ($1.1.titleTokens.count + $1.1.textTokens.count)
            if lhsScore == rhsScore {
                return $0.0 < $1.0
            }
            return lhsScore > rhsScore
        }

        let hubIndices = Array(sortedByDegree.prefix(min(6, sortedByDegree.count)).map(\.0))
        for index in seeds.indices {
            for hubIndex in hubIndices where hubIndex != index {
                result.insert(pairKey(index, hubIndex))
            }
        }

        return result.compactMap { key in
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let lhs = Int(parts[0]),
                  let rhs = Int(parts[1]) else { return nil }
            return (lhs, rhs)
        }
    }

    private func pairKey(_ lhs: Int, _ rhs: Int) -> String {
        lhs < rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
    }

    private func makeFastPathwayPositions(
        seeds: [LayoutSeed],
        edges: [InferredEdge],
        weightedDegree: [UUID: CGFloat],
        hubIDs: Set<UUID>,
        bridgeProfiles: [UUID: BridgeProfile]
    ) -> [UUID: CGPoint] {
        let maxDegree = max(weightedDegree.values.max() ?? 1, 1)
        let grouped = Dictionary(grouping: seeds, by: \.categoryRaw)
        var positions: [UUID: CGPoint] = [:]

        for category in KnowledgeCategory.allCases.map(\.rawValue) {
            let categorySeeds = (grouped[category] ?? []).sorted {
                let lhsScore = weightedDegree[$0.id, default: 0]
                let rhsScore = weightedDegree[$1.id, default: 0]
                if lhsScore == rhsScore {
                    return $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
                return lhsScore > rhsScore
            }

            guard !categorySeeds.isEmpty else { continue }
            let anchorAngle = pathwayCategoryAngles[category] ?? 0
            let direction = normalized(CGPoint(x: cos(anchorAngle), y: sin(anchorAngle) * 0.84))
            let tangent = normalized(CGPoint(x: -direction.y, y: direction.x))
            let anchor = direction * 164

            for (index, seed) in categorySeeds.enumerated() {
                let centrality = weightedDegree[seed.id, default: 0] / maxDegree
                let lane = index == 0 ? 0 : (index % 2 == 0 ? 1 : -1)
                let tier = CGFloat(index / 2)
                let radialDistance = hubIDs.contains(seed.id)
                    ? 94 - centrality * 18
                    : 140 + tier * 34 - centrality * 20
                let lateralOffset = index == 0 ? 0 : CGFloat(lane) * (24 + tier * 10)
                var position = direction * radialDistance + tangent * lateralOffset + anchor * 0.18

                if let bridge = bridgeProfiles[seed.id] {
                    let bridgeDirection = normalized(CGPoint(x: cos(bridge.averageAngle), y: sin(bridge.averageAngle) * 0.84))
                    let blend = min(0.62, 0.22 + bridge.bridgeStrength * 0.34)
                    let bridgeTarget = bridgeDirection * (radialDistance * (hubIDs.contains(seed.id) ? 0.86 : 0.92))
                    position = position * (1 - blend) + bridgeTarget * blend
                }

                positions[seed.id] = position
            }
        }

        relaxPathwayLayout(
            positions: &positions,
            seeds: seeds,
            edges: edges,
            weightedDegree: weightedDegree,
            hubIDs: hubIDs
        )
        return positions
    }

    private func relaxPathwayLayout(
        positions: inout [UUID: CGPoint],
        seeds: [LayoutSeed],
        edges: [InferredEdge],
        weightedDegree: [UUID: CGFloat],
        hubIDs: Set<UUID>
    ) {
        guard seeds.count > 1 else { return }

        let maxDegree = max(weightedDegree.values.max() ?? 1, 1)
        let neighborsByID = Dictionary(grouping: edges.flatMap { [($0.from, $0), ($0.to, $0)] }, by: \.0)
        let iterations = min(22, max(10, seeds.count / 10))

        for _ in 0..<iterations {
            var next = positions

            for seed in seeds {
                let current = positions[seed.id] ?? .zero
                let anchorAngle = pathwayCategoryAngles[seed.categoryRaw] ?? 0
                let anchor = CGPoint(
                    x: cos(anchorAngle) * 148,
                    y: sin(anchorAngle) * 148 * 0.84
                )
                let centrality = weightedDegree[seed.id, default: 0] / maxDegree
                var candidate = current * 0.74 + anchor * (hubIDs.contains(seed.id) ? 0.16 : 0.11 + centrality * 0.05)

                if let incident = neighborsByID[seed.id], !incident.isEmpty {
                    let neighborPoints = incident.compactMap { pair -> CGPoint? in
                        let edge = pair.1
                        let otherID = edge.from == seed.id ? edge.to : edge.from
                        return positions[otherID]
                    }
                    if !neighborPoints.isEmpty {
                        let centroid = neighborPoints.reduce(CGPoint.zero, +) * (1 / CGFloat(neighborPoints.count))
                        candidate = candidate * 0.72 + centroid * 0.28
                    }
                }

                next[seed.id] = candidate
            }

            for category in KnowledgeCategory.allCases.map(\.rawValue) {
                let categorySeeds = seeds.filter { $0.categoryRaw == category }
                guard categorySeeds.count > 1 else { continue }
                let anchorAngle = pathwayCategoryAngles[category] ?? 0
                let tangent = normalized(CGPoint(x: -sin(anchorAngle), y: cos(anchorAngle)))
                let sorted = categorySeeds.sorted {
                    let lhsProjection = dot(next[$0.id] ?? .zero, tangent)
                    let rhsProjection = dot(next[$1.id] ?? .zero, tangent)
                    return lhsProjection < rhsProjection
                }

                for index in 1..<sorted.count {
                    let previousID = sorted[index - 1].id
                    let currentID = sorted[index].id
                    guard let previousPoint = next[previousID],
                          let currentPoint = next[currentID] else { continue }
                    let delta = currentPoint - previousPoint
                    let distance = length(of: delta)
                    let minimumDistance: CGFloat = 28
                    guard distance < minimumDistance else { continue }

                    let direction = normalized(delta == .zero ? tangent : delta)
                    let correction = direction * ((minimumDistance - distance) * 0.5)
                    next[previousID] = previousPoint - correction
                    next[currentID] = currentPoint + correction
                }
            }

            positions = next
        }
    }

    private func hubIdentifiers(from seeds: [LayoutSeed], weightedDegree: [UUID: CGFloat], mode: GraphLayoutMode) -> Set<UUID> {
        let sorted = seeds.sorted {
            weightedDegree[$0.id, default: 0] > weightedDegree[$1.id, default: 0]
        }
        let count = min(max(1, seeds.count / (mode == .pathway ? 4 : 5)), 4)
        return Set(sorted.prefix(count).map(\.id))
    }

    private func makeInitialPositions(
        for seeds: [LayoutSeed],
        weightedDegree: [UUID: CGFloat],
        mode: GraphLayoutMode
    ) -> [UUID: CGPoint] {
        let maxDegree = max(weightedDegree.values.max() ?? 1, 1)
        let baseRadius: CGFloat = mode == .pathway ? 210 : 240
        var result: [UUID: CGPoint] = [:]

        for (index, seed) in seeds.enumerated() {
            let rankAngle = (CGFloat(index) / CGFloat(max(seeds.count, 1))) * .pi * 2
            let anchorAngle = pathwayCategoryAngles[seed.categoryRaw] ?? rankAngle
            let jitter = angleJitter(for: seed.id)
            let angle = rankAngle * 0.55 + anchorAngle * 0.45 + jitter
            let centrality = weightedDegree[seed.id, default: 0] / maxDegree
            let radius = baseRadius - centrality * (mode == .pathway ? 118 : 88)

            result[seed.id] = CGPoint(
                x: cos(angle) * radius,
                y: sin(angle) * radius * 0.84
            )
        }

        return result
    }

    private func applyForceLayout(
        to positions: inout [UUID: CGPoint],
        seeds: [LayoutSeed],
        edges: [InferredEdge],
        weightedDegree: [UUID: CGFloat],
        hubIDs: Set<UUID>,
        mode: GraphLayoutMode
    ) {
        guard seeds.count > 1 else { return }

        let maxDegree = max(weightedDegree.values.max() ?? 1, 1)
        let iterations = mode == .pathway ? 220 : 190
        var temperature: CGFloat = mode == .pathway ? 22 : 28
        let minimumDistance: CGFloat = mode == .pathway ? 42 : 48
        let repulsionStrength: CGFloat = mode == .pathway ? 5400 : 6400

        for _ in 0..<iterations {
            var displacement = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, CGPoint.zero) })

            for index in seeds.indices {
                for nextIndex in seeds.indices where nextIndex > index {
                    let lhs = seeds[index]
                    let rhs = seeds[nextIndex]
                    let lhsPosition = positions[lhs.id] ?? .zero
                    let rhsPosition = positions[rhs.id] ?? .zero
                    let delta = lhsPosition - rhsPosition
                    let distance = max(length(of: delta), 1)
                    let direction = normalized(delta)
                    let overlap = max(0, minimumDistance - distance)
                    let force = (repulsionStrength / (distance * distance)) + overlap * 1.35

                    displacement[lhs.id, default: .zero] = displacement[lhs.id, default: .zero] + direction * force
                    displacement[rhs.id, default: .zero] = displacement[rhs.id, default: .zero] - direction * force
                }
            }

            for edge in edges {
                let fromPosition = positions[edge.from] ?? .zero
                let toPosition = positions[edge.to] ?? .zero
                let delta = toPosition - fromPosition
                let distance = max(length(of: delta), 1)
                let direction = normalized(delta)
                let targetLength: CGFloat = edge.sameCategory
                    ? (mode == .pathway ? 104 : 118)
                    : max(92, (mode == .pathway ? 128 : 144) - edge.strength * 26)
                let springForce = (distance - targetLength) * (edge.sameCategory ? 0.092 : 0.082) * (0.78 + edge.strength)

                displacement[edge.from, default: .zero] = displacement[edge.from, default: .zero] + direction * springForce
                displacement[edge.to, default: .zero] = displacement[edge.to, default: .zero] - direction * springForce
            }

            for seed in seeds {
                let position = positions[seed.id] ?? .zero
                let anchorAngle = pathwayCategoryAngles[seed.categoryRaw] ?? 0
                let anchorRadius: CGFloat = mode == .pathway ? 148 : 176
                let anchor = CGPoint(
                    x: cos(anchorAngle) * anchorRadius,
                    y: sin(anchorAngle) * anchorRadius * 0.84
                )
                let centrality = weightedDegree[seed.id, default: 0] / maxDegree
                let anchorPull = (anchor - position) * (mode == .pathway ? 0.008 : 0.006)
                let centerPull = (CGPoint.zero - position) * ((hubIDs.contains(seed.id) ? 0.024 : 0.008) + centrality * 0.014)
                displacement[seed.id, default: .zero] = displacement[seed.id, default: .zero] + anchorPull + centerPull
            }

            for seed in seeds {
                let move = displacement[seed.id, default: .zero]
                let moveLength = length(of: move)
                guard moveLength > 0 else { continue }

                let limitedMove = normalized(move) * min(moveLength, temperature)
                positions[seed.id] = (positions[seed.id] ?? .zero) + limitedMove
            }

            temperature *= 0.984
        }
    }

    private func normalizePositions(_ positions: inout [UUID: CGPoint], mode: GraphLayoutMode) {
        let points = Array(positions.values)
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return }

        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let targetWidth: CGFloat = mode == .pathway ? 300 : 330
        let targetHeight: CGFloat = mode == .pathway ? 430 : 500
        let scale = min(targetWidth / width, targetHeight / height)
        let midX = (minX + maxX) * 0.5
        let midY = (minY + maxY) * 0.5

        for key in positions.keys {
            let point = positions[key] ?? .zero
            positions[key] = CGPoint(
                x: (point.x - midX) * scale,
                y: (point.y - midY) * scale
            )
        }
    }

    private func similarity(between lhs: LayoutSeed, and rhs: LayoutSeed) -> CGFloat {
        let titleOverlap = overlap(lhs.titleTokens, rhs.titleTokens)
        let textOverlap = overlap(lhs.textTokens, rhs.textTokens)
        let semanticOverlap = overlap(lhs.semanticTokens, rhs.semanticTokens)
        let categoryBonus: CGFloat = lhs.categoryRaw == rhs.categoryRaw ? 0.24 : -0.03
        let sharedSignal: CGFloat = titleOverlap > 0 || semanticOverlap > 0 ? 0.08 : 0.0
        let crossDomainBonus: CGFloat = lhs.categoryRaw == rhs.categoryRaw ? 0.0 : min(0.18, semanticOverlap * 0.54 + titleOverlap * 0.24)

        if lhs.categoryRaw == rhs.categoryRaw && titleOverlap == 0 && semanticOverlap < 0.12 {
            return 0
        }

        let relationBonus: CGFloat
        if lhs.categoryRaw == rhs.categoryRaw, let hierarchy = classifyHierarchy(between: lhs, and: rhs) {
            switch hierarchy.kind {
            case .prerequisite:
                relationBonus = 0.12
            case .application:
                relationBonus = 0.09
            case .example:
                relationBonus = 0.06
            }
        } else {
            relationBonus = 0
        }

        return min(0.96, max(0, titleOverlap * 0.44 + textOverlap * 0.16 + semanticOverlap * 0.3 + categoryBonus + sharedSignal + crossDomainBonus + relationBonus))
    }

    private func classifyHierarchy(between lhs: LayoutSeed, and rhs: LayoutSeed) -> (parentID: UUID, childID: UUID, kind: HierarchyKind)? {
        let sharedSemanticTokens = lhs.semanticTokens.intersection(rhs.semanticTokens)
        guard !sharedSemanticTokens.isEmpty || overlap(lhs.titleTokens, rhs.titleTokens) >= 0.2 else {
            return nil
        }

        if lhs.exampleScore > rhs.exampleScore + 0.12 {
            return (rhs.id, lhs.id, .example)
        }
        if rhs.exampleScore > lhs.exampleScore + 0.12 {
            return (lhs.id, rhs.id, .example)
        }

        if lhs.applicationScore > rhs.applicationScore + 0.12 && rhs.abstractionScore > lhs.abstractionScore + 0.08 {
            return (rhs.id, lhs.id, .application)
        }
        if rhs.applicationScore > lhs.applicationScore + 0.12 && lhs.abstractionScore > rhs.abstractionScore + 0.08 {
            return (lhs.id, rhs.id, .application)
        }

        if lhs.abstractionScore > rhs.abstractionScore + 0.14 {
            return (lhs.id, rhs.id, .prerequisite)
        }
        if rhs.abstractionScore > lhs.abstractionScore + 0.14 {
            return (rhs.id, lhs.id, .prerequisite)
        }

        return nil
    }

    private func abstractionScore(for text: String) -> CGFloat {
        keywordScore(in: text, keywords: foundationalKeywords) - keywordScore(in: text, keywords: exampleKeywords) * 0.6
    }

    private func keywordScore(in text: String, keywords: Set<String>) -> CGFloat {
        let normalizedText = text.lowercased()
        let matches = keywords.reduce(into: 0) { partialResult, keyword in
            if normalizedText.contains(keyword.lowercased()) {
                partialResult += 1
            }
        }
        guard matches > 0 else { return 0 }
        return min(1, CGFloat(matches) * 0.22)
    }

    private func overlap(_ lhs: Set<String>, _ rhs: Set<String>) -> CGFloat {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersection = lhs.intersection(rhs).count
        guard intersection > 0 else { return 0 }
        return CGFloat(intersection * 2) / CGFloat(lhs.count + rhs.count)
    }

    private func tokens(from text: String) -> Set<String> {
        let lowercased = text.lowercased()
        let words = lowercased
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !stopWords.contains($0) }

        var tokens = Set(words)
        let compactScalars = lowercased.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || isCJK(scalar)
        }
        let compactCharacters = compactScalars.map(Character.init)

        if compactCharacters.count == 1 {
            tokens.insert(String(compactCharacters))
        }

        if compactCharacters.count >= 2 {
            for index in 0..<(compactCharacters.count - 1) {
                tokens.insert(String(compactCharacters[index...index + 1]))
            }
        }

        if compactCharacters.count >= 3 {
            for index in 0..<(compactCharacters.count - 2) {
                tokens.insert(String(compactCharacters[index...index + 2]))
            }
        }

        return tokens
    }

    private func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private func nodeCategory(for id: UUID, in nodes: [VisNode]) -> String {
        nodes.first(where: { $0.id == id })?.categoryRaw ?? ""
    }

    private func bridgeProfiles(from edges: [InferredEdge], seeds: [LayoutSeed]) -> [UUID: BridgeProfile] {
        let categoryByID = Dictionary(uniqueKeysWithValues: seeds.map { ($0.id, $0.categoryRaw) })
        var categoryStrengths: [UUID: [String: CGFloat]] = [:]

        for edge in edges where !edge.sameCategory && edge.strength >= 0.18 {
            guard let fromCategory = categoryByID[edge.from], let toCategory = categoryByID[edge.to] else { continue }
            categoryStrengths[edge.from, default: [:]][toCategory, default: 0] += edge.strength
            categoryStrengths[edge.to, default: [:]][fromCategory, default: 0] += edge.strength
        }

        var result: [UUID: BridgeProfile] = [:]
        for seed in seeds {
            let categoryMap = categoryStrengths[seed.id, default: [:]]
            let sorted = categoryMap.sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            guard let strongest = sorted.first, strongest.value >= 0.2 else { continue }

            let relatedCategories = Array(sorted.prefix(2).map(\.key))
            let allAngles = ([seed.categoryRaw] + relatedCategories).compactMap { pathwayCategoryAngles[$0] }
            guard !allAngles.isEmpty else { continue }
            let averageAngle = circularAverage(of: allAngles)
            let totalStrength = sorted.prefix(2).reduce(CGFloat.zero) { partial, item in
                partial + item.value
            }

            result[seed.id] = BridgeProfile(
                nodeID: seed.id,
                relatedCategories: relatedCategories,
                averageAngle: averageAngle,
                bridgeStrength: min(1, totalStrength / 0.9)
            )
        }

        return result
    }

    private func edgeKey(_ lhs: UUID, _ rhs: UUID) -> String {
        lhs.uuidString < rhs.uuidString ? "\(lhs.uuidString)|\(rhs.uuidString)" : "\(rhs.uuidString)|\(lhs.uuidString)"
    }

    private func angleJitter(for id: UUID) -> CGFloat {
        let value = id.uuidString.unicodeScalars.reduce(0) { partialResult, scalar in
            partialResult + Int(scalar.value)
        }
        return CGFloat((value % 23) - 11) * 0.018
    }

    private func circularAverage(of angles: [CGFloat]) -> CGFloat {
        let vector = angles.reduce(CGPoint.zero) { partialResult, angle in
            partialResult + CGPoint(x: cos(angle), y: sin(angle))
        }
        return atan2(vector.y, vector.x)
    }

    private func mixedColor(from lhs: Color, to rhs: Color) -> Color {
        let uiLHS = UIColor(lhs)
        let uiRHS = UIColor(rhs)
        var lR: CGFloat = 0
        var lG: CGFloat = 0
        var lB: CGFloat = 0
        var lA: CGFloat = 0
        var rR: CGFloat = 0
        var rG: CGFloat = 0
        var rB: CGFloat = 0
        var rA: CGFloat = 0
        uiLHS.getRed(&lR, green: &lG, blue: &lB, alpha: &lA)
        uiRHS.getRed(&rR, green: &rG, blue: &rB, alpha: &rA)

        return Color(
            red: (lR + rR) * 0.5,
            green: (lG + rG) * 0.5,
            blue: (lB + rB) * 0.5,
            opacity: (lA + rA) * 0.5
        )
    }

    private func canPlaceBridgeEdge(
        _ candidate: InferredEdge,
        existing: [GraphEdge],
        nodeMap: [UUID: VisNode]
    ) -> Bool {
        guard let candidateFrom = nodeMap[candidate.from],
              let candidateTo = nodeMap[candidate.to] else { return false }

        for edge in existing {
            if edge.from == candidate.from || edge.from == candidate.to || edge.to == candidate.from || edge.to == candidate.to {
                continue
            }
            guard let existingFrom = nodeMap[edge.from],
                  let existingTo = nodeMap[edge.to] else { continue }
            if segmentsIntersect(candidateFrom.position, candidateTo.position, existingFrom.position, existingTo.position) {
                return false
            }
        }

        return true
    }

    private func segmentsIntersect(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        let denominator = (b.x - a.x) * (d.y - c.y) - (b.y - a.y) * (d.x - c.x)
        if abs(denominator) < 0.001 { return false }

        let numerator1 = (a.y - c.y) * (d.x - c.x) - (a.x - c.x) * (d.y - c.y)
        let numerator2 = (a.y - c.y) * (b.x - a.x) - (a.x - c.x) * (b.y - a.y)
        let t = numerator1 / denominator
        let u = numerator2 / denominator

        return t > 0.08 && t < 0.92 && u > 0.08 && u < 0.92
    }

    private func length(of point: CGPoint) -> CGFloat {
        sqrt(point.x * point.x + point.y * point.y)
    }

    private func dot(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        lhs.x * rhs.x + lhs.y * rhs.y
    }

    private func normalized(_ point: CGPoint) -> CGPoint {
        let magnitude = max(length(of: point), 0.001)
        return CGPoint(x: point.x / magnitude, y: point.y / magnitude)
    }

    private func shortLabel(for text: String, maxLength: Int) -> String {
        text.count > maxLength ? String(text.prefix(maxLength)) + "…" : text
    }
}

private func + (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint {
    CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func * (lhs: CGPoint, rhs: CGFloat) -> CGPoint {
    CGPoint(x: lhs.x * rhs, y: lhs.y * rhs)
}

struct InteractiveGraphView: View {
    var nodes: [KnowledgeNode]
    var totalNodeCount: Int
    var onSelectCategory: ((KnowledgeCategory) -> Void)? = nil

    @EnvironmentObject private var regionUI: RegionUIStore
    @StateObject private var engine = GraphLayoutEngine()
    @State private var selectedNode: KnowledgeNode?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isGraphReady = false
    @State private var nodeOpacity = 0.0
    @State private var edgeOpacity = 0.0
    @State private var transitionMaskOpacity = 0.0
    @State private var contentScale: CGFloat = 1.0
    @State private var contentBlur: CGFloat = 0.0
    @State private var showPathwayHint = false
    @State private var isArrangingPathway = false
    @State private var loadingPulse = false
    @State private var loadingSweep = false
    @State private var loadingHalo = false
    @State private var revealSequenceID = UUID()
    @State private var layoutMode: GraphLayoutMode = .constellation
    @State private var newestPulse = false

    private var newestNode: KnowledgeNode? {
        nodes.max { lhs, rhs in
            lhs.createdAt < rhs.createdAt
        }
    }

    private var graphSignature: [GraphNodeSignature] {
        nodes.map { node in
            GraphNodeSignature(
                id: node.id,
                title: node.title,
                contentPreview: String(node.content.prefix(140)),
                category: node.category,
                createdAt: node.createdAt
            )
        }
    }

    private var isShowingSubsetNotice: Bool {
        totalNodeCount > nodes.count
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                Canvas { context, size in
                    context.translateBy(x: size.width / 2 + offset.width, y: size.height / 2 + offset.height)
                    context.scaleBy(x: scale, y: scale)

                    drawCategoryGuides(in: &context)
                    drawEdges(in: &context)
                    drawNodes(in: &context)
                }
                .gesture(dragGesture)
                .gesture(magnificationGesture)
                .onTapGesture(coordinateSpace: .local) { location in
                    handleTap(at: location, in: geometry.size)
                }
                .opacity(isGraphReady ? 1.0 : 0.0)
                .scaleEffect(contentScale)
                .blur(radius: contentBlur)

                categoryTapTargets(in: geometry.size)

                transitionMask
                    .opacity(transitionMaskOpacity)

                centerPathwayDock(in: geometry.size)
                    .opacity(showPathwayHint ? 1.0 : 0.0)
                    .scaleEffect(showPathwayHint ? 1.0 : 0.96)

                latestNodeBanner

                graphSubsetBanner
            }
            .sheet(item: $selectedNode) { node in
                NodeDetailView(node: node)
            }
            .task(id: graphSignature) {
                engine.sync(with: nodes, mode: layoutMode, newestNodeID: newestNode?.id)
                beginRevealSequence(hasContent: !nodes.isEmpty)
            }
            .onAppear {

                if !loadingPulse {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        loadingPulse = true
                    }
                }
                if !loadingSweep {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                        loadingSweep = true
                    }
                }
                if !loadingHalo {
                    withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        loadingHalo = true
                    }
                }
                if !newestPulse {
                    withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                        newestPulse = true
                    }
                }
            }
        }
    }

    private var graphSubsetBanner: some View {
        VStack {
            Spacer()

            if isShowingSubsetNotice {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.caption.weight(.semibold))
                    Text(regionUI.copy.graphSubsetNotice(shown: nodes.count, total: totalNodeCount))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.06), radius: 12, y: 8)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private func drawEdges(in context: inout GraphicsContext) {
        let nodeMap = Dictionary(uniqueKeysWithValues: engine.visNodes.map { ($0.id, $0) })

        for edge in engine.edges {
            guard let from = nodeMap[edge.from], let to = nodeMap[edge.to] else { continue }

            var path = Path()
            path.move(to: from.position)
            path.addLine(to: to.position)

            let strokeStyle = StrokeStyle(
                lineWidth: edge.style == .solid
                    ? 1.1 + edge.strength * (edge.isCrossDomain ? 1.7 : 1.4)
                    : (edge.style == .dotted ? 1.2 + edge.strength * 0.5 : 0.9 + edge.strength * 0.7),
                dash: {
                    switch edge.style {
                    case .solid:
                        return []
                    case .dashed:
                        return [4, 6]
                    case .dotted:
                        return [1.2, 6.2]
                    }
                }()
            )
            context.stroke(path, with: .color(edge.color.opacity(edgeOpacity)), style: strokeStyle)

            if edge.style == .solid || edge.isCrossDomain {
                let midpoint = CGPoint(x: (from.position.x + to.position.x) * 0.5, y: (from.position.y + to.position.y) * 0.5)
                let dotSize: CGFloat = edge.isCrossDomain ? 3.2 : 2.2
                let dot = CGRect(x: midpoint.x - dotSize * 0.5, y: midpoint.y - dotSize * 0.5, width: dotSize, height: dotSize)
                context.fill(Path(ellipseIn: dot), with: .color(edge.color.opacity(edgeOpacity * (edge.isCrossDomain ? 0.5 : 0.36))))
            }
        }
    }

    private func drawCategoryGuides(in context: inout GraphicsContext) {
        guard layoutMode == .constellation else { return }

        let grouped = Dictionary(grouping: engine.visNodes, by: \.categoryRaw)

        for (category, anchor) in engine.categoryAnchors {
            let hub = grouped[category]?.first(where: \.isHub)
            let anchorLength = max(hypot(anchor.x, anchor.y), 0.001)
            let direction = anchor == .zero
                ? CGPoint(x: 0, y: -1)
                : CGPoint(x: anchor.x / anchorLength, y: anchor.y / anchorLength)
            let labelPoint = anchor + direction * 18

            var trunk = Path()
            trunk.move(to: .zero)
            trunk.addLine(to: hub?.position ?? anchor)
            context.stroke(
                trunk,
                with: .color(colorForCategory(category).opacity(edgeOpacity * 0.22)),
                style: StrokeStyle(lineWidth: 1.6, dash: [10, 7])
            )

            if onSelectCategory == nil {
                let label = Text(localizedCategoryName(for: category))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(colorForCategory(category).opacity(nodeOpacity * 0.92))

                context.draw(context.resolve(label), at: labelPoint, anchor: .center)
            }
        }
    }

    private func nodeSize(for node: VisNode) -> CGFloat {
        switch layoutMode {
        case .constellation:
            if node.isHub { return 24 }
            if node.isBridge { return 20 }
            return 15
        case .pathway:
            return node.isHub ? 22 : 17
        }
    }

    private func drawNodes(in context: inout GraphicsContext) {
        for node in engine.visNodes {
            switch layoutMode {
            case .constellation:
                drawConstellationNode(node, in: &context)
            case .pathway:
                drawPathwayNode(node, in: &context)
            }
        }
    }

    private func drawConstellationNode(_ node: VisNode, in context: inout GraphicsContext) {
        let size = nodeSize(for: node)
        let rect = CGRect(x: node.position.x - size * 0.5, y: node.position.y - size * 0.5, width: size, height: size)

        if node.isNewest {
            drawNewestHighlight(for: node, size: size, in: &context)
        }

        if node.isHub {
            let haloRect = rect.insetBy(dx: -7, dy: -7)
            context.fill(Path(ellipseIn: haloRect), with: .color(node.color.opacity(nodeOpacity * 0.14)))
        } else if node.isBridge {
            let haloRect = rect.insetBy(dx: -5, dy: -5)
            context.fill(Path(ellipseIn: haloRect), with: .color(node.color.opacity(nodeOpacity * 0.1)))
        }

        if node.isBridge {
            drawBridgeRelationHalo(for: node, size: size, in: &context)
        }

        context.fill(Path(ellipseIn: rect), with: .color(node.color.opacity(nodeOpacity)))
        context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(nodeOpacity * 0.18)), lineWidth: 0.8)

        if shouldShowLabel(for: node) {
            drawLabel(for: node, in: &context, fontSize: labelFontSize(for: node))
        }
    }

    private func drawPathwayNode(_ node: VisNode, in context: inout GraphicsContext) {
        let fillColor = node.color.opacity(nodeOpacity)
        let size = nodeSize(for: node)
        let shapePath = Path(ellipseIn: CGRect(
            x: node.position.x - size * 0.5,
            y: node.position.y - size * 0.5,
            width: size,
            height: size
        ))

        if node.isNewest {
            drawNewestHighlight(for: node, size: size, in: &context)
        }

        if node.isHub {
            let haloPath = Path(ellipseIn: CGRect(
                x: node.position.x - size * 0.5 - 6,
                y: node.position.y - size * 0.5 - 6,
                width: size + 12,
                height: size + 12
            ))
            context.fill(haloPath, with: .color(node.color.opacity(nodeOpacity * 0.12)))
        }

        if node.isBridge {
            drawBridgeRelationHalo(for: node, size: size, in: &context)
        }

        context.fill(shapePath, with: .color(fillColor))
        context.stroke(shapePath, with: .color(Color.white.opacity(nodeOpacity * 0.16)), lineWidth: 0.75)

        if shouldShowLabel(for: node) {
            drawLabel(for: node, in: &context, fontSize: labelFontSize(for: node))
        }
    }

    private func drawLabel(for node: VisNode, in context: inout GraphicsContext, fontSize: CGFloat) {
        let labelPoint = CGPoint(
            x: node.position.x + node.labelOffset.width,
            y: node.position.y + node.labelOffset.height
        )
        let metrics = labelMetrics(for: node, fontSize: fontSize)
        let rect = CGRect(
            x: labelPoint.x - metrics.width * 0.5,
            y: labelPoint.y - metrics.height * 0.5,
            width: metrics.width,
            height: metrics.height
        )

        context.fill(
            Path(roundedRect: rect, cornerRadius: 7),
            with: .color(Color(.systemBackground).opacity(layoutMode == .constellation ? 0.66 : 0.58))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 7),
            with: .color(Color.white.opacity(nodeOpacity * 0.09)),
            lineWidth: 0.6
        )

        let label = Text(node.title)
            .font(.system(size: fontSize, weight: node.isHub || node.isBridge ? .semibold : .medium, design: .rounded))
            .foregroundColor(.primary.opacity(nodeOpacity * 0.94))
        let titlePoint = CGPoint(
            x: labelPoint.x,
            y: labelPoint.y - (node.relatedCategoryRaws.isEmpty ? 0 : 6)
        )
        context.draw(context.resolve(label), at: titlePoint, anchor: .center)

        if !node.relatedCategoryRaws.isEmpty {
            drawBridgeBadges(for: node, in: &context, rect: rect)
        }

        if node.isNewest {
            let badgePoint = CGPoint(
                x: rect.maxX - 8,
                y: rect.minY - 8
            )
            let badge = Text(regionUI.copy.newestBadge)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(.black.opacity(0.85))
            let badgeRect = CGRect(x: badgePoint.x - 16, y: badgePoint.y - 8, width: 32, height: 16)
            context.fill(Path(roundedRect: badgeRect, cornerRadius: 8), with: .color(Color(red: 1.0, green: 0.86, blue: 0.34).opacity(nodeOpacity)))
            context.draw(context.resolve(badge), at: badgePoint, anchor: .center)
        }
    }

    private func shouldShowLabel(for node: VisNode) -> Bool {
        if node.isNewest {
            return true
        }
        let visibleIDs = preferredLabelIDs(scale: scale)
        return visibleIDs.contains(node.id)
    }

    private func preferredLabelIDs(scale: CGFloat) -> Set<UUID> {
        if engine.visNodes.count <= 14 || scale >= 1.42 {
            return Set(engine.visNodes.map(\.id))
        }

        let sortedNodes = engine.visNodes.sorted { lhs, rhs in
            let lhsPriority = labelPriority(for: lhs)
            let rhsPriority = labelPriority(for: rhs)
            if lhsPriority == rhsPriority {
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return lhsPriority > rhsPriority
        }

        let collisionThresholdX: CGFloat
        let collisionThresholdY: CGFloat
        if scale >= 1.5 {
            collisionThresholdX = 0
            collisionThresholdY = 0
        } else if scale >= 1.28 {
            collisionThresholdX = 4
            collisionThresholdY = 2
        } else if scale >= 1.15 {
            collisionThresholdX = 8
            collisionThresholdY = 4
        } else {
            collisionThresholdX = 12
            collisionThresholdY = 6
        }

        var selected: [(id: UUID, rect: CGRect)] = []
        var result = Set<UUID>()
        for node in sortedNodes {
            let rect = labelRect(
                for: node,
                fontSize: labelFontSize(for: node),
                horizontalPadding: collisionThresholdX,
                verticalPadding: collisionThresholdY
            )
            let overlaps = selected.contains { existing in
                existing.rect.intersects(rect)
            }

            if !overlaps {
                selected.append((node.id, rect))
                result.insert(node.id)
            }
        }

        return result
    }

    private func labelFontSize(for node: VisNode) -> CGFloat {
        switch layoutMode {
        case .constellation:
            return node.isHub ? 11.5 : (node.isBridge ? 10.5 : 9.5)
        case .pathway:
            return node.isHub ? 10.5 : 9.25
        }
    }

    private func labelRect(
        for node: VisNode,
        fontSize: CGFloat,
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0
    ) -> CGRect {
        let labelPoint = CGPoint(
            x: node.position.x + node.labelOffset.width,
            y: node.position.y + node.labelOffset.height
        )
        let metrics = labelMetrics(for: node, fontSize: fontSize)
        return CGRect(
            x: labelPoint.x - metrics.width * 0.5 - horizontalPadding,
            y: labelPoint.y - metrics.height * 0.5 - verticalPadding,
            width: metrics.width + horizontalPadding * 2,
            height: metrics.height + verticalPadding * 2
        )
    }

    private func labelPriority(for node: VisNode) -> CGFloat {
        if node.isNewest { return 4.2 }
        if node.isHub { return 3.2 }
        if node.isBridge { return 2.3 + node.bridgeStrength }
        return 1.0
    }

    private func drawNewestHighlight(for node: VisNode, size: CGFloat, in context: inout GraphicsContext) {
        let warmHighlight = Color(red: 1.0, green: 0.84, blue: 0.24)
        let outerInset = newestPulse ? 12.0 : 8.0
        let outerOpacity = newestPulse ? 0.32 : 0.2
        let outerRect = CGRect(
            x: node.position.x - size * 0.5 - outerInset,
            y: node.position.y - size * 0.5 - outerInset,
            width: size + outerInset * 2,
            height: size + outerInset * 2
        )
        let innerRect = CGRect(
            x: node.position.x - size * 0.5 - 4,
            y: node.position.y - size * 0.5 - 4,
            width: size + 8,
            height: size + 8
        )

        context.fill(Path(ellipseIn: outerRect), with: .color(warmHighlight.opacity(nodeOpacity * outerOpacity)))
        context.stroke(Path(ellipseIn: innerRect), with: .color(warmHighlight.opacity(nodeOpacity * 0.88)), lineWidth: 1.4)
    }

    private func drawBridgeRelationHalo(for node: VisNode, size: CGFloat, in context: inout GraphicsContext) {
        guard !node.relatedCategoryRaws.isEmpty else { return }

        let orbitRect = CGRect(
            x: node.position.x - size * 0.5 - 5.5,
            y: node.position.y - size * 0.5 - 5.5,
            width: size + 11,
            height: size + 11
        )

        let categories = Array(node.relatedCategoryRaws.prefix(2))
        let segmentLength = CGFloat.pi / (CGFloat(max(categories.count, 1)) + 0.6)
        let baseAngle = -CGFloat.pi * 0.78

        for (index, categoryRaw) in categories.enumerated() {
            let start = baseAngle + CGFloat(index) * (segmentLength + 0.22)
            let end = start + segmentLength
            var arc = Path()
            arc.addArc(
                center: CGPoint(x: orbitRect.midX, y: orbitRect.midY),
                radius: orbitRect.width * 0.5,
                startAngle: .radians(start),
                endAngle: .radians(end),
                clockwise: false
            )
            context.stroke(
                arc,
                with: .color(colorForCategory(categoryRaw).opacity(nodeOpacity * (0.72 + node.bridgeStrength * 0.18))),
                style: StrokeStyle(lineWidth: 2.0, lineCap: .round)
            )
        }
    }

    private func drawBridgeBadges(for node: VisNode, in context: inout GraphicsContext, rect: CGRect) {
        let categories = Array(node.relatedCategoryRaws.prefix(2))
        guard !categories.isEmpty else { return }

        let badgeHeight: CGFloat = 12
        let spacing: CGFloat = 5
        let badgeWidths = categories.map { badgeWidth(for: shortCategoryBadgeLabel(for: $0)) }
        let totalWidth = badgeWidths.reduce(0, +) + spacing * CGFloat(max(0, categories.count - 1))
        var currentX = rect.midX - totalWidth * 0.5
        let y = rect.maxY - 9

        for (index, categoryRaw) in categories.enumerated() {
            let label = shortCategoryBadgeLabel(for: categoryRaw)
            let width = badgeWidths[index]
            let badgeRect = CGRect(x: currentX, y: y, width: width, height: badgeHeight)

            context.fill(
                Path(roundedRect: badgeRect, cornerRadius: badgeHeight * 0.5),
                with: .color(colorForCategory(categoryRaw).opacity(nodeOpacity * 0.18))
            )
            context.stroke(
                Path(roundedRect: badgeRect, cornerRadius: badgeHeight * 0.5),
                with: .color(colorForCategory(categoryRaw).opacity(nodeOpacity * 0.42)),
                lineWidth: 0.7
            )

            let text = Text(label)
                .font(.system(size: 7.2, weight: .bold, design: .rounded))
                .foregroundColor(colorForCategory(categoryRaw).opacity(nodeOpacity * 0.92))
            context.draw(context.resolve(text), at: CGPoint(x: badgeRect.midX, y: badgeRect.midY), anchor: .center)

            currentX += width + spacing
        }
    }

    private func labelMetrics(for node: VisNode, fontSize: CGFloat) -> CGSize {
        let titleWidth = max(30, CGFloat(node.title.count) * fontSize * 0.62 + 14)
        let badgeWidths = node.relatedCategoryRaws.prefix(2).map { badgeWidth(for: shortCategoryBadgeLabel(for: $0)) }
        let badgeRowWidth = badgeWidths.reduce(0, +) + CGFloat(max(0, badgeWidths.count - 1)) * 5
        let width = max(titleWidth, badgeRowWidth + 14)
        let height = fontSize + 8 + (badgeWidths.isEmpty ? 0 : 12)
        return CGSize(width: width, height: height)
    }

    private func badgeWidth(for text: String) -> CGFloat {
        max(22, CGFloat(text.count) * 5.8 + 12)
    }

    private func shortCategoryBadgeLabel(for rawCategory: String) -> String {
        guard let category = KnowledgeCategory(rawValue: rawCategory) else { return rawCategory }
        switch (category, RegionUIStore.runtimeRegion()) {
        case (.naturalScience, .taiwan):
            return "自然"
        case (.mathematicalScience, .taiwan):
            return "數學"
        case (.systemicScience, .taiwan):
            return "系統"
        case (.thinkingScience, .taiwan):
            return "思維"
        case (.humanScience, .taiwan):
            return "人體"
        case (.socialScience, .taiwan):
            return "社會"
        case (.naturalScience, .unitedStates):
            return "Nat"
        case (.mathematicalScience, .unitedStates):
            return "Math"
        case (.systemicScience, .unitedStates):
            return "Sys"
        case (.thinkingScience, .unitedStates):
            return "Mind"
        case (.humanScience, .unitedStates):
            return "Human"
        case (.socialScience, .unitedStates):
            return "Soc"
        case (.naturalScience, .japan):
            return "自然"
        case (.mathematicalScience, .japan):
            return "数学"
        case (.systemicScience, .japan):
            return "系統"
        case (.thinkingScience, .japan):
            return "思考"
        case (.humanScience, .japan):
            return "人体"
        case (.socialScience, .japan):
            return "社会"
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let adjustedX = (location.x - size.width / 2 - offset.width) / scale
        let adjustedY = (location.y - size.height / 2 - offset.height) / scale

        let tappedNode = engine.visNodes.first { node in
            let threshold: CGFloat = layoutMode == .pathway ? 28 : 40
            return hypot(node.position.x - adjustedX, node.position.y - adjustedY) < threshold / scale
        }

        guard let tappedNode, let realNode = nodes.first(where: { $0.id == tappedNode.id }) else { return }
        selectedNode = realNode
    }

    private func categoryTapTargets(in size: CGSize) -> some View {
        ZStack {
            if layoutMode == .constellation {
                ForEach(KnowledgeCategory.allCases, id: \.self) { category in
                    let screenPoint = screenPointForCategoryLabel(category, in: size)
                    Button {
                        onSelectCategory?(category)
                    } label: {
                        Text(category.localizedName)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(colorForCategory(category.rawValue).opacity(nodeOpacity * 0.92))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.001))
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .position(screenPoint)
                }
            }
        }
        .allowsHitTesting(isGraphReady && onSelectCategory != nil)
    }

    private func screenPointForCategoryLabel(_ category: KnowledgeCategory, in size: CGSize) -> CGPoint {
        let anchor = engine.categoryAnchors[category.rawValue] ?? .zero
        let anchorLength = max(hypot(anchor.x, anchor.y), 0.001)
        let direction = anchor == .zero
            ? CGPoint(x: 0, y: -1)
            : CGPoint(x: anchor.x / anchorLength, y: anchor.y / anchorLength)
        let labelPoint = anchor + direction * 18

        return CGPoint(
            x: size.width / 2 + offset.width + labelPoint.x * scale,
            y: size.height / 2 + offset.height + labelPoint.y * scale
        )
    }

    private var transitionMask: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 22,
                endRadius: 220
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 18, height: 18)
                        .blur(radius: 0.4)
                        .scaleEffect(loadingPulse ? 1.08 : 0.9)

                    Circle()
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.9)
                        .frame(width: 34, height: 34)

                    Circle()
                        .trim(from: 0.1, to: 0.78)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.white.opacity(0.78),
                                    Color.white.opacity(0.08)
                                ],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(loadingSweep ? 320 : -40))

                    Circle()
                        .stroke(Color.white.opacity(0.24), lineWidth: 7)
                        .frame(width: 46, height: 46)
                        .blur(radius: 6)
                        .opacity(loadingHalo ? 0.22 : 0.08)
                        .scaleEffect(loadingHalo ? 1.12 : 0.94)
                }
                .frame(width: 50, height: 50)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.07))
                        .frame(width: 86, height: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.0),
                                    Color.white.opacity(0.72),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 34, height: 5)
                        .offset(x: loadingSweep ? 52 : -6)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .mask(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .padding(1)
                    )
                    .frame(maxHeight: 44)
                    .blendMode(.screen)
            }
            .shadow(color: Color.black.opacity(0.06), radius: 20, y: 10)
            .scaleEffect(loadingPulse ? 1.0 : 0.988)
        }
        .allowsHitTesting(false)
    }

    private func centerPathwayDock(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 46, height: 46)

            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                .frame(width: 40, height: 40)

            Image(systemName: layoutMode == .pathway ? "point.3.connected.trianglepath.dotted" : "point.3.filled.connected.trianglepath.dotted")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .contentShape(Circle())
        .onTapGesture(count: 2) {
            activatePathwayLayout()
        }
        .frame(width: size.width, height: size.height, alignment: .bottomLeading)
        .padding(.leading, 16)
        .padding(.bottom, 16)
        .allowsHitTesting(isGraphReady && !engine.visNodes.isEmpty)
    }

    private var latestNodeBanner: some View {
        VStack {
            if let newestNode, isGraphReady {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(red: 0.92, green: 0.70, blue: 0.18))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(regionUI.copy.newestAdded)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(newestNode.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(localizedCategoryName(for: newestNode.category))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(colorForCategory(newestNode.category).opacity(0.14), in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.4), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }

    private func activatePathwayLayout() {
        guard !nodes.isEmpty else { return }

        isArrangingPathway = true
        let nextMode: GraphLayoutMode = layoutMode == .pathway ? .constellation : .pathway
        layoutMode = nextMode

        withAnimation(.easeInOut(duration: 0.24)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
            transitionMaskOpacity = 0.3
            edgeOpacity = 0.2
            contentScale = 0.996
            contentBlur = 1.2
            showPathwayHint = false
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            engine.sync(with: nodes, mode: nextMode, newestNodeID: newestNode?.id)
            nodeOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                edgeOpacity = 1.0
                transitionMaskOpacity = 0.0
                contentScale = 1.0
                contentBlur = 0.0
                showPathwayHint = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            isArrangingPathway = false
        }
    }

    private func beginRevealSequence(hasContent: Bool) {
        let sequenceID = UUID()
        revealSequenceID = sequenceID
        showPathwayHint = false

        guard hasContent else {
            withAnimation(.easeOut(duration: 0.15)) {
                isGraphReady = true
                nodeOpacity = 0.0
                edgeOpacity = 0.0
                transitionMaskOpacity = 0.0
                contentScale = 1.0
                contentBlur = 0.0
            }
            return
        }

        let alreadyShowingGraph = isGraphReady && !engine.visNodes.isEmpty
        nodeOpacity = alreadyShowingGraph ? 0.92 : 0.0
        edgeOpacity = alreadyShowingGraph ? 0.34 : 0.0
        transitionMaskOpacity = alreadyShowingGraph ? 0.26 : 0.42
        contentScale = alreadyShowingGraph ? 0.996 : 1.0
        contentBlur = alreadyShowingGraph ? 1.0 : 1.8

        withAnimation(.easeOut(duration: 0.14)) {
            isGraphReady = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard revealSequenceID == sequenceID else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                nodeOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard revealSequenceID == sequenceID else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                edgeOpacity = 1.0
                transitionMaskOpacity = 0.0
                contentScale = 1.0
                contentBlur = 0.0
                showPathwayHint = true
            }
        }
    }

    private func localizedCategoryName(for rawCategory: String) -> String {
        KnowledgeCategory(rawValue: rawCategory)?.localizedName ?? rawCategory
    }
}

private struct GraphNodeSignature: Hashable {
    let id: UUID
    let title: String
    let contentPreview: String
    let category: String
    let createdAt: Date
}
