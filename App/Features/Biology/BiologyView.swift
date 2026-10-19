import SwiftUI
import SwiftData
import Charts
import AppCore

/// Long-term baselines: HRV trend and biomarkers.
struct BiologyView: View {
    @Environment(BiologyModel.self) private var biology
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(AppRouter.self) private var router
    @Environment(ProgressPhotosModel.self) private var progressPhotos
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
                    BodyAgeCard(result: vitals.bodyAge, isLoading: vitals.isLoading)
                    ProgressPhotosCard { router.showProgressPhotos = true }
                    InsightsCard(insights: checkIns.insights, daysLeft: checkIns.daysUntilInsights)
                    hrvCard
                    MicronutrientsCard(findings: metrics.micronutrients)
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
                                let stat = proteinStat(protein)
                                Button { selected = stat } label: {
                                    VitalTile(stat: stat, colors: VitalTile.colors(for: .body))
                                }
                                .buttonStyle(.plain)
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

    private func proteinStat(_ protein: BiologyModel.Marker) -> VitalsModel.Stat {
        var stat = VitalsModel.Stat(
            id: "protein", category: .body, title: "Protein · 7 days", icon: "fork.knife",
            value: protein.value, unit: protein.unit, status: protein.status,
            tone: protein.tone == .caution ? .caution : .good, series: protein.series
        )
        stat.chart = .bars
        stat.goal = metrics.proteinTarget
        stat.about = "Protein logged in Cronometer each day. Your target comes from your goal and weight: about 1.6 g per kg helps build muscle with lifting, and more while losing weight (Morton et al., Br J Sports Med 2018)."
        return stat
    }

    private func load() async {
        guard let health else { return }
        var manual: [Date: Double] = [:]
        for reading in hrvReadings where manual[reading.date] == nil {
            manual[reading.date] = reading.milliseconds
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let recent = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.map(\.strainSummary)
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent,
                             sleepConsistency: metrics.sleepConsistency, sleepSpreadMinutes: metrics.sleepSpreadMinutes)
        await checkIns.refreshInsights(health: health, manualHRV: manual)
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
                if let trend = metrics.recovery?.hrvTrend {
                    let color: Color = trend.status == .below ? Theme.recoveryModerate : Theme.recoveryHigh
                    Text("7-day average \(Int(trend.average.rounded())) ms · normal \(Int(trend.normalRange.lowerBound.rounded()))–\(Int(trend.normalRange.upperBound.rounded())) ms · \(trend.status == .below ? "below normal: train easy" : (trend.status == .above ? "above normal" : "in range"))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
                Chart {
                    if let trend = metrics.recovery?.hrvTrend {
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

/// Body age: the headline number, how it compares with your age, and what moves it.
struct BodyAgeCard: View {
    let result: BodyAge.Result?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: "Body age")
                Spacer()
                Text("Estimate")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let result {
                let younger = result.difference <= 0
                let tone = younger ? Theme.recoveryHighText : Theme.recoveryModerateText
                HStack(alignment: .center, spacing: 18) {
                    // A full ring in the result's color: green when younger, amber when older.
                    GradientRing(
                        progress: 1,
                        colors: younger ? [Theme.recoveryHighLight, Theme.recoveryHigh] : [Theme.recoveryModerateLight, Theme.recoveryModerate],
                        lineWidth: 12
                    ) {
                        VStack(spacing: 0) {
                            Text(result.bodyAge.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
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
                            Text("\(abs(result.difference).formatted(.number.precision(.fractionLength(1)))) years \(younger ? "younger" : "older")")
                        }
                        .font(.headline)
                        .foregroundStyle(tone)
                        Text("than your age (\(result.age))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Text(younger ? "Your habits are taking years off. Keep it up." : "Fitness, sleep and steps are the quickest ways to bring this down.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                VStack(spacing: 10) {
                    ForEach(result.factors) { factor in
                        FactorRow(factor: factor)
                    }
                }
                Text("Based on fitness (VO₂ max), resting heart rate, sleep, steps and body composition. An estimate, not a medical test.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(isLoading ? "Working it out…" : "Needs at least two of: VO₂ max, resting heart rate, sleep, steps, body fat or BMI. Wear your watch day and night and add your height and weight in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: (result?.difference ?? 0) <= 0 ? Theme.recoveryHigh : Theme.recoveryModerate)
    }
}

private struct FactorRow: View {
    let factor: BodyAge.Factor

    var body: some View {
        let helps = factor.years <= 0
        let color = helps ? Theme.recoveryHigh : Theme.recoveryModerate
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(factor.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            // Bar centred on zero: left = younger, right = older.
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
            .frame(width: 90, height: 28)
            Text("\(helps ? "−" : "+")\(abs(factor.years).formatted(.number.precision(.fractionLength(1)))) y")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// "What affects you": patterns between check-in answers and next-morning data.
struct InsightsCard: View {
    let insights: [CheckInInsights.Insight]
    let daysLeft: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "What affects you", color: Theme.sleep)
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(insight.sentence)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("\(insight.daysWith) days with vs \(insight.daysWithout) without")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if !insights.isEmpty {
                Text("Patterns, not proof: other things can change on the same days.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.sleep)
    }
}

/// Vitamins and minerals from the food log, 7-day averages vs daily targets.
struct MicronutrientsCard: View {
    let findings: [Micronutrients.Finding]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Vitamins & minerals", color: Theme.nutrition)
                Spacer()
                Text("7-day average")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if findings.isEmpty {
                Text("Log food in Cronometer for at least 4 days (with Apple Health sync on) to see how your vitamins and minerals compare with daily targets.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            ForEach(findings) { finding in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(finding.nutrient.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Text("\(amount(finding.average)) / \(amount(finding.target)) \(finding.nutrient.unit)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(color(finding))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule()
                                .fill(color(finding).gradient)
                                .frame(width: max(6, geo.size.width * min(1, finding.percentOfTarget / 100)))
                        }
                    }
                    .frame(height: 6)
                    if let effect = finding.effect {
                        Text(effect)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if !findings.isEmpty {
                Text("Targets: US Dietary Reference Intakes (NIH). Only nutrients your food app shares are shown. Food logs undercount supplements unless you log them too.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.nutrition)
    }

    private func color(_ finding: Micronutrients.Finding) -> Color {
        switch finding.kind {
        case .low: Theme.recoveryModerate
        case .ok: Theme.recoveryHigh
        case .high: Theme.recoveryLow
        }
    }

    private func amount(_ value: Double) -> String {
        value >= 100 ? "\(Int(value.rounded()))" : value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// Latest front/side photos and the latest weekly analysis.
struct ProgressPhotosCard: View {
    @Environment(ProgressPhotosModel.self) private var photos
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "Progress photos", color: Theme.lifting)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                }
                HStack(spacing: 10) {
                    ForEach(ProgressPhotosModel.Pose.allCases) { pose in
                        Group {
                            if let entry = photos.latest(pose), let image = photos.thumbnail(entry) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                ZStack {
                                    Theme.cardRaised
                                    Image(systemName: "camera.fill").foregroundStyle(Theme.lifting)
                                }
                            }
                        }
                        .frame(width: 72, height: 96)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(photos.todayEntry(.front) == nil ? "Take today's photos" : "Today's photos done")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        if let analysis = photos.latestAnalysis {
                            Text(analysis.text)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(4)
                        } else {
                            Text("Front and side, kept only in the app. Claude compares them weekly.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
            }
            .card(tint: Theme.lifting)
        }
        .buttonStyle(.plain)
    }
}
