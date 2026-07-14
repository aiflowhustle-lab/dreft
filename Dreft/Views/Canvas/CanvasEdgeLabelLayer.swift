import SwiftUI

/// Inline labels on connection lines — centered on the curve with editing support.
struct CanvasEdgeLabelLayer: View {
    let transform: CanvasViewTransform
    let cardIndex: [String: CanvasCard]
    let edges: [CanvasEdge]
    let positionOverrides: [String: CGPoint]
    let resizeOverrides: [String: CGRect]
    var editingEdgeID: String?
    @Binding var labelDraft: String
    var onCommit: (String, String) -> Void
    var onBeginEdit: (String) -> Void

    var body: some View {
        ZStack {
            ForEach(edges) { edge in
                if let midpoint = edgeMidpoint(for: edge) {
                    let screen = worldToScreen(midpoint)
                    let borderColor = edgeBorderColor(for: edge)
                    if editingEdgeID == edge.id {
                        edgeLabelEditor(for: edge, at: screen, borderColor: borderColor)
                    } else if let text = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                        edgeLabelDisplay(text, at: screen, edgeID: edge.id)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func edgeBorderColor(for edge: CanvasEdge) -> Color {
        if let hex = edge.colorHex, let color = Color(hexString: hex) {
            return color
        }
        return AppColors.edgeStroke
    }

    private func edgeLabelDisplay(_ text: String, at screen: CGPoint, edgeID: String) -> some View {
        EdgeLabelChrome(text: text)
            .position(screen)
            .allowsHitTesting(true)
            .contentShape(Rectangle())
            .highPriorityGesture(
                TapGesture(count: 2).onEnded {
                    onBeginEdit(edgeID)
                    labelDraft = text
                }
            )
    }

    private func edgeLabelEditor(for edge: CanvasEdge, at screen: CGPoint, borderColor: Color) -> some View {
        EdgeLabelField(
            text: $labelDraft,
            borderColor: borderColor,
            onCommit: { onCommit(edge.id, labelDraft) }
        )
        .position(screen)
        .allowsHitTesting(true)
    }

    private func worldToScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * transform.zoom + transform.x,
            y: point.y * transform.zoom + transform.y
        )
    }

    private func edgeMidpoint(for edge: CanvasEdge) -> CGPoint? {
        guard let from = cardIndex[edge.fromID] else { return nil }
        let p1 = CanvasGeometry.anchor(
            for: from,
            side: edge.fromSide,
            overrides: positionOverrides,
            resizeOverrides: resizeOverrides
        )
        let p2: CGPoint
        let toSide: CanvasSide?
        if let toID = edge.toID, let to = cardIndex[toID] {
            let side = edge.toSide ?? .left
            p2 = CanvasGeometry.anchor(for: to, side: side, overrides: positionOverrides, resizeOverrides: resizeOverrides)
            toSide = side
        } else if let point = edge.toPoint {
            p2 = point
            toSide = nil
        } else {
            return nil
        }
        return CanvasGeometry.pointOnCurve(
            from: p1,
            fromSide: edge.fromSide,
            to: p2,
            toSide: toSide,
            t: 0.5
        )
    }
}

private struct EdgeLabelChrome: View {
    let text: String

    var body: some View {
        Text(text)
            .font(EdgeLabelMetrics.font)
            .foregroundStyle(AppColors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.canvasBackground)
            .fixedSize()
    }
}

private struct EdgeLabelField: View {
    @Binding var text: String
    let borderColor: Color
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    private var fieldWidth: CGFloat {
        EdgeLabelMetrics.width(for: text, isEditing: true)
    }

    var body: some View {
        TextField("", text: $text, prompt: Text(""))
            .textFieldStyle(.plain)
            .font(EdgeLabelMetrics.font)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .frame(width: fieldWidth, height: EdgeLabelMetrics.height)
            .background(
                RoundedRectangle(cornerRadius: EdgeLabelMetrics.cornerRadius, style: .continuous)
                    .fill(AppColors.canvasBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: EdgeLabelMetrics.cornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .fixedSize()
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onSubmit(onCommit)
            .onChange(of: isFocused) { _, focused in
                if !focused { onCommit() }
            }
    }
}

private enum EdgeLabelMetrics {
    static let font = Font.system(size: 13, weight: .regular)
    static let height: CGFloat = 34
    static let cornerRadius: CGFloat = 10
    static let minWidth: CGFloat = 28
    static let maxWidth: CGFloat = 88

    static func width(for text: String, isEditing: Bool) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Compact vertical pill while waiting for the first character.
            return minWidth
        }
        let charWidth: CGFloat = 7.5
        let expanded = CGFloat(trimmed.count) * charWidth + 18
        return min(max(expanded, minWidth + 4), maxWidth)
    }
}
