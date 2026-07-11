import CoreGraphics
import Foundation

/// Barnes–Hut quadtree for O(n log n) repulsion in large graph simulations.
enum GraphBarnesHut {
    static let theta: CGFloat = 1.2

    static func repulsionForces(
        nodes: [GraphNodeSnapshot],
        draggedNodeID: String?,
        strength: CGFloat
    ) -> [CGPoint] {
        guard nodes.count > 1 else { return Array(repeating: .zero, count: nodes.count) }

        let bounds = boundingBox(for: nodes)
        guard bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: nodes.count)
        }

        let root = QuadNode(bounds: bounds)
        for (index, node) in nodes.enumerated() {
            root.insert(index: index, position: node.position)
        }
        root.refreshMass()

        var forces = Array(repeating: CGPoint.zero, count: nodes.count)
        for (index, node) in nodes.enumerated() {
            if node.id == draggedNodeID { continue }
            var force = CGPoint.zero
            root.accumulateForce(
                on: node.position,
                excluding: index,
                theta: theta,
                strength: strength,
                into: &force
            )
            forces[index] = force
        }
        return forces
    }

    private static func boundingBox(for nodes: [GraphNodeSnapshot]) -> CGRect {
        guard let first = nodes.first else { return .zero }
        var minX = first.position.x
        var maxX = first.position.x
        var minY = first.position.y
        var maxY = first.position.y

        for node in nodes.dropFirst() {
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
        }

        let padding: CGFloat = 64
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(maxX - minX + padding * 2, 1),
            height: max(maxY - minY + padding * 2, 1)
        )
    }

    private final class QuadNode {
        let bounds: CGRect
        private var bodyIndex: Int?
        private var centerOfMass = CGPoint.zero
        private var totalMass: CGFloat = 0
        private var children: [QuadNode]?

        init(bounds: CGRect) {
            self.bounds = bounds
        }

        func insert(index: Int, position: CGPoint) {
            guard bounds.contains(position) else { return }

            if bodyIndex == nil, children == nil {
                bodyIndex = index
                centerOfMass = position
                totalMass = 1
                return
            }

            if children == nil {
                subdivide()
            }

            if let existing = bodyIndex {
                insertIntoChild(index: existing, position: centerOfMass)
                bodyIndex = nil
            }
            insertIntoChild(index: index, position: position)
        }

        func refreshMass() {
            if let children {
                totalMass = 0
                var weightedX: CGFloat = 0
                var weightedY: CGFloat = 0
                for child in children {
                    child.refreshMass()
                    totalMass += child.totalMass
                    weightedX += child.centerOfMass.x * child.totalMass
                    weightedY += child.centerOfMass.y * child.totalMass
                }
                if totalMass > 0 {
                    centerOfMass = CGPoint(x: weightedX / totalMass, y: weightedY / totalMass)
                } else {
                    centerOfMass = .zero
                }
                bodyIndex = nil
            } else if let bodyIndex {
                totalMass = 1
                _ = bodyIndex
            } else {
                totalMass = 0
                centerOfMass = .zero
            }
        }

        func accumulateForce(
            on position: CGPoint,
            excluding excludedIndex: Int,
            theta: CGFloat,
            strength: CGFloat,
            into force: inout CGPoint
        ) {
            guard totalMass > 0 else { return }

            let delta = CGPoint(x: position.x - centerOfMass.x, y: position.y - centerOfMass.y)
            let distance = max(hypot(delta.x, delta.y), 10)

            if let bodyIndex, children == nil {
                guard bodyIndex != excludedIndex else { return }
                let push = min(strength / (distance * distance), 14)
                force.x += delta.x / distance * push
                force.y += delta.y / distance * push
                return
            }

            let cellSize = max(bounds.width, bounds.height)
            if cellSize / distance < theta {
                let push = min(strength / (distance * distance), 14)
                force.x += delta.x / distance * push * totalMass
                force.y += delta.y / distance * push * totalMass
                return
            }

            guard let children else { return }
            for child in children {
                child.accumulateForce(
                    on: position,
                    excluding: excludedIndex,
                    theta: theta,
                    strength: strength,
                    into: &force
                )
            }
        }

        private func subdivide() {
            let halfWidth = bounds.width / 2
            let halfHeight = bounds.height / 2
            let x = bounds.minX
            let y = bounds.minY

            children = [
                QuadNode(bounds: CGRect(x: x, y: y, width: halfWidth, height: halfHeight)),
                QuadNode(bounds: CGRect(x: x + halfWidth, y: y, width: halfWidth, height: halfHeight)),
                QuadNode(bounds: CGRect(x: x, y: y + halfHeight, width: halfWidth, height: halfHeight)),
                QuadNode(bounds: CGRect(x: x + halfWidth, y: y + halfHeight, width: halfWidth, height: halfHeight)),
            ]
        }

        private func insertIntoChild(index: Int, position: CGPoint) {
            guard let children else {
                bodyIndex = index
                centerOfMass = position
                return
            }
            for child in children where child.bounds.contains(position) {
                child.insert(index: index, position: position)
                return
            }
        }
    }
}

struct GraphNodeSnapshot {
    let id: String
    let position: CGPoint
}
