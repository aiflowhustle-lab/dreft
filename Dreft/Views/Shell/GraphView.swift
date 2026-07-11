import SwiftUI

private struct GraphNode: Identifiable {
    let id: String
    var label: String
    var position: CGPoint
    var velocity: CGPoint = .zero
}

private struct GraphLink: Identifiable, Hashable {
    let fromID: String
    let toID: String

    var id: String { "\(fromID)->\(toID)" }
}

private struct GraphGroup: Identifiable {
    var id = UUID()
    var query: String = ""
    var color: Color
}

private let groupColorCycle: [Color] = [
    Color(red: 224 / 255, green: 82 / 255, blue: 82 / 255),
    Color(red: 233 / 255, green: 151 / 255, blue: 63 / 255),
    Color(red: 224 / 255, green: 200 / 255, blue: 82 / 255),
    Color(red: 108 / 255, green: 192 / 255, blue: 108 / 255),
    Color(red: 83 / 255, green: 155 / 255, blue: 245 / 255),
    Color(red: 168 / 255, green: 130 / 255, blue: 255 / 255),
]

private enum GraphPerformance {
    static let viewportCullThreshold = 150
    static let naivePhysicsNodeCap = 350
    static let maxSimulationNodes = 2500
    static let simulationNodeCap = naivePhysicsNodeCap
    static let denseLabelNodeCap = 180
    static let selectiveLabelNodeCap = 80
    static let selectiveLabelZoomThreshold: CGFloat = 0.72
    static let dotsOnlyZoomThreshold: CGFloat = 0.38
    static let hideDenseLinksZoomThreshold: CGFloat = 0.55
    static let hideDenseLinksCountThreshold = 800
    static let fadeLinksZoomThreshold: CGFloat = 0.45
    static let fadeLinksCountThreshold = 400
    static let physicsFrameMs = 16
    static let viewportCullPadding: CGFloat = 200
    static let localGraphDefaultThreshold = 350
}

private enum GraphLODLevel {
    case full
    case selectiveLabels
    case dotsOnly
}

private enum GraphScope: String, CaseIterable, Identifiable {
    case local
    case global

    var id: String { rawValue }

    var label: String {
        switch self {
        case .local: return "Local"
        case .global: return "Global"
        }
    }
}

struct GraphView: View {
    @Bindable var workspace: WorkspaceStore

    @State private var nodes: [GraphNode] = []
    @State private var links: [GraphLink] = []
    @State private var nodeIndexByID: [String: Int] = [:]
    @State private var panOffset: CGSize = .zero
    @State private var panDragStart: CGSize = .zero
    @State private var draggedNodeID: String?
    @State private var nodeDragStart: CGPoint?
    @State private var isPanningGraph = false
    @State private var canvasSize: CGSize = .zero
    @State private var expandedSections: Set<String> = ["Filters"]
    @State private var simulationTask: Task<Void, Never>?
    @State private var graphSyncTask: Task<Void, Never>?
    @State private var alpha: CGFloat = 0
    @State private var zoomScale: CGFloat = 1
    @State private var zoomGestureStart: CGFloat?
    @State private var controlsVisible = true

    @State private var searchText = ""
    @State private var filterTags = false
    @State private var filterAttachments = false
    @State private var filterExistingOnly = false
    @State private var filterOrphans = true
    @State private var displayArrows = false
    @State private var textFadeThreshold = 0.5
    @State private var nodeSize = 0.3
    @State private var linkThickness = 0.25
    @State private var centerForce = 0.5
    @State private var repelForce = 0.5
    @State private var linkForce = 0.9
    @State private var linkDistance = 0.4

    @State private var groups: [GraphGroup] = []
    @State private var colorPickerGroupID: UUID?
    @FocusState private var focusedGroupID: UUID?

    @State private var graphScope: GraphScope = .global
    @State private var localGraphDepth = 2
    @State private var savedPositions: [String: CGPoint] = [:]
    @State private var layoutSaveTask: Task<Void, Never>?
    @State private var didApplyDefaultScope = false
    @State private var lastLocalCenterID: String?

