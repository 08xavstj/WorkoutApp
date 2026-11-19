import SwiftUI
import WatchKit

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
    /// The space a page in a paged `TabView` can use, measured by the pager
    /// (`View.measuresWatchPages()`). Nil outside one.
    @Entry var watchPageSpace: WatchPageSpace? = nil
}

/// The space a watch page can use: the pager's own height (under the toolbar,
/// above the safe area's bottom) and how far below it a page may reach, down
/// to just above the page dots.
nonisolated struct WatchPageSpace: Equatable, Sendable {
    var pagerHeight: CGFloat
    var below: CGFloat
    var height: CGFloat { pagerHeight + below }
}

extension View {
    /// On a paged `TabView`: measures the space its pages can use and hands it
    /// to them (`watchPageSpace`). The pager offers a page no height, only
    /// "what you need", and grows the page to fit, so a page that's too tall
    /// can't tell: it just spills over the toolbar and the page dots.
    func measuresWatchPages() -> some View {
        modifier(WatchPageMeasure())
    }
}

private struct WatchPageMeasure: ViewModifier {
    /// Room kept clear above the screen's bottom edge for the page dots
    /// (app's choice: the dots sit about 6 pt from the edge and are about 6 pt
    /// tall; HIG Page controls: content shouldn't cover them).
    private static let dotsClearance: CGFloat = 16

    @State private var space: WatchPageSpace?

    nonisolated private struct Frame: Equatable {
        var height: CGFloat
        var maxY: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .environment(\.watchPageSpace, space)
            // The pager already sits inside the safe area (under the toolbar);
            // its own size is the space, whatever insets it reports.
            .onGeometryChange(for: Frame.self) { proxy in
                Frame(height: proxy.size.height, maxY: proxy.frame(in: .global).maxY)
            } action: { frame in
                guard frame.height > 0 else { return }
                let screen = WKInterfaceDevice.current().screenBounds.height
                space = WatchPageSpace(pagerHeight: frame.height,
                                       below: max(0, screen - Self.dotsClearance - frame.maxY))
            }
    }
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
/// The space comes from the pager (`watchPageSpace`): a paged `TabView`
/// offers its pages no height and grows each one to fit, so a page can't
/// measure the space itself. The page is laid out at the pager's height plus
/// the room below it down to the page dots, and reports only the pager's
/// height, so the pager doesn't centre it (which would push it up under the
/// toolbar). Without a pager around it, the page is laid out as it is.
struct FittedPage<Content: View>: View {
    var resetID: AnyHashable?
    @ViewBuilder let content: (WatchPageFit) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.watchPageSpace) private var space
    @State private var fit: WatchPageFit = .full
    @State private var contentHeight: CGFloat = 0

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
                // Offered exactly the page's height, the content fills it
                // (Done at the bottom); taller than that, it reports its own
                // height, and the page steps down.
                content(current)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    .frame(maxWidth: .infinity)
                    .frame(height: space?.height, alignment: .top)
                    .padding(.bottom, -(space?.below ?? 0))
                    #if DEBUG
                    .overlay(alignment: .center) {
                        if UserDefaults.standard.bool(forKey: "demoFitDebug") {
                            Text("fit \(fit) c \(Int(contentHeight)) a \(Int(space?.height ?? -1))")
                                .font(.system(size: 11))
                                .foregroundStyle(.black)
                                .background(.yellow)
                        }
                    }
                    #endif
            }
        }
        // Only a measurement that holds for a moment counts: while a page
        // appears or slides in, its sizes pass through values it never shows.
        .task(id: Measurement(fit: fit, content: contentHeight, available: space?.height ?? 0)) {
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
        guard let space, space.height > 0, contentHeight > space.height + Self.tolerance,
              let next = WatchPageFit(rawValue: fit.rawValue + 1) else { return }
        fit = next
    }
}
