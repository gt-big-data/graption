import SwiftUI

/// The Graption mark: two eyes above a speech bubble with three peach dots.
/// Drawn in a 100 x 100 space and scaled to fit the frame.
public struct GraptionLogo: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            let origin = CGPoint(
                x: (size.width - 100 * scale) / 2,
                y: (size.height - 100 * scale) / 2
            )
            func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
                CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale)
            }
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
            }

            let line = StrokeStyle(lineWidth: 5 * scale, lineCap: .round, lineJoin: .round)
            let cream = GraphicsContext.Shading.color(.graptionAccent)

            // Eyes
            context.stroke(Path(ellipseIn: rect(26.5, 4, 20, 20)), with: cream, style: line)
            context.stroke(Path(ellipseIn: rect(53.5, 4, 20, 20)), with: cream, style: line)

            // Speech bubble with its tail at the bottom left, as one outline
            let corners: [(CGFloat, CGFloat, CGFloat)] = [
                (90, 38, 9), (90, 72, 9), (44, 72, 1), (26, 90, 1.5), (26, 72, 1), (10, 72, 9), (10, 38, 9),
            ]
            var bubble = Path()
            bubble.move(to: point(50, 38))
            for index in corners.indices {
                let (x, y, radius) = corners[index]
                let (nextX, nextY, _) = corners[(index + 1) % corners.count]
                bubble.addArc(tangent1End: point(x, y), tangent2End: point(nextX, nextY), radius: radius * scale)
            }
            bubble.closeSubpath()
            context.stroke(bubble, with: cream, style: line)

            // Typing dots
            for x in [39, 50, 61] as [CGFloat] {
                context.fill(Path(ellipseIn: rect(x - 5.5, 49.5, 11, 11)), with: .color(.graptionPeach))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    GraptionLogo()
        .frame(width: 200, height: 200)
        .padding()
        .background(Color.graptionBackground)
}
