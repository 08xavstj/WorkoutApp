import SwiftUI
import AppCore

/// Health › All measures: one row per category (Heart, Sleep, Breathing &
/// temperature, Activity, Body) with how many measures have data and how many
/// to watch, each pushing that category's tile grid. Replaces a wall of ~30
/// equal tiles on the front page (ux-audit.md B2; HIG Layout, "use … nested
/// views to reduce how much content to initially display", P7, P8).
struct AllMeasuresSection: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(BodyMeasurementsStore.self) private var measurements

    private var extras: HealthExtraStats {
        HealthExtraStats(biology: biology, metrics: metrics, settings: settings, measurements: measurements)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("All measures")
            if vitals.stats.isEmpty {
                Text(vitals.isLoading ? "Loading your health stats…" : "No health stats yet. Turn on Apple Health sharing in your watch's app (Garmin Connect: More → Settings → Connected Apps → Apple Health).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            }
            VStack(spacing: 0) {
                ForEach(VitalsModel.Category.allCases) { category in
                    CategoryRow(category: category, stats: extras.allStats(in: category, vitals: vitals))
                    if category != VitalsModel.Category.allCases.last {
                        Divider()
                    }
                }
            }
            .card()
        }
    }
}

/// "Heart · 6 measures · 1 to watch", pushing the category page.
private struct CategoryRow: View {
    let category: VitalsModel.Category
    let stats: [VitalsModel.Stat]

    private var withData: Int { stats.filter { $0.value != nil }.count }
    /// Measures whose latest value is flagged (amber), never ones without data.
    private var toWatch: Int { stats.filter { $0.value != nil && $0.tone == .caution }.count }

    private var detail: String {
        guard withData > 0 else { return "No data yet" }
        // One form on every row: "5 of 6 with data", "6 of 6 with data".
        let measures = "\(withData) of \(stats.count) with data"
        return toWatch > 0 ? "\(measures) · \(toWatch) to watch" : measures
    }

    var body: some View {
        HealthNavigationRow(
            title: category.rawValue,
            detail: detail,
            icon: CategoryView.icon(for: category),
            color: VitalTile.colors(for: category).last ?? Theme.secondaryText,
            hint: "Shows every \(category.rawValue.lowercased()) measure"
        ) {
            CategoryView(category: category)
        }
    }
}

/// Every measure in one category as the tile grid, each tile pushing its
/// history. The yearly STOP-Bang screen sits on the Breathing page, next to
/// overnight blood oxygen.
struct CategoryView: View {
    let category: VitalsModel.Category
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(BodyMeasurementsStore.self) private var measurements
    @State private var showingStopBang = false

    static func icon(for category: VitalsModel.Category) -> String {
        switch category {
        case .heart: "heart.fill"
        case .sleep: "bed.double.fill"
        case .breathing: "lungs.fill"
        case .activity: "figure.walk"
        case .body: "figure.stand"
        }
    }

    private var stats: [VitalsModel.Stat] {
        HealthExtraStats(biology: biology, metrics: metrics, settings: settings, measurements: measurements)
            .allStats(in: category, vitals: vitals)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if stats.isEmpty {
                    Text(vitals.isLoading ? "Loading your health stats…" : "No health stats yet.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                TileGrid {
                    ForEach(stats) { stat in
                        VitalTileLink(stat: stat, colors: VitalTile.colors(for: category))
                    }
                }
                if category == .breathing {
                    StopBangSummaryCard { showingStopBang = true }
                }
            }
            .padding()
            .lockedToScreenWidth()
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle(category.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingStopBang) { StopBangView() }
    }
}

/// A tile that pushes the stat's history.
private struct VitalTileLink: View {
    let stat: VitalsModel.Stat
    let colors: [Color]

    var body: some View {
        NavigationLink {
            VitalDetailView(stat: stat, colors: colors, pushed: true)
        } label: {
            VitalTile(stat: stat, colors: colors)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows history")
    }
}
