import SwiftUI

/// The app's logo mark: a ring of three gradient arcs (strain, recovery,
/// sleep) around a white disk with a heartbeat line. Matches the app icon
/// drawn by docs/brand/make_logo.py.
struct AppLogoMark: View {
    var size: CGFloat = 44

    var body: some View {
        let width = size * 0.16
        let gap = 15.0 / 360
        ZStack {
            arc(from: 0 + gap, to: 1.0 / 3 - gap, colors: [Theme.strainLight, Theme.strain, Theme.lifting], width: width)
            arc(from: 1.0 / 3 + gap, to: 2.0 / 3 - gap, colors: [Theme.recoveryHighLight, Theme.recoveryHigh], width: width)
            arc(from: 2.0 / 3 + gap, to: 1 - gap, colors: [Theme.sleepLight, Theme.sleep], width: width)
            Circle()
                .fill(Color.white)
                .padding(width * 1.25)
                .shadow(color: Color.black.opacity(0.12), radius: size * 0.04, y: size * 0.02)
            HeartbeatLine()
                .stroke(
                    LinearGradient(colors: [Theme.strain, Theme.lifting, Theme.sleep], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: max(1.5, size * 0.055), lineCap: .round, lineJoin: .round)
                )
                .padding(size * 0.3)
        }
        .padding(width / 2)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// One arc, as a fraction of the circle starting at 12 o'clock.
    private func arc(from: Double, to: Double, colors: [Color], width: CGFloat) -> some View {
        Circle()
            .trim(from: from, to: to)
            .stroke(
                AngularGradient(colors: colors, center: .center, startAngle: .degrees(360 * from), endAngle: .degrees(360 * to)),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: (colors.last ?? .clear).opacity(0.35), radius: width * 0.4)
    }
}

/// Flat line, small bump, tall spike, dip, flat.
nonisolated struct HeartbeatLine: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(Double, Double)] = [
            (-1.0, 0.0), (-0.48, 0.0), (-0.34, -0.22), (-0.2, 0.0), (-0.08, 0.0),
            (0.06, -0.78), (0.22, 0.62), (0.36, 0.0), (1.0, 0.0)
        ]
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: rect.midX + point.0 * rect.width / 2, y: rect.midY + point.1 * rect.height / 2)
            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// Logo mark plus the app name, for the top of the Home screen.
struct AppLogoHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            AppLogoMark(size: 34)
            Text("WorkoutApp")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting, Theme.sleep], startPoint: .leading, endPoint: .trailing))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("WorkoutApp")
    }
}
