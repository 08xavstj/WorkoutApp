import SwiftUI
import SwiftData
import Charts

/// Long-term baselines: HRV trend and biomarkers.
struct BiologyView: View {
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(VitalsModel.self) private var vitals
    @Environment(\.healthClient) private var health
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var selected: VitalsModel.Stat?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Biology")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        Text("Your long-term baselines")
                            .font(.title3)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.top, 8)
                    hrvCard
                    ForEach(VitalsModel.Category.allCases) { category in
                        SectionTitle(text: category.rawValue)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(vitals.stats(in: category)) { stat in
                                Button { selected = stat } label: {
                                    VitalTile(stat: stat, colors: VitalTile.colors(for: category))
                                }
                                .buttonStyle(.plain)
                            }
                            if category == .body, let protein = biology.markers.first(where: { $0.id == "protein" }) {
                                VitalTile(stat: VitalsModel.Stat(
                                    id: "protein", category: .body, title: "Protein · 7 days", icon: "fork.knife",
                                    value: protein.value, unit: protein.unit, status: protein.status,
                                    tone: protein.tone == .caution ? .caution : .good, series: protein.series
                                ), colors: VitalTile.colors(for: .body))
                            }
                        }
                    }
                    if vitals.stats.isEmpty {
                        Text(vitals.isLoading ? "Loading your health stats…" : "No health stats yet. Turn on Apple Health sharing in Garmin Connect (More → Settings → Connected Apps → Apple Health).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .card()
                    }
                    Text("Garmin Connect shares heart rate, resting heart rate, sleep, steps, distance, floors, energy, workouts, and (on supported watches) blood oxygen and respiration with Apple Health. Body Battery, Garmin stress and HRV stay in Garmin Connect, so stress here is estimated from heart rate.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.butter, Theme.Wash.lime, Theme.Wash.sky])
            }
            .sheet(item: $selected) { stat in
                VitalDetailView(stat: stat, colors: VitalTile.colors(for: stat.category))
                    .presentationDetents([.medium, .large])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        guard let health else { return }
        var manual: [Date: Double] = [:]
        for reading in hrvReadings where manual[reading.date] == nil {
            manual[reading.date] = reading.milliseconds
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let recent = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.map(\.strainSummary)
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent)
        await biology.refresh(health: health, settings: settings, manualHRV: manual, proteinTarget: metrics.proteinTarget)
    }

    private var hrvCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "HRV baseline")
                Spacer()
                Text("90 days")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let baseline = biology.hrvBaseline {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(whole(baseline.rounded()))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Theme.recoveryHigh, Theme.oxygen], startPoint: .leading, endPoint: .trailing))
                    Text("ms")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    if let change = biology.hrvChangePercent {
                        Chip(
                            text: "\(change >= 0 ? "↑" : "↓") \(whole(abs(change).rounded()))% vs last month",
                            color: change >= 0 ? Theme.recoveryHigh : Theme.recoveryModerate
                        )
                    }
                }
                .foregroundStyle(Theme.primaryText)
                Chart {
                    RuleMark(y: .value("Baseline", baseline))
                        .foregroundStyle(Theme.secondaryText.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Baseline \(whole(baseline.rounded()))")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    ForEach(biology.hrvSeries) { point in
                        AreaMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.recoveryHigh.opacity(0.3), Theme.oxygen.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.oxygen, Theme.recoveryHigh], startPoint: .leading, endPoint: .trailing))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 170)
            } else {
                Text("No HRV yet. Garmin doesn't share HRV with Apple Health, so add last night's value with Add HRV on the Home screen.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.recoveryHigh)
    }
}

/// One health stat: icon, value, status and a little trend line.
struct VitalTile: View {
    let stat: VitalsModel.Stat
    let colors: [Color]

    static func colors(for category: VitalsModel.Category) -> [Color] {
        switch category {
        case .heart: Theme.heartColors
        case .breathing: Theme.oxygenColors
        case .activity: Theme.strainColors
        case .body: Theme.nutritionColors
        }
    }

    static func color(for tone: VitalsModel.Tone) -> Color {
        switch tone {
        case .good: Theme.recoveryHigh
        case .neutral: Theme.secondaryText
        case .caution: Theme.recoveryModerate
        }
    }

    var body: some View {
        let main = colors.last ?? Theme.strain
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: stat.icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: .circle)
                    .shadow(color: main.opacity(0.35), radius: 4, y: 2)
                Text(stat.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            if let value = stat.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(stat.unit)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("No data")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
            }
            if let status = stat.status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.color(for: stat.tone))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if stat.series.count > 1 {
                Sparkline(values: Array(stat.series.suffix(30)), color: main)
                    .frame(height: 34)
            } else if let gauge = stat.gauge {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * gauge))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(RadialGradient(colors: [main.opacity(0.14), main.opacity(0)], center: .topLeading, startRadius: 0, endRadius: 170))
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}

/// A stat's history over the last weeks, with an explanation.
struct VitalDetailView: View {
    let stat: VitalsModel.Stat
    let colors: [Color]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let main = colors.last ?? Theme.strain
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(stat.value ?? "No data")
                            .font(.system(size: 52, weight: .bold, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        Text(stat.unit)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let status = stat.status {
                        Chip(text: status, color: VitalTile.color(for: stat.tone))
                    }
                    if stat.series.count > 1 {
                        Chart(stat.series) { point in
                            AreaMark(x: .value("Date", point.date), y: .value(stat.title, point.value))
                                .foregroundStyle(LinearGradient(colors: [main.opacity(0.3), main.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Date", point.date), y: .value(stat.title, point.value))
                                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 200)
                        .card()
                    }
                    if let footnote = stat.footnote {
                        Text(footnote)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if stat.value == nil {
                        Text("Nothing in Apple Health yet. If your Garmin records this, check that Garmin Connect's Apple Health sharing is on and that WorkoutApp can read it (Health app → profile → Apps → WorkoutApp).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle(stat.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
