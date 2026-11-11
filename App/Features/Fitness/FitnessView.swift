import SwiftUI
import SwiftData
import AppCore

/// Fitness: plan, start and track training (docs/research/ux-audit.md 4.6).
/// Five sections under the week strip, most actionable first (HIG Layout:
/// "Place the most important items near the top"; ux-audit.md P7): This week
/// (the primary card), Today (day strain, activities, zones), Training load,
/// Progress (rows that push the full cards and their research notes) and
/// Workouts (saved workouts and history).
struct FitnessView: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(AppRefresher.self) private var refresher
    @State private var showingHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    WeekStrip(days: metrics.weekStrain)
                    ThisWeekCard()
                    SectionHeader("Lift goals", linkTitle: "See all", destination: LiftGoalsDetailView())
                    LiftGoalRingsCard()
                    SectionHeader("Today")
                    FitnessTodayCard()
                    SectionHeader("Training load")
                    FitnessLoadSection()
                    SectionHeader("Progress")
                    FitnessProgressCard()
                    ProgressRecordsCard()
                    SectionHeader("Workouts")
                    FitnessWorkoutsCard()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.rose, Theme.Wash.butter])
            }
            .background(Theme.background)
            .navigationTitle("Fitness")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Workout history", systemImage: "calendar") {
                        showingHistory = true
                    }
                }
            }
            .tabToolbar()
            .navigationDestination(isPresented: $showingHistory) {
                WorkoutHistoryView()
            }
            .refreshable { await refresher.refresh() }
        }
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    let days: [DailyMetricsModel.DayStrain]
    /// Ring numbers at 11 pt or more, scaled with Dynamic Type (ux-audit.md 4.6, P22).
    @ScaledMetric(relativeTo: .caption2) private var ringNumberSize: CGFloat = 11

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // The last 7 days, today last.
        let dates = (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        HStack(spacing: 6) {
            ForEach(dates, id: \.self) { date in
                let isToday = calendar.isDate(date, inSameDayAs: today)
                let strain = days.first { calendar.isDate($0.date, inSameDayAs: date) }?.strain
                VStack(spacing: 6) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isToday ? Theme.strainTextColor : Theme.secondaryText)
                    GradientRing(progress: (strain ?? 0) / StrainCalculator.maximum, colors: Theme.strainColors, lineWidth: 4, showsDisk: false) {
                        Text(strain.map { "\(whole($0))" } ?? "–")
                            .font(.system(size: ringNumberSize, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .foregroundStyle(Theme.primaryText)
                    }
                    .frame(width: 36, height: 36)
                    Text(date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isToday ? Theme.primaryText : Theme.secondaryText)
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(isToday ? Theme.card : Color.clear, in: .rect(cornerRadius: 18))
                .shadow(color: isToday ? Color.black.opacity(0.07) : .clear, radius: 9, y: 4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide).day())), strain \(strain.map { strainText($0) } ?? "no data")")
            }
        }
    }
}

// MARK: - Today

/// Today: the day-strain gauge with today's range band, today's activities
/// as rows, and a Heart-rate zones row that pushes the zones page. The range
/// message and session suggestions live on the Today tab's Strain sheet, so
/// they are not repeated here (ux-audit.md 4.6 Fitness, F2).
private struct FitnessTodayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DayStrainGauge()
            Divider().overlay(Theme.separator)
            TodayActivityRows()
            Divider().overlay(Theme.separator)
            ZonesSummaryRow()
        }
        .card()
    }
}

