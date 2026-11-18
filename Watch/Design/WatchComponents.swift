import SwiftUI
import WatchKit

// Reusable pieces for the workout pages (docs/research/watch-app-redesign-2026-11.md
// §4.8). Sizes:
// - any control: at least 44 × 44 pt, the HIG default (HIG Accessibility);
// - primary in-workout buttons (Done, Lap, Resume, Next set): 60 pt tall and
//   full width, the app's choice: about 36 % over 44 pt, inside the 20-40 %
//   that made up for walking in Schildbach & Rukzio (MobileHCI 2010); 7 mm
//   (≈ 44 pt) targets were missed 9.7 % of the time walking (Dobbelstein et
//   al., ISWC 2017);
// - secondary circles 48 pt, the controls grid 64 pt, chips 52 pt (app's
//   choices, all above 44 pt);
// - at most three glyph or two text buttons in a row (HIG Layout).

/// Height of a primary in-workout button (see above).
let watchPrimaryButtonHeight: CGFloat = 60

/// A filled button that shrinks a little when pressed (not with Reduce
/// Motion) and turns into a stroked outline in Always On.
struct WatchFilledButtonStyle: ButtonStyle {
    let tint: Color
    var cornerRadius: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(AlwaysOnFill(tint: tint, cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The page's one big action: 60 pt, full width, black label on a score tint.
/// `primaryAction` makes it answer double tap (Series 9 and later); only on a
/// page that doesn't scroll, and only on the page in front (HIG Gestures).
struct PrimaryWideButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var primaryAction = false
    var accessibilityLabel: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: watchPrimaryButtonHeight)
        }
        .buttonStyle(WatchFilledButtonStyle(tint: tint))
        .handGestureShortcut(.primaryAction, isEnabled: primaryAction)
        .accessibilityLabel(accessibilityLabel ?? title)
    }
}

/// A round glyph button with an optional caption under it. Glass, as watchOS
/// 26 draws controls (Liquid Glass is for controls, not content).
struct CircleButton: View {
    let title: String
    let systemImage: String
    var tint: Color = .white
    var size: CGFloat = 48
    var showsTitle = true
    var role: ButtonRole?
    /// For UI tests.
    var identifier: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(role: role, action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier ?? "")
            if showsTitle {
                Text(title)
                    .font(.footnote)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One choice in a `ChipGrid`.
nonisolated struct WatchChip: Identifiable, Hashable, Sendable {
    let id: Int
    let label: String
    var detail: String?
    let spoken: String
}

/// Chips in rows of `perRow` (at most three: HIG Layout), each `height` tall,
/// outlined in `tint`; the `highlighted` one filled. A tap clicks and fires `action`.
struct ChipGrid: View {
    let chips: [WatchChip]
    var perRow = 3
    var height: CGFloat = 52
    var tint: Color = WatchPalette.lifting
    var highlighted: Int?
    let action: (Int) -> Void
    @Environment(\.isLuminanceReduced) private var reduced

    var body: some View {
        let rows = stride(from: 0, to: chips.count, by: max(1, perRow)).map { start in
            Array(chips[start..<min(start + max(1, perRow), chips.count)])
        }
        VStack(spacing: 6) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row) { chip in
                        button(chip)
                    }
                }
            }
        }
    }

    private func button(_ chip: WatchChip) -> some View {
        let isOn = chip.id == highlighted
        return Button {
            WKInterfaceDevice.current().play(.click)
            action(chip.id)
        } label: {
            VStack(spacing: 0) {
                Text(chip.label)
                    .font(.headline)
                    .monospacedDigit()
                if let detail = chip.detail {
                    Text(detail)
                        .font(.footnote)
                        .lineLimit(1)
                        .foregroundStyle(isOn ? WatchPalette.onTint : .secondary)
                }
            }
            .foregroundStyle(isOn && !reduced ? WatchPalette.onTint : .primary)
            .frame(maxWidth: .infinity, minHeight: height)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if isOn && !reduced {
                    shape.fill(tint)
                } else {
                    shape.strokeBorder(tint.opacity(reduced ? 0.5 : 0.9), lineWidth: 1.5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chip.spoken)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A number with its unit and a small label: "5:12 /km · Pace".
struct MetricBlock: View {
    let value: String
    var unit: String?
    let label: String
    var role: WatchNumeral = .secondary
    var color: Color = .primary
    var spoken: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .numeral(role)
                    .alwaysOnPrimary(color)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? "\(label), \(value) \(unit ?? "")")
    }
}

/// The workout clock: time since `start` without pauses. A `Text` timer, so
/// the system keeps it current in Always On without waking the app
/// ("Designing your app for the Always On state"); frozen at `pausedAt`.
struct WorkoutClockText: View {
    /// The clock's start moved on by the pauses already over.
    let start: Date
    let pausedAt: Date?

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, pauseTime: pausedAt, countsDown: false, showsHours: true)
    }
}

/// The row at the top of every workout page: elapsed time (with a pause
/// glyph), a rest chip while a rest runs on another page, and heart rate in
/// its zone colour. 15 pt monospaced, combined for VoiceOver.
struct ToolbarStatus: View {
    let clockStart: Date?
    let pausedAt: Date?
    let heartRate: Double?
    let zone: Int?
    var restEndsAt: Date?
    var restStartedAt: Date?
    /// A rest that just ended while you were on another page flashes the chip.
    var flashRest = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                if pausedAt != nil {
                    Image(systemName: "pause.fill")
                        .foregroundStyle(WatchPalette.strain)
                        .accessibilityLabel("Paused")
                }
                if let clockStart {
                    WorkoutClockText(start: clockStart, pausedAt: pausedAt)
                        .foregroundStyle(pausedAt == nil ? WatchPalette.strain : .secondary)
                }
            }
            Spacer(minLength: 2)
            if let restEndsAt {
                HStack(spacing: 2) {
                    Image(systemName: "timer")
                    Text(timerInterval: min(restStartedAt ?? restEndsAt, restEndsAt)...restEndsAt, countsDown: true)
                }
                .padding(.horizontal, 5)
                .background(WatchPalette.lifting.opacity(0.25), in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rest")
            } else if flashRest {
                Text("Go")
                    .padding(.horizontal, 6)
                    .foregroundStyle(WatchPalette.onTint)
                    .background(WatchPalette.recovery, in: Capsule())
                    .accessibilityLabel("Rest over")
            }
            Spacer(minLength: 2)
            HStack(spacing: 2) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(WatchPalette.heart)
                    .accessibilityHidden(true)
                Text(heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                    .foregroundStyle(heartRate == nil ? Color.secondary : WatchPalette.zoneColor(zone))
                    .accessibilityLabel(heartRate.map { "Heart rate \(Int($0.rounded()))" } ?? "No heart rate yet")
            }
        }
        .statusFont()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
