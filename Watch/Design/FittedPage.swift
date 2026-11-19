import SwiftUI

/// How a workout page that shouldn't scroll fits the screen.
nonisolated enum WatchPageFit: Int, Comparable, Sendable {
    /// Everything at its full size.
    case full
    /// One step down: big numbers about a sixth smaller, the wide button and
    /// chips shorter (`NumeralFont`, `PrimaryWideButton`, `ChipGrid`).
    case compact
    /// Still too tall: the page scrolls, so double tap is off (HIG Gestures).
    case scrolls

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension EnvironmentValues {
    /// The fit `FittedPage` chose for the page around this view.
    @Entry var watchPageFit: WatchPageFit = .full
}

/// A workout page that fits the screen without scrolling when it can
/// (HIG Workouts: glanceable, no scrolling mid-set).
///
/// A page taller than the space it's given doesn't clip: SwiftUI centres it
/// and it spills over both ends, under the toolbar at the top (the rest
/// timer, the clock, heart rate) and under the page dots at the bottom. That
/// happened on the Set page at the 46 mm watch's default text size. So the
/// page measures itself: taller than the space, it steps down to `compact`;
/// still taller, it scrolls. At the accessibility text sizes it scrolls from
/// the start. The fit only steps down while the page is up (so sizes don't
/// jump between sets), and starts over when `resetID` or the text size changes.
struct FittedPage<Content: View>: View {
    var resetID: AnyHashable?
    @ViewBuilder let content: (WatchPageFit) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fit: WatchPageFit = .full
    @State private var contentHeight: CGFloat = 0
    @State private var availableHeight: CGFloat = 0

    /// Under half a point over is rounding, not overflow.
    private static var tolerance: CGFloat { 0.5 }

    private var current: WatchPageFit {
        dynamicTypeSize.isAccessibilitySize ? .scrolls : fit
    }

    var body: some View {
        let current = current
        Group {
            if current == .scrolls {
                ScrollView { content(current) }
            } else {
                content(current)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        contentHeight = height
                        stepDownIfTooTall()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        availableHeight = height
                        stepDownIfTooTall()
                    }
            }
        }
        .environment(\.watchPageFit, current)
        .onChange(of: dynamicTypeSize) { fit = .full }
        .onChange(of: resetID) { fit = .full }
    }

    private func stepDownIfTooTall() {
        guard availableHeight > 0, contentHeight > availableHeight + Self.tolerance,
              let next = WatchPageFit(rawValue: fit.rawValue + 1) else { return }
        // Measured again at the new fit before the next step.
        contentHeight = 0
        fit = next
    }
}
