import SwiftUI

/// Stylized purple gem mark used in vault manager and help.
struct DreftGemLogo: View {
    var body: some View {
        ZStack {
            GemFacetShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.62, blue: 0.98),
                            Color(red: 0.42, green: 0.28, blue: 0.85),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            GemFacetShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0),
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }
}

private struct GemFacetShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.62, y: 0))
        path.addLine(to: CGPoint(x: w * 0.98, y: h * 0.32))
        path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.96))
        path.addLine(to: CGPoint(x: w * 0.30, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.08))
        path.closeSubpath()
        return path
    }
}
