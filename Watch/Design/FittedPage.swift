import SwiftUI

/// How a workout page that shouldn't scroll fits the screen.
nonisolated enum WatchPageFit: Int, Comparable, Sendable {
    /// Everything at its full size.
    case full
    /// One step down: big numbers about a sixth smaller, the wide button and
    /// chips shorter (`NumeralFont`, `PrimaryWideButton`, `ChipGrid`).
    case compact
    /// Two steps down: big numbers about 30 % smaller, the wide button and
    /// chips at their floors (the 42 mm watch at the larger text sizes).
    case tight
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
/// happened on the Set page on the 42 mm watch, and on the 46 mm at the
/// larger text sizes (seen in the watchOS simulator and on the owner's
/// wrist). So the page measures itself: taller than the space, it steps down
/// to `compact`, then `tight`; still taller, it scrolls. At the accessibility
/// text sizes it scrolls from the start. The fit only steps down while the
/// page is up (so sizes don't jump between sets), and starts over when
/// `resetID` or the text size changes.
///
/// The space is read with a `GeometryReader`, which takes the size it's
/// offered whatever its content needs: a watch page in a paged `TabView`
/// grows to fit its content, so measuring the page itself never shows the
/// overflow.
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
                GeometryReader { proxy in
                    content(current)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onChange(of: proxy.size.height, initial: true) { availableHeight = proxy.size.height }
                        #if DEBUG
                        .overlay(alignment: .center) {
                            if UserDefaults.standard.bool(forKey: "demoLift") {
                                let frame = proxy.frame(in: .global)
                                Text("fit \(fit) c \(Int(contentHeight)) a \(Int(availableHeight)) y \(Int(frame.minY))-\(Int(frame.maxY)) s \(Int(proxy.safeAreaInsets.top))/\(Int(proxy.safeAreaInsets.bottom))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.black)
                                    .background(.yellow)
                            }
                        }
                        #endif
                }
            }
        }
        // Only a measurement that holds for a moment counts: while a page
        // appears or slides in, its sizes pass through values it never shows.
        .task(id: Measurement(fit: fit, content: contentHeight, available: availableHeight)) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            stepDownIfTooTall()
        }
        .environment(\.watchPageFit, current)
        .onChange(of: dynamicTypeSize) { fit = .full }
        .onChange(of: resetID) { fit = .full }
    }

    private struct Measurement: Equatable {
        var fit: WatchPageFit
        var content: CGFloat
        var available: CGFloat
    }

    private func stepDownIfTooTall() {
        #if DEBUG
        print("FittedPage fit=\(fit) content=\(contentHeight) available=\(availableHeight)")
        #endif
        guard availableHeight > 0, contentHeight > availableHeight + Self.tolerance,
              let next = WatchPageFit(rawValue: fit.rawValue + 1) else { return }
        fit = next
    }
}
