import SwiftUI
import WatchKit

/// The cardio pages, left to right.
enum CardioPage: Hashable {
    case controls, metrics, media
}

/// A cardio workout in progress, laid out as Apple's Workout app (HIG
/// Workouts): Controls | Metrics | Now Playing, swiped sideways, opening on
/// Metrics. Metrics is a vertical stack of the pages chosen for the activity
/// (`CardioPageSettings`), moved through with the Digital Crown; the system's
/// double tap pages them too, so none of them has a double-tap action. A
/// split, lap or auto-pause banner shows over them.
struct CardioPagesView: View {
    @Environment(WatchCardioModel.self) private var cardio
    @State private var page: CardioPage = .metrics
    @State private var metric: CardioMetricPage = .main

    private var pages: [CardioMetricPage] {
        var pages = CardioPageSettings.shown(for: cardio.activity, hasTarget: cardio.interval != nil || cardio.tracker.band != nil)
        // An interval session always has its page, right after Main.
        if cardio.interval != nil, !pages.contains(.target) { pages.insert(.target, at: min(1, pages.count)) }
        return pages
    }

    var body: some View {
        TabView(selection: $page) {
            CardioControlsPage(page: $page)
                .tag(CardioPage.controls)
            metrics
                .tag(CardioPage.metrics)
            NowPlayingView()
                .tag(CardioPage.media)
        }
        .tabViewStyle(.page)
    }

    private var metrics: some View {
        TabView(selection: $metric) {
            ForEach(pages) { page in
                CardioMetricPageView(page: page)
                    .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .overlay(alignment: .top) {
            CardioBannerView()
        }
        .onChange(of: pages, initial: true) {
            if !pages.contains(metric) { metric = pages.first ?? .main }
        }
        // An interval session opens on its step.
        .onAppear { if cardio.interval != nil { metric = .target } }
    }
}
