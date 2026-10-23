import SwiftUI

/// Tensile's logo mark: a "T" made from a loaded barbell whose bar flexes
/// under the weight, white on the app's orange-pink-violet gradient. Matches
/// the app icon drawn by docs/brand/make_logo.py (same geometry).
struct AppLogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: Self.gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                TensileMark()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.18), radius: size * 0.02, y: size * 0.012)
                    .padding(size * 0.1)
                    .offset(y: -size * 0.016)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Strain yellow and orange, lifting pink, sleep violet (fixed, so the
    /// mark looks the same in light and dark mode, like the icon).
    static let gradient: [Color] = [
        Color(red: 1.0, green: 0.788, blue: 0.290),
        Color(red: 1.0, green: 0.478, blue: 0.102),
        Color(red: 0.941, green: 0.267, blue: 0.478),
        Color(red: 0.357, green: 0.357, blue: 0.941),
    ]
}

/// The barbell "T", in a unit square. Keep the numbers in sync with
/// `GEOMETRY` in docs/brand/make_logo.py.
nonisolated struct TensileMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }
        let start = (x: 0.14, y: 0.40), control = (x: 0.50, y: 0.25), end = (x: 0.86, y: 0.40)
        func onBar(_ t: Double) -> (x: Double, y: Double) {
            let a = (1 - t) * (1 - t), b = 2 * (1 - t) * t, c = t * t
            return (a * start.x + b * control.x + c * end.x, a * start.y + b * control.y + c * end.y)
        }

        var path = Path()
        // Stem.
        let stemWidth = 0.13
        path.addRoundedRect(
            in: CGRect(x: origin.x + (0.5 - stemWidth / 2) * side, y: origin.y + 0.30 * side,
                       width: stemWidth * side, height: 0.52 * side),
            cornerSize: CGSize(width: stemWidth * side / 2, height: stemWidth * side / 2)
        )
        // Flexed bar.
        var bar = Path()
        bar.move(to: point(start.x, start.y))
        bar.addQuadCurve(to: point(end.x, end.y), control: point(control.x, control.y))
        // Union rather than addPath, so overlapping pieces can't cancel out when filled.
        path = path.union(bar.strokedPath(StrokeStyle(lineWidth: 0.07 * side, lineCap: .round)))
        // Plates, square to the bar: (t, width, height), mirrored on the right.
        for (t0, width, height) in [(0.075, 0.085, 0.30), (0.145, 0.06, 0.21)] {
            for t in [t0, 1 - t0] {
                let a = onBar(t - 0.01), b = onBar(t + 0.01), centre = onBar(t)
                let angle = atan2(b.y - a.y, b.x - a.x)
                let plate = Path(
                    roundedRect: CGRect(x: -width * side / 2, y: -height * side / 2, width: width * side, height: height * side),
                    cornerRadius: 0.035 * side
                )
                let transform = CGAffineTransform(rotationAngle: angle)
                    .concatenating(CGAffineTransform(translationX: origin.x + centre.x * side, y: origin.y + centre.y * side))
                path = path.union(plate.applying(transform))
            }
        }
        return path
    }
}

/// Logo mark plus the app name, for the top of the Home screen.
struct AppLogoHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            AppLogoMark(size: 30)
            Text("Tensile")
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(LinearGradient(colors: Array(AppLogoMark.gradient.dropFirst()), startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tensile")
    }
}
