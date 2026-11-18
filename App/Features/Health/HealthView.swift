import SwiftUI
import SwiftData
import Charts
import AppCore

/// The Health tab: long-term trends and health records
/// (docs/research/ux-audit.md 4.6 Health). One primary card (the HRV
/// baseline), then Key measures, All measures by category, Records and
/// Patterns, each row pushing its page. Less on the front page with details on
/// demand: people understand the key numbers better when fewer are shown at
/// once (Peters et al., Med Care Res Rev 2007;64:169; ux-audit.md P7, P8, P16).
struct HealthView: View {
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(\.healthClient) private var health
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HRVBaselineCard()
                    OuraCard()
                    // Oura's unvalidated scores, apart from Tensile's own (owner's request, 18 Nov 2026).
                    OuraOwnNumbersCard()
                    // This week's changes and the long-run measures (`LongevityView.swift`).
                    HealthHighlightsSection()
                    KeyMeasuresSection()
                    AllMeasuresSection()
                    RecordsSection()
                    PatternsSection()
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
            .background(Theme.background)
            .navigationTitle("Health")
            .navigationSubtitle("Trends and records")
            .tabToolbar()
            .task { await load(force: false) }
            .refreshable { await load(force: true) }
        }
    }

    /// Opening the tab reloads only what is over 10 minutes old (the main
    /// refresh keeps the stats current while the app is open; the app's
    /// choice); pull to refresh reloads everything.
    private func load(force: Bool) async {
        guard let health else { return }
        func stale(_ date: Date?) -> Bool { force || date.map { Date.now.timeIntervalSince($0) > 10 * 60 } ?? true }
        let manual = RootView.hrvByMorning(hrvReadings, camera: false)
        // 28 days: the VO₂ max activity estimate averages 4 weeks of lifting (`VitalsModel`).
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        let recent = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.map(\.strainSummary)
        if stale(vitals.lastRefreshed) {
            await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent,
                                 sleepConsistency: metrics.sleepConsistency, sleepSpreadMinutes: metrics.sleepSpreadMinutes)
        }
        if stale(checkIns.insightsUpdated) {
            await checkIns.refreshInsights(health: health, manualHRV: manual)
        }
        if stale(biology.lastRefreshed) {
            await biology.refresh(health: health, settings: settings, manualHRV: manual, proteinTarget: metrics.proteinTarget,
                                  scoredVO2: vitals.vo2ForScores)
        }
        vitals.setHRVSeries(biology.hrvSeries)
    }
}

// MARK: - Shared page pieces

/// Wraps a view in its own NavigationStack only when it's shown as a sheet;
/// when pushed, it uses the stack it was pushed onto, so there is never a
/// stack inside a stack (ux-audit.md 4.1 rule 5). The record views use it so
/// they work both pushed from Health › Records and as the root sheets
/// `AppRouter` opens from notifications and links. (Same idea as the private
/// helper in `MyGymView`.)
struct SheetNavigationStack<Content: View>: View {
    let isSheet: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if isSheet {
            NavigationStack { content }
        } else {
            content
        }
    }
}

/// A pushed page of cards with an inline title, for Health's detail pages
/// (patterns, Garmin help).
struct HealthDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding()
            .lockedToScreenWidth()
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - HRV baseline (primary card)