private struct DayStrainGauge: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 60

    var body: some View {
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CardLabel(text: "Day strain")
                Spacer()
                if let target {
                    rangeChip(current: current, target: target)
                }
            }
            gauge(current: current, target: target)
                .frame(maxWidth: .infinity)
            rangeLine(target)
        }
    }

    private func gauge(current: Double, target: ClosedRange<Double>?) -> some View {
        ArcGauge(
            value: current / StrainCalculator.maximum,
            band: target.map { ($0.lowerBound / StrainCalculator.maximum)...($0.upperBound / StrainCalculator.maximum) },
            colors: [Theme.strainLight, Theme.strain, Theme.lifting],
            lineWidth: 24
        ) {
            VStack(spacing: 2) {
                Text(strainText(current))
                    .font(.system(size: min(heroSize, 76), weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing))
                Text("day strain")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(width: 250, height: 250)
        .padding(.bottom, -40)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenGauge(current: current, target: target))
    }

    /// "In range" / "Below range" / "Above range" (ux-audit.md 4.7). Calm
    /// colours: below is grey, never a warning (ux-audit.md P17, P19).
    private func rangeChip(current: Double, target: ClosedRange<Double>) -> some View {
        let status = StrainPlanner().status(current: current, target: target)
        // Before any activity, "Not started" rather than "Below range" at 7 am (as on the Strain sheet).
        let notStarted = current < 0.5 && metrics.activities.isEmpty
        let chip: (text: String, color: Color) = switch status {
        case .below: ("Below range", Theme.secondaryText)
        case .inRange: ("In range", Theme.recoveryHigh)
        case .above: ("Above range", Theme.strain)
        }
        return notStarted ? Chip(text: "Not started", color: Theme.secondaryText) : Chip(text: chip.text, color: chip.color)
    }

    @ViewBuilder
    private func rangeLine(_ target: ClosedRange<Double>?) -> some View {
        if let target {
            Text("Today's range \(strainRangeText(target))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.recoveryHighText)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        } else {
            Text("Wear your watch to sleep so the app can set a daily strain range from your recovery.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func spokenGauge(current: Double, target: ClosedRange<Double>?) -> String {
        guard let target else { return "Day strain \(strainText(current))" }
        return "Day strain \(strainText(current)), today's range \(strainRangeText(target))"
    }
}

/// Today's activities as rows with their strain; one line when there are
/// none (no Start button here: the primary card above has it).
private struct TodayActivityRows: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if metrics.activities.isEmpty {
                Text("No workouts yet today. Log a gym session or record one on your watch.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(metrics.activities.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().overlay(Theme.separator).padding(.vertical, 10)
                }
                HStack(spacing: 12) {
                    IconBadge(
                        systemName: item.isStrength ? "dumbbell.fill" : "figure.walk",
                        color: item.isStrength ? Theme.lifting : Theme.oxygen,
                        size: badgeSize
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("\(item.detail) · \(item.start.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Chip(text: item.noHeartRate ? "—" : "+\(strainText(item.strainAdded))")
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Minutes in heart-rate zones today; pushes the zones page.
private struct ZonesSummaryRow: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let total = (metrics.strain?.zoneMinutes ?? []).reduce(0, +)
        MetricRow(
            title: "Heart-rate zones",
            value: "\(whole(total))",
            unit: "min today",
            spokenUnit: "minutes in zones today",
            hint: "Shows time in each zone",
            destination: ZonesDetailView()
        )
    }
}

// MARK: - Training load

/// The two dials, side by side (stacked at accessibility text sizes,
/// ux-audit.md 4.8).
private struct FitnessLoadSection: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        VStack(alignment: .leading, spacing: 8) {
            layout {
                LoadCard(title: "Cardio", result: metrics.cardioLoad, colors: [Theme.oxygenLight, Theme.oxygen, Theme.sleep])
                LoadCard(title: "Muscular", result: metrics.muscularLoad, colors: [Theme.strainLight, Theme.strain, Theme.lifting])
            }
            // A description of this week vs your usual 4 weeks, not an injury prediction (`TrainingLoadCalculator`).
            Text("Average daily strain over the last 7 days, against your usual. A description, not an injury forecast.")
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct LoadCard: View {
    let title: String
    let result: TrainingLoadCalculator.Result?
    let colors: [Color]

    var body: some View {
        let maximum = StrainCalculator.maximum
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            TickDial(
                value: result.map { $0.value / maximum },
                band: band(maximum: maximum),
                colors: colors,
                tickCount: 36,
                tickLength: 10
            ) {
                dialCentre
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 140)
            .frame(maxWidth: .infinity)
            .padding(.bottom, -14)
            HStack {
                Text("0")
                Spacer()
                Text("\(whole(maximum))%")
            }
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var dialCentre: some View {
        VStack(spacing: 0) {
            Text(result.map { $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "–")
                .tileNumberFont()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Theme.primaryText)
            Text("avg daily strain")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let result, result.status != .calibrating {
                Text("your usual \(whole(result.usual.lowerBound))–\(whole(result.usual.upperBound.rounded(.up)))")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 18)
    }

    private func band(maximum: Double) -> ClosedRange<Double>? {
        guard let result, result.status != .calibrating else { return nil }
        return (result.usual.lowerBound / maximum)...(result.usual.upperBound / maximum)
    }

    /// A description of this week vs your usual 4 weeks (not an injury prediction).
    private var statusText: String {
        switch result?.status {
        case .lighter: return "Lighter than usual"
        case .steady: return "About your usual"
        case .building: return "A bit more than usual"
        case .spike: return "Much more than usual"
        default: return "Learning your usual"
        }
    }

    private var statusColor: Color {
        switch result?.status {
        case .steady: Theme.recoveryHighText
        case .building: Theme.strainTextColor
        case .spike: Theme.recoveryModerateText
        case .lighter: Theme.oxygenText
        default: Theme.secondaryText
        }
    }
}

// MARK: - Progress

/// Cardio fitness, Strength and Muscles as `MetricRow`s; each pushes a page
/// with the full cards and their research notes (ux-audit.md 4.5, 4.6).
private struct FitnessProgressCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(UserSettings.self) private var settings
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var plans
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        VStack(spacing: 0) {
            cardioRow
            Divider().overlay(Theme.separator)
            strengthRow
            Divider().overlay(Theme.separator)
            musclesRow
        }
        .card()
    }

    /// VO₂ max with its age-and-sex label and the 90-day trend, as on the
    /// full card (`CardioFitness`; Kaminsky et al., Mayo Clin Proc 2015).
    private var cardioRow: some View {
        let history = vitals.vo2MaxHistory
        let start = Date.now.addingTimeInterval(-Double(CardioFitness.trendDays) * 86_400)
        // The value the app scores with (`VitalsModel.vo2ForScores`): the estimate by default.
        let scored = vitals.vo2ForScores
        let verdict: MetricVerdict? = scored.map { scored in
            let category = VO2Norms.category(vo2: scored.value, age: settings.age, sex: settings.sex)
            return MetricVerdict(category.name, color: category.chipColor)
        }
        return MetricRow(
            title: scored?.isEstimate == true ? "Cardio fitness (VO₂ max, estimate)" : "Cardio fitness (VO₂ max)",
            value: scored.map { ($0.isEstimate ? "≈" : "") + $0.value.formatted(.number.precision(.fractionLength($0.isEstimate ? 0 : 1))) },
            unit: "ml/kg/min",
            spokenUnit: "millilitres per kilogram per minute",
            verdict: verdict,
            trend: history.filter { $0.date >= start },
            trendColor: Theme.oxygen,
            hint: "Shows your VO₂ max trend and weekly active minutes",
            destination: CardioDetailView()
        )
    }

    /// Strength days in the last 7 against the 2+ a week target (WHO 2020;
    /// `StrengthDays`), with the same chip as the full card.
    private var strengthRow: some View {
        let finished = sessions.filter { !$0.isActive && !$0.workingSets.isEmpty }
        let thisWeek = StrengthDays.lastSevenDays(finished.map(\.startedAt))
        let target = StrengthDays.weeklyTarget
        let met = thisWeek >= target
        let verdict = MetricVerdict(met ? "Goal reached" : "\(target - thisWeek) more to go", color: met ? Theme.recoveryHigh : Theme.lifting)
        return MetricRow(
            title: "Strength",
            value: "\(thisWeek)",
            unit: "in 7 days · goal \(target)+",
            spokenUnit: "days in the last 7, goal \(target) or more",
            verdict: verdict,
            hint: "Shows strength days, the health minimum and strength for health",
            destination: StrengthDetailView()
        )
    }

    /// Muscles at this block week's target (sets since Monday within each
    /// muscle's band, as on `WeeklySetsCard`), or without a block in the
    /// 10-20 hard sets a week range (Schoenfeld et al., J Sports Sci 2017;
    /// Pelland et al., Sports Med 2026), with a chip for overworked or
    /// recovering muscles (`MuscleRecovery`).
    private var musclesRow: some View {
        let states = WeeklySetsCard.shown.compactMap { muscles.states[$0] }
        let all = Muscle.allCases.compactMap { muscles.states[$0] }
        let bands = (plans.volumeTargets(muscles: muscles)?.targets ?? []).filter { WeeklySetsCard.shown.contains($0.muscle) }
        let atTarget = bands.filter { target in
            let sets = muscles.weekSets[target.muscle] ?? 0
            return sets >= Double(target.band.lowerBound) && sets <= Double(target.band.upperBound)
        }.count
        let hasBlock = !bands.isEmpty
        let inRange = hasBlock ? atTarget : states.filter { $0.volume == .productive }.count
        let total = hasBlock ? bands.count : states.count
        let overworked = all.filter(\.isOverworked).count
        let recovering = all.filter { $0.status != .fresh && !$0.isOverworked }.count
        let verdict: MetricVerdict? = if overworked > 0 {
            MetricVerdict("\(overworked) overworked", color: Theme.recoveryModerate)
        } else if recovering > 0 {
            MetricVerdict("\(recovering) recovering")
        } else {
            nil
        }
        return MetricRow(
            title: "Muscles",
            value: total == 0 ? nil : "\(inRange) of \(total)",
            unit: hasBlock ? "at this week's target" : "at 10–20 sets",
            spokenUnit: hasBlock ? "muscles at this week's set target" : "muscles at 10 to 20 hard sets this week",
            verdict: verdict,
            hint: "Shows the muscle map and hard sets per muscle",
            destination: MusclesDetailView()
        )
    }
}

// MARK: - Workouts

/// Saved workouts and History, both pushed (ux-audit.md 4.3; replaces the
/// old "Your workouts" card).
private struct FitnessWorkoutsCard: View {
    @Query private var templates: [WorkoutTemplate]

    var body: some View {
        VStack(spacing: 0) {
            NavigationLink {
                MyWorkoutsView()
            } label: {
                FitnessLinkRow(
                    title: "Saved workouts",
                    detail: templates.isEmpty ? "Build your own" : "\(templates.count) saved",
                    systemImage: "list.bullet.rectangle.portrait"
                )
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.separator)
            NavigationLink {
                WorkoutHistoryView()
            } label: {
                FitnessLinkRow(title: "History", detail: "Every session you've logged", systemImage: "calendar")
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}

/// A row that pushes a page: neutral icon (ux-audit.md 4.5 colour rules),
/// title, one line of detail and a chevron (HIG Lists and tables, P6).
private struct FitnessLinkRow: View {
    let title: String
    let detail: String
    let systemImage: String
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: systemImage, color: Theme.secondaryText, size: badgeSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail page

/// The page a Progress or Zones row pushes: the full cards, with their
/// research notes, on the standard background.
struct FitnessDetailPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .lockedToScreenWidth()
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
