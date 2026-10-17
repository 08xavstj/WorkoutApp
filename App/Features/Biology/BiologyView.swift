import SwiftUI
import SwiftData
import Charts

/// Long-term baselines: HRV trend and biomarkers.
struct BiologyView: View {
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]

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
                    SectionTitle(text: "Biomarkers")
                    markersCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.recoveryHigh, Theme.sleep])
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
                    Text("\(Int(baseline.rounded()))")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                    Text("ms")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    if let change = biology.hrvChangePercent {
                        Chip(
                            text: "\(change >= 0 ? "↑" : "↓") \(Int(abs(change).rounded()))% vs last month",
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
                            Text("Baseline \(Int(baseline.rounded()))")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    ForEach(biology.hrvSeries) { point in
                        AreaMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                            .foregroundStyle(LinearGradient(colors: [Theme.sleep.opacity(0.22), Theme.sleep.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Date", point.date), y: .value("HRV", point.value))
                            .foregroundStyle(Theme.sleep)
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
        .card()
    }

    private var markersCard: some View {
        VStack(spacing: 0) {
            if biology.markers.isEmpty {
                Text(biology.isLoading ? "Loading…" : "No biomarkers in Apple Health yet. Weight, body fat and VO₂ max appear here once Garmin or a smart scale writes them.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(biology.markers.enumerated()), id: \.element.id) { index, marker in
                if index > 0 {
                    Divider().overlay(Theme.separator).padding(.vertical, 12)
                }
                MarkerRow(marker: marker)
            }
        }
        .card()
    }
}

private struct MarkerRow: View {
    let marker: BiologyModel.Marker

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(marker.name)
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(marker.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primaryText)
                    Text(marker.unit)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 8)
            Chip(text: marker.status, color: color)
            Sparkline(values: marker.series, color: color)
                .frame(width: 92, height: 44)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch marker.tone {
        case .good: Theme.recoveryHigh
        case .neutral: Theme.strain
        case .caution: Theme.recoveryModerate
        }
    }
}