/// The tab's primary card (mockup `04-biology.png`): 90-day HRV, the
/// baseline, change against last month and the 7-day normal range.
struct HRVBaselineCard: View {
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "HRV baseline")
                Spacer()
                // Geometric mean of 90 nights; the coach and Recovery use a 30-night baseline.
                Text("90-day average")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let baseline = biology.hrvBaseline {
                headline(baseline)
                trendLine
                HRVBaselineChart(baseline: baseline, series: biology.hrvSeries, trend: metrics.recovery?.hrvTrend)
                    .frame(height: 170)
            } else {
                Text("No HRV yet. If your watch doesn't share HRV with Apple Health (Garmin doesn't), add last night's value in the Log tab under Overnight HRV.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.recoveryHigh)
    }

    private func headline(_ baseline: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(whole(baseline.rounded()))")
                .heroNumberFont()
                .foregroundStyle(LinearGradient(colors: [Theme.recoveryHigh, Theme.oxygen], startPoint: .leading, endPoint: .trailing))
            Text("ms")
                .font(Theme.Typography.heroUnit)
                .foregroundStyle(Theme.secondaryText)
            Spacer()
            if let change = biology.hrvChangePercent {
                // Neutral while the 7-day average is in your normal range, so an
                // amber arrow never sits next to a green "in range".
                let inRange = metrics.recovery?.hrvTrend?.status == .within
                Chip(
                    text: "\(change >= 0 ? "↑" : "↓") \(whole(abs(change).rounded()))% vs last month",
                    color: inRange ? Theme.secondaryText : (change >= 0 ? Theme.recoveryHigh : Theme.recoveryModerate)
                )
            }
        }
        .foregroundStyle(Theme.primaryText)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trendLine: some View {
        if let trend = metrics.recovery?.hrvTrend {
            let color: Color = trend.status == .below ? Theme.recoveryModerateText : Theme.recoveryHighText
            Text("7-day average \(Int(trend.average.rounded())) ms · normal \(Int(trend.normalRange.lowerBound.rounded()))–\(Int(trend.normalRange.upperBound.rounded())) ms · \(trend.status == .below ? "below normal: train easy" : (trend.status == .above ? "above normal" : "in range"))")
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

/// 90 days of HRV against the baseline (dashed) and the 7-day normal band.
private struct HRVBaselineChart: View {
    let baseline: Double
    let series: [DatedValue]
    let trend: RecoveryCalculator.HRVTrend?

    /// 7-day rolling average of the nightly values.
    private var rolling: [DatedValue] {
        PersonalBaseline.rollingAverage(series.map { DayValue(date: $0.date, value: $0.value) })
            .map { DatedValue(date: $0.date, value: $0.value) }
    }

    /// From the data (and band and baseline), padded, at least 10 ms tall:
    /// an area from zero flattens 40-50 ms into a straight line (`ChartScale`).
    private var domain: ClosedRange<Double> {
        var values = series.map(\.value) + [baseline]
        if let trend { values += [trend.normalRange.lowerBound, trend.normalRange.upperBound] }
        return ChartScale.domain(values, minimumSpan: ChartScale.minimumSpan(unit: "ms", typical: baseline)) ?? 0...100
    }

    var body: some View {
        let scale = domain
        Chart {
            if let trend {
                RectangleMark(
                    yStart: .value("Normal low", trend.normalRange.lowerBound),
                    yEnd: .value("Normal high", trend.normalRange.upperBound)
                )
                .foregroundStyle(Theme.recoveryHigh.opacity(0.10))
            }
            RuleMark(y: .value("Baseline", baseline))
                .foregroundStyle(Theme.secondaryText.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            // Nightly HRV swings a lot, so each night is a faint dot and the
            // line is the 7-day rolling average (the same smoothing as the
            // normal band; Plews et al., Sports Med 2013).
            ForEach(series) { point in
                PointMark(x: .value("Date", point.date), y: .value("Nightly HRV", point.value))
                    .foregroundStyle(Theme.secondaryText.opacity(0.35))
                    .symbolSize(10)
            }
            ForEach(rolling) { point in
                AreaMark(x: .value("Date", point.date), yStart: .value("Floor", scale.lowerBound), yEnd: .value("7-day HRV", point.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.recoveryHigh.opacity(0.3), Theme.oxygen.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", point.date), y: .value("7-day HRV", point.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.oxygen, Theme.recoveryHigh], startPoint: .leading, endPoint: .trailing))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
            }
            // Drawn last, on a capsule, so the line never runs through the label.
            RuleMark(y: .value("Baseline", baseline))
                .foregroundStyle(.clear)
                .annotation(position: .top, alignment: .leading) {
                    Text("Baseline \(whole(baseline.rounded()))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.card.opacity(0.9), in: .capsule)
                }
        }
        .chartYScale(domain: scale)
        .chartYAxis(.hidden)
        // Room after the last day so the last month label isn't cut off.
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        }
        // A chart states its message for VoiceOver too (HIG Charts; ux-audit.md P15).
        .accessibilityLabel("HRV over the last 90 days")
        .accessibilityValue(spokenSummary)
    }

    private var spokenSummary: String {
        let base = "Baseline \(whole(baseline.rounded())) milliseconds"
        guard let latest = series.last else { return base }
        return base + ", latest \(whole(latest.value.rounded()))"
    }
}

// MARK: - Tiles

/// One health stat: icon, value, status and a little trend line.
struct VitalTile: View {
    let stat: VitalsModel.Stat
    let colors: [Color]

    static func colors(for category: VitalsModel.Category) -> [Color] {
        switch category {
        case .heart: Theme.heartColors
        case .sleep: Theme.sleepColors
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
                    .accessibilityHidden(true)
                Text(stat.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            valueLine
            if let status = stat.status {
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textColor(for: Self.color(for: stat.tone)))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trendVisual(main: main)
        }
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var valueLine: some View {
        if let value = stat.value {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .tileNumberFont()
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(stat.unit)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
        } else {
            Text(stat.emptyText ?? "No data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// Day totals (steps, energy) leave out today until the evening, so the
    /// line doesn't plunge to a half-finished day (`dayTotalVerdictHour`).
    /// Sleep bars are whole nights and stay.
    private static func sparklineSeries(_ stat: VitalsModel.Stat) -> [DatedValue] {
        guard stat.chart == .bars, stat.nights.isEmpty, !stat.isHours,
              Calendar.current.component(.hour, from: .now) < VitalsModel.dayTotalVerdictHour,
              let last = stat.series.last, Calendar.current.isDateInToday(last.date),
              stat.series.count > 2 else { return stat.series }
        return Array(stat.series.dropLast())
    }

    @ViewBuilder
    private func trendVisual(main: Color) -> some View {
        if stat.series.count > 1 {
            let recent = Array(Self.sparklineSeries(stat).suffix(30))
            let typical = recent.map(\.value).reduce(0, +) / Double(max(1, recent.count))
            Sparkline(values: recent, color: main, minimumSpan: ChartScale.minimumSpan(unit: stat.unit, typical: typical))
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
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Patterns cards

/// "What affects you": patterns between check-in answers and next-morning data.
struct InsightsCard: View {
    let insights: [CheckInInsights.Insight]
    let daysLeft: Int
    /// Habits still being collected, closest first.
    var progress: [CheckInInsights.FactorProgress] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "What affects you")
            if insights.isEmpty {
                Text(daysLeft > 0
                     ? "Do the morning and evening check-ins for \(daysLeft) more day\(daysLeft == 1 ? "" : "s") and your personal patterns appear here: what lowers your HRV, raises your resting heart rate or hurts your sleep."
                     : "No clear patterns yet. Each habit needs at least 7 check-in days with it and 7 without (drinks, late caffeine, a late workout), plus that morning's HRV or sleep.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(insights.prefix(6)) { insight in
                HStack(spacing: 10) {
                    Image(systemName: insight.isGood ? "arrow.up.heart.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(insight.isGood ? Theme.recoveryHigh : Theme.recoveryModerate)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.sentence)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("\(insight.daysWith) days with vs \(insight.daysWithout) without")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if !progress.isEmpty {
                HabitProgressList(items: Array(progress.prefix(5)))
            }
            if !insights.isEmpty {
                Text("Patterns, not proof: other things can change on the same days.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}

/// "Late caffeine · 4/7 days": how far each habit is from being tested.
private struct HabitProgressList: View {
    let items: [CheckInInsights.FactorProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Still collecting")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            ForEach(items) { item in
                HStack {
                    Text(item.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 8)
                    Text(item.text)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Vitamins and minerals from the food log: what to fix first (low nutrients,
/// worst first, each with 2-3 food fixes sized to close the gap), then the
/// ones that are fine (collapsed), then how to read it. 7-day averages vs
/// daily targets (`Micronutrients`).
struct MicronutrientsCard: View {
    let findings: [Micronutrients.Finding]
    @Environment(UserSettings.self) private var settings

    var body: some View {
        if findings.isEmpty {
            emptyCard
        } else {
            WhatToFixCard(findings: Micronutrients.toFix(findings), sex: settings.sex, focuses: settings.goals.focuses)
            TooHighNutrientsCard(findings: Micronutrients.tooHigh(findings), age: settings.age)
            // Weekly share of energy beside sodium and fibre; absent without data (`SaturatedFat`).
            SaturatedFatCard()
            FineNutrientsCard(findings: findings.filter { $0.kind == .ok })
            MicronutrientsFooter()
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Vitamins & minerals", color: Theme.nutrition)
            Text("Log food in your food app for at least 4 days (with Apple Health sync on) to see which vitamins and minerals your meals cover and what to fix.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

/// Low nutrients, worst first, each with the foods that would close the gap.
private struct WhatToFixCard: View {
    let findings: [Micronutrients.Finding]
    let sex: BiologicalSex
    let focuses: [Goals.Focus]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: "Low this week", color: Theme.nutrition)
                Spacer()
                Text("7-day average")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if findings.isEmpty {
                Text("Nothing is low this week. Everything your food app shares is at or near its target.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(findings) { finding in
                NutrientFixRow(finding: finding, note: Micronutrients.athleteNote(finding.nutrient, sex: sex, focuses: focuses))
            }
        }
        .card(tint: Theme.nutrition)
    }
}

private struct NutrientFixRow: View {
    let finding: Micronutrients.Finding
    let note: String?
    @Environment(LabsModel.self) private var labs

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NutrientAmountLine(finding: finding, color: Theme.recoveryModerate)
            if let effect = finding.effect {
                Text(effect)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(Micronutrients.fixes(for: finding)) { fix in
                FoodFixLine(fix: fix, unit: finding.nutrient.unit)
            }
            NutrientContextLines(finding: finding)
            // With a blood test on file, the test line replaces "a test settles it".
            if let note, NutrientContextLines.latestLab(for: finding.nutrient, in: labs) == nil {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// Under a nutrient: what supplements add (or that doses aren't marked yet)
/// and the latest blood test for it, e.g. "Your Sep 22 test: 24 ng/mL".
private struct NutrientContextLines: View {
    let finding: Micronutrients.Finding
    @Environment(MedicationsModel.self) private var medications
    @Environment(LabsModel.self) private var labs

    static func latestLab(for nutrient: Micronutrients.Nutrient, in labs: LabsModel) -> LabResult? {
        guard let id = nutrient.labMarkerID else { return nil }
        return labs.latest.first { $0.groupKey == id }
    }

    var body: some View {
        let listed = SupplementNutrients.listed(for: finding.nutrient, in: medications.medications)
        let names = listed.map { [$0.name, $0.dose].filter { !$0.isEmpty }.joined(separator: " ") }.joined(separator: ", ")
        let source = names.isEmpty ? "supplements" : names
        VStack(alignment: .leading, spacing: 4) {
            if finding.fromSupplements > 0 {
                line("pills.fill", "Includes \(nutrientAmount(finding.fromSupplements)) \(finding.nutrient.unit) a day from \(source)")
            } else if !names.isEmpty {
                line("pills", "You take \(names): mark doses in Log to count them")
            }
            if let lab = Self.latestLab(for: finding.nutrient, in: labs) {
                line("drop.fill", labText(lab))
            }
        }
    }

    private func labText(_ lab: LabResult) -> String {
        let value = lab.value.formatted(.number.precision(.fractionLength(0...1)))
        let date = lab.date.formatted(.dateTime.month(.abbreviated).day())
        var text = "Your \(date) test: \(value) \(lab.unit)"
        if let markerID = lab.markerID,
           let note = LabMarkers.guidelineNote(markerID: markerID, value: lab.value, unit: lab.unit, labLow: lab.referenceLow) {
            text += ". " + note
        } else if let status = lab.status {
            text += " (\(status.rawValue.lowercased()))"
        }
        return text
    }

    private func line(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Nutrients over their upper limit, each with its warning; kept apart from
/// "Fine" so a red sodium line never sits under a green heading.
private struct TooHighNutrientsCard: View {
    let findings: [Micronutrients.Finding]
    let age: Int

    var body: some View {
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardLabel(text: "Too high", color: Theme.recoveryLow)
                ForEach(findings) { finding in
                    VStack(alignment: .leading, spacing: 4) {
                        // Against the upper limit the warning cites (sodium 2,300 mg), not the intake target.
                        NutrientAmountLine(finding: finding, color: Theme.recoveryLow, limit: finding.nutrient.upperLimit(age: age))
                        if let effect = finding.effect {
                            Text(effect)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        NutrientContextLines(finding: finding)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// "40 g pumpkin seeds (+220 mg)", with the food's note when it has one.
private struct FoodFixLine: View {
    let fix: Micronutrients.FoodFix
    let unit: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(fix.grams)) g \(fix.food.name) (+\(nutrientAmount(fix.amount)) \(unit))" + (fix.closesGap ? "" : ", part of the gap"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                if let note = fix.food.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } icon: {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.nutrition)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Name, "210 / 400 mg" and a progress bar toward the target; for a
/// too-high nutrient "2,900 mg · limit 2,300" with the bar running past a
/// tick at the limit.
private struct NutrientAmountLine: View {
    let finding: Micronutrients.Finding
    let color: Color
    var limit: Double?

    private var amountText: String {
        if let limit {
            return "\(nutrientAmount(finding.average)) \(finding.nutrient.unit) · limit \(nutrientAmount(limit))"
        }
        return "\(nutrientAmount(finding.average)) / \(nutrientAmount(finding.target)) \(finding.nutrient.unit)"
    }

    /// Where the limit tick sits on a full bar (the bar is the intake).
    private var limitFraction: Double? {
        guard let limit, finding.average > limit else { return nil }
        return limit / finding.average
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(finding.nutrient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(amountText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textColor(for: color))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    if let limitFraction {
                        Capsule()
                            .fill(color.gradient)
                        Rectangle()
                            .fill(Theme.card)
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * limitFraction - 1)
                    } else {
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(6, geo.size.width * min(1, finding.percentOfTarget / 100)))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    private var spokenLabel: String {
        let name = finding.nutrient.name
        if let limit {
            return "\(name), \(nutrientAmount(finding.average)) \(finding.nutrient.unit) a day, over the limit of \(nutrientAmount(limit))"
        }
        return "\(name), \(Int(finding.percentOfTarget.rounded())) percent of target"
    }
}

/// Nutrients near or over target but under the upper limit, collapsed.
private struct FineNutrientsCard: View {
    let findings: [Micronutrients.Finding]
    @State private var expanded = false

    var body: some View {
        if !findings.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            NutrientAmountLine(finding: finding, color: Theme.recoveryHigh)
                            NutrientContextLines(finding: finding)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text("Fine (\(findings.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            .tint(Theme.secondaryText)
            .card()
        }
    }
}

/// How to read the page: the data's limits, in plain words.
private struct MicronutrientsFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs at least 4 logged days and averages the last 7, using what your food app (Cronometer) shares with Apple Health and its food database. Only nutrients it shares are shown. Supplements in your list count on days you mark them taken.")
            Text("Targets are US RDAs and Adequate Intakes for your sex and age (NIH Office of Dietary Supplements): population targets, not a test of you. Low intake is a reason to check, not proof of deficiency; a blood test (ferritin, vitamin D, B12) tells you more than intake. Food amounts come from USDA FoodData Central.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
    }
}

/// Whole numbers from 100 up (with a thousands separator), one decimal below.
private func nutrientAmount(_ value: Double) -> String {
    value >= 100 ? Int(value.rounded()).formatted() : value.formatted(.number.precision(.fractionLength(0...1)))
}
