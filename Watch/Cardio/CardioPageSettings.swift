import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// One of the cardio metric pages (docs/research/watch-app-redesign-2026-11.md §4.5.2).
/// Raw values are stored per activity, so cases can be added but never renamed.
nonisolated enum CardioMetricPage: String, CaseIterable, Identifiable, Sendable {
    case main, zones, pace, speed, elevation, splits, target

    var id: String { rawValue }

    var title: String {
        switch self {
        case .main: "Main"
        case .zones: "Heart zones"
        case .pace: "Pace"
        case .speed: "Speed"
        case .elevation: "Elevation"
        case .splits: "Splits"
        case .target: "Target"
        }
    }

    var systemImage: String {
        switch self {
        case .main: "gauge.with.dots.needle.50percent"
        case .zones: "heart.fill"
        case .pace: "speedometer"
        case .speed: "speedometer"
        case .elevation: "mountain.2.fill"
        case .splits: "chart.bar.fill"
        case .target: "scope"
        }
    }

    /// Whether the page means anything for `activity`: pace on foot, speed on
    /// a bike or skis, splits where there's a distance, elevation outdoors,
    /// target only for steady cardio (sports record with no target,
    /// `CardioActivity.takesTarget`). Main and Heart zones always.
    func isOffered(for activity: CardioActivity) -> Bool {
        switch self {
        case .main, .zones: true
        case .pace: activity.movement == .onFoot
        case .speed: activity.movement.showsSpeed
        case .splits: activity.movement != .stationary
        case .elevation: activity.isOutdoor == true
        case .target: activity.takesTarget
        }
    }
}

/// Which metric pages each activity shows, in what order. Chosen in Home ›
/// Settings › "Pages for Outdoor run" and kept per activity in UserDefaults,
/// as Apple's Workout app keeps its views per workout (app's choice: choosing
/// pages covers most needs with far less UI than a field editor).
nonisolated enum CardioPageSettings {
    private static func key(_ activity: CardioActivity) -> String {
        "cardioPages.\(activity.rawValue)"
    }

    /// The default pages: Main, Heart zones, Pace (on foot) or Speed, Splits,
    /// Elevation (outdoors) and Target (when one is set). Sports get Main and
    /// Heart zones.
    static func defaults(for activity: CardioActivity) -> [CardioMetricPage] {
        CardioMetricPage.allCases.filter { $0.isOffered(for: activity) }
    }

    /// The pages chosen for `activity`, offered ones only, Main always first.
    static func pages(for activity: CardioActivity) -> [CardioMetricPage] {
        guard let stored = UserDefaults.standard.string(forKey: key(activity)) else { return defaults(for: activity) }
        var pages = stored.split(separator: ",").compactMap { CardioMetricPage(rawValue: String($0)) }
            .filter { $0.isOffered(for: activity) }
        pages.removeAll { $0 == .main }
        return [.main] + pages
    }

    static func save(_ pages: [CardioMetricPage], for activity: CardioActivity) {
        UserDefaults.standard.set(pages.map(\.rawValue).joined(separator: ","), forKey: key(activity))
    }

    /// The pages to show now: the target page only while a target (or an
    /// interval session) is set.
    static func shown(for activity: CardioActivity, hasTarget: Bool) -> [CardioMetricPage] {
        pages(for: activity).filter { $0 != .target || hasTarget }
    }
}

/// Settings › Pages for one activity: each offered page with a switch, in
/// the order shown; drag to reorder. Main is always on.
struct CardioPagesEditor: View {
    let activity: CardioActivity
    @State private var rows: [Row] = []

    nonisolated struct Row: Identifiable, Equatable, Sendable {
        var page: CardioMetricPage
        var isOn: Bool
        var id: String { page.rawValue }
    }

    var body: some View {
        List {
            ForEach($rows) { $row in
                Toggle(isOn: $row.isOn) {
                    Label(row.page.title, systemImage: row.page.systemImage)
                }
                .disabled(row.page == .main)
            }
            .onMove { from, to in
                rows.move(fromOffsets: from, toOffset: to)
            }
            Section {
                Button("Reset to default") {
                    rows = Self.rows(for: CardioPageSettings.defaults(for: activity), activity: activity)
                }
            } footer: {
                Text("Turn the Digital Crown during a workout to move between these pages. Touch and hold a page to reorder it.")
            }
        }
        .navigationTitle(activity.title)
        .onAppear {
            rows = Self.rows(for: CardioPageSettings.pages(for: activity), activity: activity)
        }
        .onChange(of: rows) {
            CardioPageSettings.save(rows.filter { $0.isOn || $0.page == .main }.map(\.page), for: activity)
        }
    }

    /// Chosen pages first, in order, then the rest switched off.
    private static func rows(for chosen: [CardioMetricPage], activity: CardioActivity) -> [Row] {
        let offered = CardioMetricPage.allCases.filter { $0.isOffered(for: activity) }
        return chosen.map { Row(page: $0, isOn: true) } + offered.filter { !chosen.contains($0) }.map { Row(page: $0, isOn: false) }
    }
}
