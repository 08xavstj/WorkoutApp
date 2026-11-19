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
    /// The height a page in a paged `TabView` can use: the `TabView`'s height
    /// inside its safe area (under the toolbar, above the screen's edge),
    /// measured by the pager (`View.measuresWatchPages()`). Nil outside one.
    @Entry var watchPageHeight: CGFloat? = nil
}

extension View {
    /// On a paged `TabView`: measures the height its pages can use and hands
    /// it to them (`watchPageHeight`), since the pager itself offers a page
    /// no height, only "what you need" (so a page can't tell it's too tall).
    func measuresWatchPages() -> some View {
        modifier(WatchPageMeasure())
    }
}

private struct WatchPageMeasure: ViewModifier {
    @State private var height: CGFloat?
    #if DEBUG
    @State private var raw = ""
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.watchPageHeight, height)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom
            } action: { value in
                height = value > 0 ? value : nil
            }
            #if DEBUG
            .onGeometryChange(for: String.self) { proxy in
                let frame = proxy.frame(in: .global)
                return "pager \(Int(proxy.size.height)) y \(Int(frame.minY)) in \(Int(proxy.safeAreaInsets.top))/\(Int(proxy.safeAreaInsets.bottom))"
            } action: { raw = $0 }
            .overlay(alignment: .bottom) {
                if UserDefaults.standard.bool(forKey: "demoLift") {
                    Text(raw)
                        .font(.system(size: 11))
                        .foregroundStyle(.black)
                        .background(.yellow)
                        .padding(.bottom, 70)
                }
            }
            #endif
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
/// The space comes from the pager (`watchPageHeight`): a paged `TabView`
/// offers its pages no height and grows each one to fit, so a page can't
/// measure the space itself. Without a pager around it, the page is laid
/// out as it is (`full`).
struct FittedPage<Content: View>: View {
    var resetID: AnyHashable?
    @ViewBuilder let content: (WatchPageFit) -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.watchPageHeight) private var pageHeight
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
                    .frame(height: pageHeight)
                    #if DEBUG
                    .overlay(alignment: .center) {
                        if UserDefaults.standard.bool(forKey: "demoLift") {
                            Text("fit \(fit) c \(Int(contentHeight)) a \(Int(pageHeight ?? -1))")
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
        .task(id: Measurement(fit: fit, content: contentHeight, available: pageHeight ?? 0)) {
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
        guard let pageHeight, pageHeight > 0, contentHeight > pageHeight + Self.tolerance,
              let next = WatchPageFit(rawValue: fit.rawValue + 1) else { return }
        fit = next
    }
}