    var body: some View {
        ZStack {
            AppColors.canvasBackground

            GeometryReader { geo in
                ZStack {
                    graphContent
                        .scaleEffect(zoomScale)
                        .offset(panOffset)
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if zoomGestureStart == nil {
                                zoomGestureStart = zoomScale
                            }
                            zoomScale = min(max((zoomGestureStart ?? 1) * value, 0.3), 3.5)
                        }
                        .onEnded { _ in
                            zoomGestureStart = nil
                        }
                )
                .onAppear {
                    canvasSize = geo.size
                    loadSavedLayout()
                    applyDefaultScopeIfNeeded()
                    syncGraph(in: geo.size)
                    kickSimulation(to: simulationEnergyAfterSync())
                }
                .onChange(of: geo.size) { _, newSize in
                    canvasSize = newSize
                    scheduleGraphSync(in: newSize, simulationEnergy: 0.5)
                }
                .onChange(of: workspace.files) { _, _ in
                    applyDefaultScopeIfNeeded()
                    scheduleGraphSync(in: geo.size, simulationEnergy: 0.8)
                }
                .onChange(of: workspace.graphLinksVersion) { _, _ in
                    let linksChanged = syncGraphLinks()
                    if linksChanged, nodes.count <= GraphPerformance.maxSimulationNodes {
                        kickSimulation(to: 0.5)
                    }
                }
                .onChange(of: workspace.activeVault?.id) { _, _ in
                    loadSavedLayout()
                    didApplyDefaultScope = false
                    lastLocalCenterID = nil
                    applyDefaultScopeIfNeeded()
                    scheduleGraphSync(in: geo.size, simulationEnergy: simulationEnergyAfterSync())
                }
                .onChange(of: workspace.selectedFileID) { _, _ in
                    guard graphScope == .local else { return }
                    let center = localGraphCenterID()
                    guard center != lastLocalCenterID else { return }
                    lastLocalCenterID = center
                    scheduleGraphSync(in: geo.size, simulationEnergy: 0.6)
                }
                .onChange(of: graphScope) { _, _ in
                    scheduleGraphSync(in: geo.size, simulationEnergy: simulationEnergyAfterSync())
                }
                .onChange(of: localGraphDepth) { _, _ in
                    guard graphScope == .local else { return }
                    scheduleGraphSync(in: geo.size, simulationEnergy: 0.6)
                }
            }

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if controlsVisible {
                        graphControlsPanel
                    } else {
                        reopenControlsButton
                    }
                }
                Spacer()
            }
            .padding(14)
        }
        .background(AppColors.canvasBackground)
        .overlay(alignment: .bottomLeading) {
            if !nodes.isEmpty {
                Text(graphStatusText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.leading, 14)
                    .padding(.bottom, 10)
            }
        }
        .onDisappear {
            simulationTask?.cancel()
            graphSyncTask?.cancel()
            layoutSaveTask?.cancel()
            persistGraphLayout()
        }
    }

    private func scheduleGraphSync(in size: CGSize, simulationEnergy: CGFloat) {
        graphSyncTask?.cancel()
        graphSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            syncGraph(in: size)
            kickSimulation(to: simulationEnergy)
        }
    }

    private var graphStatusText: String {
        let nodeLabel = "\(nodes.count) node\(nodes.count == 1 ? "" : "s")"
        let linkLabel = "\(links.count) link\(links.count == 1 ? "" : "s")"
        var parts = [nodeLabel, linkLabel]
        switch graphScope {
        case .local:
            parts.append("Local")
        case .global:
            break
        }
        switch graphLODLevel {
        case .selectiveLabels:
            parts.append("Selective labels")
        case .dotsOnly:
            parts.append("Dots only")
        case .full:
            break
        }
        return parts.joined(separator: " · ")
    }

    private func loadSavedLayout() {
        guard let vaultURL = workspace.activeVaultURL else {
            savedPositions = [:]
            groups = []
            return
        }
        let state = GraphLayoutPersistence.load(vaultURL: vaultURL)
        savedPositions = state.positions
        groups = state.groups.map { record in
            GraphGroup(
                id: record.id,
                query: record.query,
                color: Color(hexString: record.colorHex)
                    ?? groupColorCycle[abs(record.id.hashValue) % groupColorCycle.count]
            )
        }
        if !groups.isEmpty {
            expandedSections.insert("Groups")
        }
    }

    private func applyDefaultScopeIfNeeded() {
        guard !didApplyDefaultScope else { return }
        didApplyDefaultScope = true
        if workspace.graphEligibleFileCount > GraphPerformance.localGraphDefaultThreshold {
            graphScope = .local
        }
        lastLocalCenterID = localGraphCenterID()
    }

    private func graphEligibleFileIDs() -> Set<String> {
        Set(
            workspace.files
                .filter { $0.kind == .note || $0.kind == .canvas }
                .map(\.id)
        )
    }

    private func scopedFileIDs() -> Set<String> {
        let eligible = graphEligibleFileIDs()
        switch graphScope {
        case .global:
            return eligible
        case .local:
            guard let center = localGraphCenterID() else { return [] }
            return workspace.graphNeighborhood(around: center, depth: localGraphDepth)
                .intersection(eligible)
        }
    }

    private func localGraphCenterID() -> String? {
        if let selected = workspace.selectedFileID,
           let file = workspace.files.first(where: { $0.id == selected }),
           file.kind == .note || file.kind == .canvas {
            return selected
        }
        if let fileID = workspace.activeTab?.fileID,
           let file = workspace.files.first(where: { $0.id == fileID }),
           file.kind == .note || file.kind == .canvas {
            return fileID
        }
        return nil
    }

    private func simulationEnergyAfterSync() -> CGFloat {
        let scoped = scopedFileIDs()
        guard !scoped.isEmpty else { return 0 }
        if scoped.allSatisfy({ savedPositions[$0] != nil }) {
            return 0
        }
        return nodes.count <= GraphPerformance.maxSimulationNodes ? 1 : 0
    }

    private func scheduleLayoutSave() {
        layoutSaveTask?.cancel()
        layoutSaveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            persistGraphLayout()
        }
    }

    private func persistGraphLayout() {
        guard let vaultURL = workspace.activeVaultURL else { return }
        for node in nodes {
            savedPositions[node.id] = snapGraphPoint(node.position)
        }
        let records = groups.map { group in
            GraphLayoutGroup(
                id: group.id,
                query: group.query,
                colorHex: group.color.canvasHexString
            )
        }
        GraphLayoutPersistence.save(
            GraphLayoutState(positions: savedPositions, groups: records),
            vaultURL: vaultURL
        )
    }

    private var renderedNodes: [GraphNode] {
        let candidates = displayedNodes
        guard candidates.count > GraphPerformance.viewportCullThreshold,
              !isLayoutAnimating else { return candidates }
        let rect = visibleGraphRect(padding: GraphPerformance.viewportCullPadding)
        return candidates.filter { rect.contains($0.position) }
    }

    /// While the force simulation runs, render every node so culling doesn't pop them at edges.
    private var isLayoutAnimating: Bool {
        alpha > 0.008 || draggedNodeID != nil || simulationTask != nil
    }

    private var renderedLinks: [GraphLink] {
        let visibleIDs = Set(renderedNodes.map(\.id))
        return links.filter { visibleIDs.contains($0.fromID) && visibleIDs.contains($0.toID) }
    }

    private var effectiveLabelOpacity: CGFloat {
        labelOpacity
    }

    private var graphLODLevel: GraphLODLevel {
        if zoomScale < GraphPerformance.dotsOnlyZoomThreshold { return .dotsOnly }
        let count = displayedNodes.count
        if count > GraphPerformance.denseLabelNodeCap
            || (count > GraphPerformance.selectiveLabelNodeCap
                && zoomScale < GraphPerformance.selectiveLabelZoomThreshold) {
            return .selectiveLabels
        }
        return .full
    }

    private var graphLinkRenderOpacity: CGFloat {
        guard !renderedLinks.isEmpty else { return 0 }
        if zoomScale < GraphPerformance.dotsOnlyZoomThreshold { return 0 }
        if renderedLinks.count > GraphPerformance.hideDenseLinksCountThreshold,
           zoomScale < GraphPerformance.hideDenseLinksZoomThreshold {
            return 0
        }
        if renderedLinks.count > GraphPerformance.fadeLinksCountThreshold,
           zoomScale < GraphPerformance.fadeLinksZoomThreshold {
            return 0.18
        }
        return 1
    }

    private func shouldShowLabel(for node: GraphNode) -> Bool {
        guard effectiveLabelOpacity > 0.01 else { return false }
        switch graphLODLevel {
        case .full:
            return true
        case .selectiveLabels:
            if zoomScale >= 0.92 { return true }
            if draggedNodeID == node.id { return true }
            if !searchText.isEmpty, nodeMatchesSearch(node) { return true }
            if graphScope == .local, localGraphCenterID() == node.id { return true }
            return false
        case .dotsOnly:
            return draggedNodeID == node.id
        }
    }

    private func visibleGraphRect(padding: CGFloat) -> CGRect {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(x: -.infinity, y: -.infinity, width: .infinity, height: .infinity)
        }
        let minX = (-panOffset.width) / zoomScale - padding
        let minY = (-panOffset.height) / zoomScale - padding
        let maxX = (canvasSize.width - panOffset.width) / zoomScale + padding
        let maxY = (canvasSize.height - panOffset.height) / zoomScale + padding
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var displayedNodes: [GraphNode] {
        guard filterOrphans else {
            let connected = Set(links.flatMap { [$0.fromID, $0.toID] })
            return nodes.filter { connected.contains($0.id) }
        }
        return nodes
    }

    private var linkStrokeWidth: CGFloat {
        0.5 + CGFloat(linkThickness) * 2.5
    }

    private func nodeMatchesSearch(_ node: GraphNode) -> Bool {
        searchText.isEmpty || node.label.localizedCaseInsensitiveContains(searchText)
    }

    private var labelOpacity: CGFloat {
        let threshold = 0.25 + CGFloat(textFadeThreshold) * 0.9
        return min(1, max(0, (zoomScale - threshold + 0.45) / 0.45))
    }

    private var nodeDotSize: CGFloat {
        4 + CGFloat(nodeSize) * 10
    }

    private func groupColor(for node: GraphNode) -> Color? {
        for group in groups {
            let query = group.query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { continue }

            let target: String
            let term: String
            if query.lowercased().hasPrefix("file:") {
                target = node.label
                term = String(query.dropFirst(5))
            } else if query.lowercased().hasPrefix("path:") {
                target = workspace.path(for: node.id)
                term = String(query.dropFirst(5))
            } else if query.lowercased().hasPrefix("tag:") || query.lowercased().hasPrefix("line:")
                || query.lowercased().hasPrefix("section:") || query.hasPrefix("[") {
                continue
            } else {
                target = node.label
                term = query
            }

            let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
            if !trimmedTerm.isEmpty, target.localizedCaseInsensitiveContains(trimmedTerm) {
                return group.color
            }
        }
        return nil
    }

    private var canvasDrawLinks: [GraphCanvasLink] {
        renderedLinks.map { GraphCanvasLink(fromID: $0.fromID, toID: $0.toID) }
    }

    private var canvasDrawNodes: [GraphCanvasDrawNode] {
        renderedNodes.map { node in
            GraphCanvasDrawNode(
                id: node.id,
                label: node.label,
                position: node.position,
                isActive: draggedNodeID == node.id,
                isDimmed: !nodeMatchesSearch(node),
                groupColor: groupColor(for: node),
                showsLabel: shouldShowLabel(for: node)
            )
        }
    }

    private var graphContent: some View {
        ZStack {
            graphCanvasStack
            graphNodeInteractionLayer
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        .coordinateSpace(name: "graphCanvas")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var graphCanvasStack: some View {
        ZStack {
            GraphCanvasLayer(
                nodes: canvasDrawNodes,
                links: canvasDrawLinks,
                positions: nodePositionsByID(for: renderedNodes),
                linkStrokeWidth: linkStrokeWidth,
                showArrows: displayArrows && renderedLinks.count <= 400,
                nodeDotSize: nodeDotSize,
                labelOpacity: effectiveLabelOpacity,
                drawLabelsInCanvas: isLayoutAnimating,
                linksDimmed: !searchText.isEmpty,
                linkRenderOpacity: graphLinkRenderOpacity
            )
            if !isLayoutAnimating {
                GraphNodeLabelsLayer(
                    nodes: canvasDrawNodes,
                    labelOpacity: effectiveLabelOpacity
                )
            }
        }
    }

    private var graphNodeInteractionLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(graphNodeInteractionGesture)
    }

    private var graphNodeInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("graphCanvas"))
            .onChanged { value in
                if draggedNodeID == nil, !isPanningGraph {
                    if let nodeID = GraphCanvasHitTesting.nodeID(
                        at: value.startLocation,
                        in: canvasDrawNodes
                    ) {
                        draggedNodeID = nodeID
                        nodeDragStart = nodes[nodeIndexByID[nodeID]!].position
                        kickSimulation(to: 0.6)
                    } else if hypot(value.translation.width, value.translation.height) > 4 {
                        isPanningGraph = true
                    }
                }

                if isPanningGraph {
                    panOffset = CGSize(
                        width: panDragStart.width + value.translation.width,
                        height: panDragStart.height + value.translation.height
                    )
                    return
                }

                guard let nodeID = draggedNodeID,
                      let index = nodeIndexByID[nodeID],
                      let start = nodeDragStart else { return }

                mutateGraphNodesWithoutAnimation {
                    nodes[index].position = CGPoint(
                        x: start.x + value.translation.width,
                        y: start.y + value.translation.height
                    )
                    nodes[index].velocity = .zero
                }
            }
            .onEnded { value in
                if isPanningGraph {
                    panDragStart = panOffset
                    isPanningGraph = false
                    return
                }

                let moved = hypot(value.translation.width, value.translation.height) > 3
                let tappedID = draggedNodeID
                    ?? GraphCanvasHitTesting.nodeID(at: value.location, in: canvasDrawNodes)

                if !moved, let nodeID = tappedID,
                   let file = workspace.files.first(where: { $0.id == nodeID }) {
                    workspace.openTab(for: file)
                }

                let wasDragging = draggedNodeID != nil
                draggedNodeID = nil
                nodeDragStart = nil
                if wasDragging {
                    kickSimulation(to: 0.4)
                    scheduleLayoutSave()
                }
            }
    }

    private func mutateGraphNodesWithoutAnimation(_ updates: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, updates)
    }

    // d3-force style simulation: the graph continuously relaxes toward
    // equilibrium while alpha (temperature) decays, like Obsidian's graph.
    private func kickSimulation(to targetAlpha: CGFloat) {
        guard nodes.count <= GraphPerformance.maxSimulationNodes else { return }

        if simulationTask != nil {
            if targetAlpha > alpha {
                alpha = targetAlpha
            }
            return
        }

        alpha = max(alpha, targetAlpha)

        simulationTask = Task { @MainActor in
            defer { simulationTask = nil }
            while !Task.isCancelled {
                if draggedNodeID != nil {
                    alpha = max(alpha, 0.35)
                }
                stepPhysics()
                alpha *= 0.972
                if alpha < 0.005, draggedNodeID == nil {
                    snapAllNodePositions()
                    alpha = 0
                    scheduleLayoutSave()
                    break
                }
                try? await Task.sleep(for: .milliseconds(GraphPerformance.physicsFrameMs))
            }
        }
    }

    private func snapAllNodePositions() {
        mutateGraphNodesWithoutAnimation {
            for index in nodes.indices {
                nodes[index].position = snapGraphPoint(nodes[index].position)
                nodes[index].velocity = .zero
            }
        }
    }

    private func snapGraphPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: round(point.x * 2) / 2, y: round(point.y * 2) / 2)
    }

    private func applyNaiveRepulsion(
        forces: inout [CGPoint],
        repulsionStrength: CGFloat
    ) {
        for index in nodes.indices {
            if nodes[index].id == draggedNodeID { continue }

            let position = nodes[index].position

            for otherIndex in nodes.indices where otherIndex != index {
                let other = nodes[otherIndex].position
                let delta = CGPoint(x: position.x - other.x, y: position.y - other.y)
                let distance = max(hypot(delta.x, delta.y), 10)
                let push = min(repulsionStrength / (distance * distance), 14)
                forces[index].x += delta.x / distance * push
                forces[index].y += delta.y / distance * push
            }
        }
    }

    private func stepPhysics() {
        guard nodes.count > 1, canvasSize.width > 0, canvasSize.height > 0 else { return }

        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let repulsionStrength: CGFloat = 20000 + CGFloat(repelForce) * 80000
        let gravityStrength: CGFloat = 0.02 + CGFloat(centerForce) * 0.05
        let linkTargetDistance: CGFloat = 80 + CGFloat(linkDistance) * 180
        let linkStrength: CGFloat = 0.015 + CGFloat(linkForce) * 0.1
        // Stronger damping as the simulation cools so nodes settle instead of buzzing.
        let velocityDecay: CGFloat = 0.58 + (1 - alpha) * 0.28
        let maxSpeed: CGFloat = 22
        let settleSpeed: CGFloat = 0.15
        let settleAlpha: CGFloat = 0.1

        var forces = Array(repeating: CGPoint.zero, count: nodes.count)

        if nodes.count <= GraphPerformance.naivePhysicsNodeCap {
            applyNaiveRepulsion(forces: &forces, repulsionStrength: repulsionStrength)
        } else {
            let snapshots = nodes.map { GraphNodeSnapshot(id: $0.id, position: $0.position) }
            let repulsionForces = GraphBarnesHut.repulsionForces(
                nodes: snapshots,
                draggedNodeID: draggedNodeID,
                strength: repulsionStrength
            )
            for index in nodes.indices where nodes[index].id != draggedNodeID {
                forces[index].x += repulsionForces[index].x
                forces[index].y += repulsionForces[index].y
            }
        }

        for index in nodes.indices where nodes[index].id != draggedNodeID {
            let position = nodes[index].position
            forces[index].x += (center.x - position.x) * gravityStrength
            forces[index].y += (center.y - position.y) * gravityStrength
        }

        for link in links {
            guard let fromIndex = nodeIndexByID[link.fromID],
                  let toIndex = nodeIndexByID[link.toID] else { continue }

            let from = nodes[fromIndex].position
            let to = nodes[toIndex].position
            let delta = CGPoint(x: to.x - from.x, y: to.y - from.y)
            let distance = max(hypot(delta.x, delta.y), 1)
            let displacement = distance - linkTargetDistance
            let forceMagnitude = displacement * linkStrength * alpha
            let forceX = delta.x / distance * forceMagnitude
            let forceY = delta.y / distance * forceMagnitude

            if nodes[fromIndex].id != draggedNodeID {
                forces[fromIndex].x += forceX
                forces[fromIndex].y += forceY
            }
            if nodes[toIndex].id != draggedNodeID {
                forces[toIndex].x -= forceX
                forces[toIndex].y -= forceY
            }
        }

        mutateGraphNodesWithoutAnimation {
            for index in nodes.indices {
                if nodes[index].id == draggedNodeID { continue }

                nodes[index].velocity.x = (nodes[index].velocity.x + forces[index].x * alpha) * velocityDecay
                nodes[index].velocity.y = (nodes[index].velocity.y + forces[index].y * alpha) * velocityDecay

                let speed = hypot(nodes[index].velocity.x, nodes[index].velocity.y)
                if speed > maxSpeed {
                    nodes[index].velocity.x = nodes[index].velocity.x / speed * maxSpeed
                    nodes[index].velocity.y = nodes[index].velocity.y / speed * maxSpeed
                }

                if alpha < settleAlpha, speed < settleSpeed {
                    nodes[index].velocity = .zero
                } else {
                    nodes[index].position.x += nodes[index].velocity.x
                    nodes[index].position.y += nodes[index].velocity.y
                }
            }
        }
    }

    private func syncGraph(in size: CGSize) {
        let built = buildGraphNodes(in: size)

        var merged: [GraphNode] = []
        for proposed in built {
            if let existing = nodes.first(where: { $0.id == proposed.id }) {
                merged.append(
                    GraphNode(
                        id: proposed.id,
                        label: proposed.label,
                        position: existing.position,
                        velocity: existing.velocity
                    )
                )
            } else if let saved = savedPositions[proposed.id] {
                merged.append(
                    GraphNode(
                        id: proposed.id,
                        label: proposed.label,
                        position: saved
                    )
                )
            } else {
                merged.append(proposed)
            }
        }
        nodes = merged
        rebuildNodeIndex()
        syncGraphLinks()
    }

    @discardableResult
    private func syncGraphLinks() -> Bool {
        let scopeIDs = scopedFileIDs()
        let built = workspace.graphEdges
            .filter { scopeIDs.contains($0.fromID) && scopeIDs.contains($0.toID) }
            .map { GraphLink(fromID: $0.fromID, toID: $0.toID) }
        let previousKeys = Set(links.map(\.id))
        links = built
        return Set(built.map(\.id)) != previousKeys
    }

    private func rebuildNodeIndex() {
        var map: [String: Int] = [:]
        map.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() {
            map[node.id] = index
        }
        nodeIndexByID = map
    }

    private func nodePositionsByID(for nodes: [GraphNode]) -> [String: CGPoint] {
        Dictionary(nodes.map { ($0.id, $0.position) }, uniquingKeysWith: { first, _ in first })
    }

    private func resetGraphLayout(in size: CGSize) {
        simulationTask?.cancel()
        simulationTask = nil
        draggedNodeID = nil
        nodeDragStart = nil
        alpha = 0
        for node in nodes {
            savedPositions.removeValue(forKey: node.id)
        }
        persistGraphLayout()
        nodes = buildGraphNodes(in: size)
        rebuildNodeIndex()
        syncGraphLinks()
        kickSimulation(to: 1)
    }

    private func buildGraphNodes(in size: CGSize) -> [GraphNode] {
        let scopeIDs = scopedFileIDs()
        let graphFiles = workspace.files.filter {
            ($0.kind == .note || $0.kind == .canvas) && scopeIDs.contains($0.id)
        }
        guard !graphFiles.isEmpty else { return [] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.16

        var nodes: [GraphNode] = []
        for (index, file) in graphFiles.enumerated() {
            let angle = (Double(index) / Double(graphFiles.count)) * (.pi * 2) - .pi / 2
            let jitter = CGFloat(stableHash(file.id) % 24) - 12
            let position = CGPoint(
                x: center.x + CGFloat(cos(angle)) * (radius + jitter),
                y: center.y + CGFloat(sin(angle)) * (radius + jitter * 0.6)
            )
            nodes.append(
                GraphNode(
                    id: file.id,
                    label: file.name,
                    position: position
                )
            )
        }

        return nodes
    }

    private var reopenControlsButton: some View {
        Button {
            controlsVisible = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.floatingChrome)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Open graph settings")
    }

    private var graphControlsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            filtersSection
            ShellHairline()
            groupsSection
            ShellHairline()
            displaySection
            ShellHairline()
            forcesSection
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.floatingChrome)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: centerForce) { _, _ in kickSimulation(to: 0.35) }
        .onChange(of: repelForce) { _, _ in kickSimulation(to: 0.35) }
        .onChange(of: linkForce) { _, _ in kickSimulation(to: 0.35) }
        .onChange(of: linkDistance) { _, _ in kickSimulation(to: 0.35) }
    }

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                sectionToggleLabel("Filters")
                Spacer()
                Button {
                    resetGraphLayout(in: canvasSize)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textMuted)
                }
                .buttonStyle(.plain)
                .help("Restore default settings")
                Button {
                    controlsVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textMuted)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if expandedSections.contains("Filters") {
                searchField
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                toggleRow("Tags", isOn: $filterTags)
                toggleRow("Attachments", isOn: $filterAttachments)
                toggleRow("Existing files only", isOn: $filterExistingOnly)
                toggleRow("Orphans", isOn: $filterOrphans)

                graphScopeSection

                Spacer().frame(height: 8)
            }
        }
    }

    private var graphScopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scope")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Picker("", selection: $graphScope) {
                    ForEach(GraphScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            if graphScope == .local {
                HStack {
                    Text("Depth")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Stepper("\(localGraphDepth)", value: $localGraphDepth, in: 1...4)
                        .labelsHidden()
                    Text("\(localGraphDepth)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 16, alignment: .trailing)
                }
                .padding(.horizontal, 12)

                if let centerID = localGraphCenterID(),
                   let centerName = workspace.files.first(where: { $0.id == centerID })?.name {
                    Text("Center: \(centerName)")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else {
                    Text("Select a note to center the local graph")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.textMuted)
                        .padding(.horizontal, 12)
                }
            }
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Groups")

            if expandedSections.contains("Groups") {
                ForEach($groups) { $group in
                    groupRow($group)
                }

                purpleButton("New group") {
                    let color = groupColorCycle[groups.count % groupColorCycle.count]
                    let group = GraphGroup(color: color)
                    groups.append(group)
                    focusedGroupID = group.id
                    scheduleLayoutSave()
                }
                Spacer().frame(height: 8)
            }
        }
    }

    private func groupRow(_ group: Binding<GraphGroup>) -> some View {
        HStack(spacing: 8) {
            TextField("Enter query...", text: group.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textPrimary)
                .focused($focusedGroupID, equals: group.wrappedValue.id)
                .onChange(of: group.wrappedValue.query) { _, _ in
                    scheduleLayoutSave()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    focusedGroupID == group.wrappedValue.id
                                        ? Color.white.opacity(0.35)
                                        : Color.white.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                )
                .popover(
                    isPresented: Binding(
                        get: {
                            focusedGroupID == group.wrappedValue.id
                                && group.wrappedValue.query.isEmpty
                        },
                        set: { if !$0 { focusedGroupID = nil } }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    searchOptionsPopover { option in
                        group.wrappedValue.query = option
                        focusedGroupID = group.wrappedValue.id
                        scheduleLayoutSave()
                    }
                }

            Button {
                colorPickerGroupID = group.wrappedValue.id
            } label: {
                Circle()
                    .fill(group.wrappedValue.color)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Set color")
            .popover(
                isPresented: Binding(
                    get: { colorPickerGroupID == group.wrappedValue.id },
                    set: { if !$0 { colorPickerGroupID = nil } }
                ),
                arrowEdge: .bottom
            ) {
                GroupColorPickerPopover(color: group.color, onColorChanged: scheduleLayoutSave)
            }

            Button {
                groups.removeAll { $0.id == group.wrappedValue.id }
                scheduleLayoutSave()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textMuted)
            }
            .buttonStyle(.plain)
            .help("Remove group")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func searchOptionsPopover(onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Search options")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            searchOptionRow(prefix: "path:", detail: "match path of the file", onSelect: onSelect)
            searchOptionRow(prefix: "file:", detail: "match file name", onSelect: onSelect)
            searchOptionRow(prefix: "tag:", detail: "search for tags", onSelect: onSelect)
            searchOptionRow(prefix: "line:", detail: "search keywords on same line", onSelect: onSelect)
            searchOptionRow(prefix: "section:", detail: "search keywords under same heading", onSelect: onSelect)
            searchOptionRow(prefix: "[property]", detail: "match property", onSelect: onSelect)

            Spacer().frame(height: 8)
        }
        .frame(width: 300)
    }

    private func searchOptionRow(
        prefix: String,
        detail: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        Button {
            onSelect(prefix == "[property]" ? "" : prefix)
        } label: {
            (
                Text(prefix)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                + Text(" \(detail)")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Display")

            if expandedSections.contains("Display") {
                toggleRow("Arrows", isOn: $displayArrows)
                sliderRow("Text fade threshold", value: $textFadeThreshold)
                sliderRow("Node size", value: $nodeSize)
                sliderRow("Link thickness", value: $linkThickness)
                purpleButton("Animate") { kickSimulation(to: 1) }
                Spacer().frame(height: 8)
            }
        }
    }

    private var forcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Forces")

            if expandedSections.contains("Forces") {
                sliderRow("Center force", value: $centerForce)
                sliderRow("Repel force", value: $repelForce)
                sliderRow("Link force", value: $linkForce)
                sliderRow("Link distance", value: $linkDistance)
                Spacer().frame(height: 8)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            sectionToggleLabel(title)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionToggleLabel(_ title: String) -> some View {
        Button {
            if expandedSections.contains(title) {
                expandedSections.remove(title)
            } else {
                expandedSections.insert(title)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expandedSections.contains(title) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColors.textMuted)
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textMuted)
            TextField("Search files...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.28))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(AppColors.selectionStroke)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func sliderRow(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Slider(value: value, in: 0...1)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func purpleButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(AppColors.selectionStroke)
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func stableHash(_ string: String) -> Int {
        string.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    }
}

private struct GroupColorPickerPopover: View {
    @Binding var color: Color
    var onColorChanged: () -> Void = {}

    @State private var hue: Double = 0
    @State private var saturation: Double = 0.8
    @State private var brightness: Double = 0.9

    var body: some View {
        VStack(spacing: 12) {
            saturationBrightnessArea

            HStack(spacing: 12) {
                eyedropperButton

                Circle()
                    .fill(currentColor)
                    .frame(width: 34, height: 34)

                hueSlider
            }

            rgbFields
        }
        .padding(14)
        .frame(width: 250)
        .onAppear {
            syncFromColor()
        }
    }

    private var currentColor: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    private func commit() {
        color = currentColor
        onColorChanged()
    }

    private func syncFromColor() {
        #if os(macOS)
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        #endif
    }

    private var saturationBrightnessArea: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [.white, Color(hue: hue, saturation: 1, brightness: 1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .top,
                    endPoint: .bottom
                )

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .fill(currentColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .position(
                        x: saturation * geo.size.width,
                        y: (1 - brightness) * geo.size.height
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        saturation = min(max(value.location.x / geo.size.width, 0), 1)
                        brightness = 1 - min(max(value.location.y / geo.size.height, 0), 1)
                        commit()
                    }
            )
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var eyedropperButton: some View {
        Button {
            #if os(macOS)
            NSColorSampler().show { picked in
                guard let picked, let srgb = picked.usingColorSpace(.sRGB) else { return }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                hue = h
                saturation = s
                brightness = b
                commit()
            }
            #endif
        } label: {
            Image(systemName: "eyedropper")
                .font(.system(size: 15))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .help("Pick color from screen")
    }

    private var hueSlider: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: (0...6).map {
                        Color(hue: Double($0) / 6, saturation: 1, brightness: 1)
                    },
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(Capsule())

                Circle()
                    .stroke(.white, lineWidth: 3)
                    .fill(Color(hue: hue, saturation: 1, brightness: 1))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: hue * (geo.size.width - 14))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(max(value.location.x / geo.size.width, 0), 1)
                        commit()
                    }
            )
        }
        .frame(height: 14)
    }

    private var rgbComponents: (r: Int, g: Int, b: Int) {
        #if os(macOS)
        let ns = NSColor(currentColor).usingColorSpace(.sRGB) ?? .black
        return (Int(ns.redComponent * 255), Int(ns.greenComponent * 255), Int(ns.blueComponent * 255))
        #else
        return (0, 0, 0)
        #endif
    }

    private func setRGB(r: Int, g: Int, b: Int) {
        #if os(macOS)
        let ns = NSColor(
            srgbRed: CGFloat(min(max(r, 0), 255)) / 255,
            green: CGFloat(min(max(g, 0), 255)) / 255,
            blue: CGFloat(min(max(b, 0), 255)) / 255,
            alpha: 1
        )
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ns.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        hue = h
        saturation = s
        brightness = br
        commit()
        #endif
    }

    private var rgbFields: some View {
        let rgb = rgbComponents
        return HStack(spacing: 10) {
            rgbField(label: "R", value: rgb.r) { setRGB(r: $0, g: rgb.g, b: rgb.b) }
            rgbField(label: "G", value: rgb.g) { setRGB(r: rgb.r, g: $0, b: rgb.b) }
            rgbField(label: "B", value: rgb.b) { setRGB(r: rgb.r, g: rgb.g, b: $0) }
        }
    }

    private func rgbField(label: String, value: Int, onChange: @escaping (Int) -> Void) -> some View {
        VStack(spacing: 4) {
            TextField(
                "",
                text: Binding(
                    get: { String(value) },
                    set: { if let intValue = Int($0) { onChange(intValue) } }
                )
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )

            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }
}

#if os(macOS)
import AppKit
#endif
