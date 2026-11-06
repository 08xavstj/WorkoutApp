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
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(\.healthClient) private var health
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HRVBaselineCard()
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
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var heightCm: Double? {
        metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil)
    }

    private func load() async {
        guard let health else { return }
        var manual: [Date: Double] = [:]
        for reading in hrvReadings where manual[reading.date] == nil {
            manual[reading.date] = reading.milliseconds
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let recent = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.map(\.strainSummary)
        // Body age uses waist-to-height instead of BMI while a waist reading is under 90 days old.
        vitals.waistToHeightRatio = measurements.freshWaistToHeightRatio(heightCm: heightCm)
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent,
                             sleepConsistency: metrics.sleepConsistency, sleepSpreadMinutes: metrics.sleepSpreadMinutes)
        await checkIns.refreshInsights(health: health, manualHRV: manual)
        await biology.refresh(health: health, settings: settings, manualHRV: manual, proteinTarget: metrics.proteinTarget)
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
/// (body age, patterns, Garmin help).
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
                Text("90 days")
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
                Chip(
                    text: "\(change >= 0 ? "↑" : "↓") \(whole(abs(change).rounded()))% vs last month",
                    color: change >= 0 ? Theme.recoveryHigh : Theme.recoveryModerate
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

    var body: some View {
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
                .annotation(position: .top, alignment: .leading) {
                    Text("Baseline \(whole(baseline.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            ForEach(series) { point in
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
                    .lineLimit(1)
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
            Text("No data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func trendVisual(main: Color) -> some View {
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
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Body age

/// Body age: the headline number, how it compares with your age, and what moves it.
struct BodyAgeCard: View {
    let result: BodyAge.Result?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: "Body age")
                Spacer()
                Text(result?.confidence.label ?? "Estimate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(result?.confidence == .high ? Theme.recoveryHighText : Theme.secondaryText)
            }
            if let result {
                summary(result)
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's moving it")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(result.factors) { factor in
                        FactorRow(factor: factor)
                    }
                }
                Text("\(result.confidence.label): \(result.confidenceReason) Based on fitness (VO₂ max), resting heart rate, sleep, steps and body composition. Shown as whole years with a ±\(BodyAge.uncertaintyYears)-year range because only the parts, not the sum, have been tested in studies. An estimate, not a medical test.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(isLoading ? "Working it out…" : "Needs at least two of: VO₂ max, resting heart rate, sleep, steps, waist-to-height, body fat or BMI. Wear your watch day and night and add your height and weight in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: (result?.difference ?? 0) <= 0 ? Theme.recoveryHigh : Theme.recoveryModerate)
    }

    private func summary(_ result: BodyAge.Result) -> some View {
        let younger = result.difference <= 0
        let tone = younger ? Theme.recoveryHighText : Theme.recoveryModerateText
        return HStack(alignment: .center, spacing: 18) {
            // A full ring in the result's color: green when younger, amber when older.
            GradientRing(
                progress: 1,
                colors: younger ? [Theme.recoveryHighLight, Theme.recoveryHigh] : [Theme.recoveryModerateLight, Theme.recoveryModerate],
                lineWidth: 12
            ) {
                VStack(spacing: 0) {
                    Text("\(result.years)")
                        .tileNumberFont()
                        .foregroundStyle(Theme.primaryText)
                        .minimumScaleFactor(0.7)
                    Text("years")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 14)
            }
            .frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: younger ? "arrow.down" : "arrow.up")
                    Text("\(abs(result.difference).formatted(.number.precision(.fractionLength(0)))) years \(younger ? "younger" : "older")")
                }
                .font(.headline)
                .foregroundStyle(tone)
                Text("than your age (\(result.age))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                // Whole years with a ±5-year range: no composite "age" is validated finer than that.
                Text("Likely \(result.rangeLabel)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(younger ? "Your habits are taking years off. Keep it up." : "Fitness, sleep and steps are the quickest ways to bring this down.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

private struct FactorRow: View {
    let factor: BodyAge.Factor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var barWidth: CGFloat = 90
    @ScaledMetric(relativeTo: .subheadline) private var valueWidth: CGFloat = 56

    private var helps: Bool { factor.years <= 0 }
    private var color: Color { helps ? Theme.recoveryHigh : Theme.recoveryModerate }

    var body: some View {
        // Name beside the bar normally; above it at accessibility sizes.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            VStack(alignment: .leading, spacing: 1) {
                Text(factor.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !stacked { Spacer(minLength: 8) }
            HStack(spacing: 10) {
                bar
                Text("\(helps ? "−" : "+")\(abs(factor.years).formatted(.number.precision(.fractionLength(1)))) y")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textColor(for: color))
                    .frame(width: valueWidth, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Bar centred on zero: left = younger, right = older.
    private var bar: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let length = min(half, half * abs(factor.years) / 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track).frame(height: 6)
                Rectangle().fill(Theme.secondaryText.opacity(0.4)).frame(width: 1.5, height: 12).offset(x: half - 0.75)
                Capsule()
                    .fill(LinearGradient(colors: helps ? [Theme.recoveryHighLight, color] : [Theme.recoveryModerateLight, color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, length), height: 6)
                    .offset(x: helps ? half - max(4, length) : half)
            }
            .frame(height: 12)
            .frame(maxHeight: .infinity)
        }
        .frame(width: barWidth, height: 28)
    }
}

/// Body age as its own page, pushed from Key measures. The number is kept
/// secondary to the factors that move it: an "effective age" older than your
/// real age is a nocebo risk (docs/research/behaviour-change.md, "Body age").
struct BodyAgePage: View {
    @Environment(VitalsModel.self) private var vitals

    var body: some View {
        HealthDetailPage(title: "Body age") {
            BodyAgeCard(result: vitals.bodyAge, isLoading: vitals.isLoading)
        }
    }
}

// MARK: - Patterns cards

/// "What affects you": patterns between check-in answers and next-morning data.
struct InsightsCard: View {
    let insights: [CheckInInsights.Insight]
    let daysLeft: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "What affects you")
            if insights.isEmpty {
                Text(daysLeft > 0
                     ? "Do the morning and evening check-ins for \(daysLeft) more day\(daysLeft == 1 ? "" : "s") and your personal patterns appear here: what lowers your HRV, raises your resting heart rate or hurts your sleep."
                     : "No clear patterns yet. Keep checking in; patterns need a few days with and without each habit.")
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
            if !insights.isEmpty {
                Text("Patterns, not proof: other things can change on the same days.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
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
            FineNutrientsCard(findings: findings.filter { $0.kind != .low })
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
                CardLabel(text: "What to fix", color: Theme.nutrition)
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
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
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

/// Name, "210 / 400 mg" and a progress bar toward the target.
private struct NutrientAmountLine: View {
    let finding: Micronutrients.Finding
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(finding.nutrient.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(nutrientAmount(finding.average)) / \(nutrientAmount(finding.target)) \(finding.nutrient.unit)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textColor(for: color))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(6, geo.size.width * min(1, finding.percentOfTarget / 100)))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.nutrient.name), \(Int(finding.percentOfTarget.rounded())) percent of target")
    }
}

/// Nutrients at or over target, collapsed; high ones carry their warning.
private struct FineNutrientsCard: View {
    let findings: [Micronutrients.Finding]
    @State private var expanded = false

    var body: some View {
        if !findings.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            NutrientAmountLine(finding: finding, color: finding.kind == .high ? Theme.recoveryLow : Theme.recoveryHigh)
                            if let effect = finding.effect {
                                Text(effect)
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                            }
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
            Text("Needs at least 4 logged days and averages the last 7, using what your food app (Cronometer) shares with Apple Health and its food database. Only nutrients it shares are shown, and supplements count only if you log them.")
            Text("Targets are US RDAs and Adequate Intakes for your sex and age (NIH Office of Dietary Supplements): population targets, not a test of you. Low intake is a reason to check, not proof of deficiency; a blood test settles iron, vitamin D and B12. Food amounts come from USDA FoodData Central.")
        }
        .font(.caption2)
        .foregroundStyle(Theme.secondaryText)
    }
}

/// Whole numbers from 100 up, one decimal below.
private func nutrientAmount(_ value: Double) -> String {
    value >= 100 ? "\(Int(value.rounded()))" : value.formatted(.number.precision(.fractionLength(0...1)))
}
