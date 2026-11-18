import SwiftUI
import SwiftData
import Charts
import AppCore

/// One exercise over time: estimated 1RM per session with personal records,
/// the best set and the volume.
struct LiftProgressView: View {
    let exerciseID: String
    let name: String

    @Environment(GymStore.self) private var gym
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    /// How the planner moves this lift forward (`ProgressionPreferences`).
    @State private var progression: ProgressionMode = .load
    @State private var showVolume = false
    @State private var selectedDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The gym's unit, as on every lifting screen (`GymStore.liftingUnit`).
    private var unit: WeightUnit { gym.liftingUnit }

    /// Body mass for pull-ups, chin-ups and dips (`BodyweightLoad`), kg; nil when unknown.
    private var bodyMassKg: Double? {
        let mass = metrics.bodyMassKg ?? settings.weightKg
        return mass > 0 ? mass : nil
    }

    /// A pull-up, chin-up or dip with a known body mass: its load counts the body.
    private var countsBodyMass: Bool {
        BodyweightLoad.countsBodyMass(exerciseID: exerciseID) && bodyMassKg != nil
    }

    /// Points in the display unit. Estimated 1RM, the best set, PRs and the set
    /// count come from straight working sets: drop stages and mini-sets are
    /// lighter or fatigued by design, as in the PR banner and the planner's
    /// history (`LiftHistory`). Their reps still count in the volume.
    private var points: [LiftProgress.Point] {
        var stageVolume: [Date: Double] = [:]
        let logged = sessions.filter { !$0.isActive }.compactMap { session -> LiftProgress.LoggedSession? in
            let done = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter { $0.isCompleted && !$0.isWarmup }
            let stages = done.filter { $0.kind.isStage }
            if !stages.isEmpty {
                stageVolume[session.startedAt] = stages.reduce(0) { $0 + loadDisplay($1.weightKg) * Double($1.reps) }
            }
            let sets = done.filter { !$0.kind.isStage }
                .map { LiftProgress.LoggedSet(weight: loadDisplay($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
            return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
        }
        // No e1RM PRs where body mass is added in: Records (`PRHistory`)
        // counts reps and added weight for pull-ups, chin-ups and dips, and
        // a change in body weight alone would move the estimate.
        let marksPRs = !countsBodyMass
        return LiftProgress.points(logged).map { point in
            var point = point
            point.volume += stageVolume[point.date] ?? 0
            if !marksPRs { point.isPR = false }
            return point
        }
    }

    /// A logged weight as the chart counts it: body mass added for a pull-up,
    /// chin-up or dip (`BodyweightLoad.load`), in the display unit.
    private func loadDisplay(_ loggedKg: Double) -> Double {
        unit.display(BodyweightLoad.load(exerciseID: exerciseID, loggedKg: loggedKg, bodyMassKg: bodyMassKg))
    }

    /// No weight to estimate a 1RM from (push-ups, bodyweight squats): progress in reps.
    private func isRepsOnly(_ points: [LiftProgress.Point]) -> Bool {
        points.allSatisfy { $0.bestWeight <= 0 }
    }

    /// Sessions with an estimated 1RM: only sets of 10 reps or fewer give one
    /// (`OneRepMax.displayEstimate`).
    private func estimated(_ points: [LiftProgress.Point]) -> [LiftProgress.Point] {
        points.filter { $0.estimatedOneRepMax > 0 }
    }

    /// "≈ 96 kg".
    private func estimateText(_ value: Double) -> String {
        "\(OneRepMax.symbol) \(wholeText(value)) \(unit.rawValue)"
    }

    /// "82.5 kg × 6", "BW + 10 kg × 8" for a weighted pull-up, "15 reps" for bodyweight work.
    private func bestSetText(_ point: LiftProgress.Point) -> String {
        if point.bestWeight <= 0 { return "\(point.bestReps) reps" }
        if countsBodyMass, let bodyMassKg {
            let added = point.bestWeight - unit.display(bodyMassKg)
            let load = added > 0.05 ? "BW + \(number(added)) \(unit.rawValue)" : "BW"
            return "\(load) × \(point.bestReps)"
        }
        return "\(number(point.bestWeight)) \(unit.rawValue) × \(point.bestReps)"
    }

    var body: some View {
        let points = self.points
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No history yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Finish a workout with \(name) and its progress shows up here.")
                    )
                } else {
                    summary(points)
                    chartCard(points)
                    LiftGoalsLink(exerciseID: exerciseID)
                    sessionList(points)
                    Text(footnote(points))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                progressionCard
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { progression = ProgressionPreferences.resolved(for: exerciseID, gym: gym.profile, atKilograms: latestWeightKg) }
    }

    // MARK: Progression

    /// Load, reps or sets: how the planner moves this lift forward. Load and
    /// rep progression built similar muscle and strength (Plotkin et al.,
    /// PeerJ 2022); the suggestion follows the equipment (`ProgressionMode.suggested`).
    private var progressionCard: some View {
        let suggested = ProgressionPreferences.suggested(for: exerciseID, gym: gym.profile, atKilograms: latestWeightKg)
        return VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "How it progresses", color: Theme.liftingText)
            Picker("Progress by", selection: progressionBinding) {
                ForEach(ProgressionMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(progression.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Text("Adding weight and adding reps built about the same muscle and strength in a 2022 study, so pick what suits the equipment. Adding sets is the volume route; there's less direct evidence for it as a progression rule. Suggested here: \(suggested.title.lowercased()).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    /// The latest session's best working weight, in kg, for judging the gym's next jump
    /// (the added weight only, for a pull-up, chin-up or dip).
    private var latestWeightKg: Double {
        guard let last = points.last else { return 0 }
        let body = countsBodyMass ? (bodyMassKg ?? 0) : 0
        return max(0, unit.toKilograms(last.bestWeight) - body)
    }

    private func footnote(_ points: [LiftProgress.Point]) -> String {
        if isRepsOnly(points) {
            return "Bodyweight work is tracked by your best set's reps: there's no weight to work out an estimated 1RM from."
        }
        var text = "Estimated 1RM (≈) is the most you could lift once, worked out from your best set of 10 reps or fewer and how many reps you had left (Epley formula with RPE). Past 10 reps the formulas lose accuracy and differ by lift (LeSuer 1997; Nuzzo 2024), so those sets show no estimate. It's a way to compare sessions, not a test."
        if countsBodyMass {
            text += " For pull-ups, chin-ups and dips it counts your body weight plus any added weight, so it isn't marked as a PR here; Records counts their reps and added weight."
        }
        return text
    }

    private var progressionBinding: Binding<ProgressionMode> {
        Binding(
            get: { progression },
            set: { mode in
                ProgressionPreferences.set(mode, for: exerciseID)
                progression = mode
            }
        )
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Whole units for estimates, which are only good to a few kg ("133", not "129.8").
    private func wholeText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func summary(_ points: [LiftProgress.Point]) -> some View {
        let repsOnly = isRepsOnly(points)
        let withEstimate = estimated(points)
        let best = withEstimate.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
        // Bodyweight work: the best set's reps instead of an estimated 1RM of 0.
        let first = repsOnly ? Double(points.first?.bestReps ?? 0) : (withEstimate.first?.estimatedOneRepMax ?? 0)
        let last = repsOnly ? Double(points.last?.bestReps ?? 0) : (withEstimate.last?.estimatedOneRepMax ?? 0)
        let change = first > 0 ? (last / first - 1) * 100 : 0
        let mostReps = points.map(\.bestReps).max() ?? 0
        let bestItem = repsOnly
            ? item("Most reps", "\(mostReps)", spoken: "Most reps in a set")
            : item("Best est. 1RM", best.map { estimateText($0.estimatedOneRepMax) } ?? "–", spoken: "Best estimated one-rep max")
        let sessionsItem = item("Sessions", "\(points.count)")
        let changeItem = item("Since first", (repsOnly ? points.count : withEstimate.count) > 1 ? "\(change >= 0 ? "+" : "")\(Int(change.rounded()))%" : "–")
        let prItem = item("PRs", countsBodyMass ? "–" : "\(points.filter(\.isPR).count)", spoken: "Personal records")
        // Four across; two rows of two at accessibility text sizes (ux-audit.md 4.8, P22).
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                Grid(horizontalSpacing: 8, verticalSpacing: 12) {
                    GridRow {
                        bestItem
                        sessionsItem
                    }
                    GridRow {
                        changeItem
                        prItem
                    }
                }
            } else {
                HStack(spacing: 0) {
                    bestItem
                    sessionsItem
                    changeItem
                    prItem
                }
            }
        }
        .card()
    }

    /// One summary number; VoiceOver reads "title, value".
    private func item(_ title: String, _ value: String, spoken: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? title)
        .accessibilityValue(value)
    }

    /// "3 Nov: 82.5 kg × 6 · est. 1RM 96 kg · volume 1,980", or "3 Nov: 15 reps" for bodyweight work.
    private func selectedText(_ point: LiftProgress.Point, repsOnly: Bool) -> String {
        let date = point.date.formatted(date: .abbreviated, time: .omitted)
        if repsOnly { return "\(date): best set \(point.bestReps) reps" }
        let estimate = point.estimatedOneRepMax > 0 ? " · est. 1RM \(estimateText(point.estimatedOneRepMax))" : ""
        return "\(date): \(bestSetText(point))\(estimate) · volume \(wholeText(point.volume))"
    }

    private func chartCard(_ points: [LiftProgress.Point]) -> some View {
        let repsOnly = isRepsOnly(points)
        // Only sets of more than 10 reps: no estimate to chart, so volume.
        let noEstimate = !repsOnly && estimated(points).isEmpty
        let volume = (showVolume || noEstimate) && !repsOnly
        return VStack(alignment: .leading, spacing: 10) {
            if !repsOnly, !noEstimate {
                Picker("Show", selection: $showVolume) {
                    Text("Estimated 1RM").tag(false)
                    Text("Volume").tag(true)
                }
                .pickerStyle(.segmented)
            }
            HStack(alignment: .top) {
                if let selectedDate, let point = nearest(selectedDate, in: points) {
                    Text(selectedText(point, repsOnly: repsOnly))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                } else {
                    Text("Touch the chart to see a session")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                // The chart as an image (ShareableChart.swift). e1RM is marked
                // as an estimate: reps at a given %1RM vary by lift (Nuzzo et
                // al., Sports Med 2024), so it is a trend, not a test.
                ChartShareButton(title: "\(name), \(repsOnly ? "best set reps" : volume ? "volume" : "estimated 1RM")",
                                 subtitle: shareSubtitle(points),
                                 caveat: repsOnly || volume ? nil : "Estimated 1RM ≈ from your best set of 10 reps or fewer and reps left (Epley); an estimate that varies by lift, not a tested max. Diamonds are records.") {
                    LiftTrendChart(points: points, repsOnly: repsOnly, volume: volume, selected: nil)
                }
            }
            LiftTrendChart(points: points, repsOnly: repsOnly, volume: volume,
                           selected: selectedDate.flatMap { nearest($0, in: points) })
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)
            if !volume, !repsOnly {
                // The icon in the PR markers' colour, so the legend matches the chart.
                Label {
                    Text("Diamonds are personal records")
                        .foregroundStyle(Theme.secondaryText)
                } icon: {
                    Image(systemName: "diamond.fill")
                        .foregroundStyle(Theme.strain)
                }
                .font(.caption)
            }
        }
        .card()
    }

    /// "12 sessions · 3 Jan – 18 Nov · kg".
    private func shareSubtitle(_ points: [LiftProgress.Point]) -> String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        var parts = ["\(points.count) sessions"]
        if let first = points.first?.date, let last = points.last?.date {
            parts.append("\(first.formatted(format)) – \(last.formatted(format))")
        }
        if !isRepsOnly(points) { parts.append(unit.rawValue) }
        return parts.joined(separator: " · ")
    }

    private func sessionList(_ points: [LiftProgress.Point]) -> some View {
        let repsOnly = isRepsOnly(points)
        return VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "Sessions", color: Theme.liftingText)
                .padding(.bottom, 8)
            ForEach(points.reversed()) { point in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(point.sets) sets · best \(bestSetText(point))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                    }
                    Spacer()
                    if point.isPR, !repsOnly {
                        Chip(text: "PR", color: Theme.strain)
                    }
                    if !repsOnly {
                        estimateColumn(point)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }
            }
        }
        .card()
    }

    private func estimateColumn(_ point: LiftProgress.Point) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(point.estimatedOneRepMax > 0 ? estimateText(point.estimatedOneRepMax) : "–")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            Text("est. 1RM")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(point.estimatedOneRepMax > 0
            ? "Estimated one rep max about \(wholeText(point.estimatedOneRepMax)) \(unit.rawValue)"
            : "No estimated one rep max: no set of 10 reps or fewer")
    }

    private func nearest(_ date: Date, in points: [LiftProgress.Point]) -> LiftProgress.Point? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Estimated 1RM (with records as diamonds), volume bars, or best-set reps
/// for bodyweight work, per session; used on screen and for the share image.
private struct LiftTrendChart: View {
    let points: [LiftProgress.Point]
    let repsOnly: Bool
    let volume: Bool
    let selected: LiftProgress.Point?

    var body: some View {
        Chart {
            ForEach(points) { point in
                if repsOnly {
                    LineMark(x: .value("Date", point.date), y: .value("Reps", point.bestReps))
                        .foregroundStyle(Theme.lifting)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value("Reps", point.bestReps))
                        .foregroundStyle(Theme.lifting)
                        .symbolSize(30)
                } else if volume {
                    BarMark(x: .value("Date", point.date, unit: .day), y: .value("Volume", point.volume))
                        .foregroundStyle(Theme.lifting.gradient)
                        .cornerRadius(4)
                } else if point.estimatedOneRepMax > 0 {
                    // Only sessions with a set of 10 reps or fewer have an estimate (`OneRepMax.displayEstimate`).
                    LineMark(x: .value("Date", point.date), y: .value("e1RM", point.estimatedOneRepMax))
                        .foregroundStyle(Theme.lifting)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", point.date), y: .value("e1RM", point.estimatedOneRepMax))
                        .foregroundStyle(point.isPR ? Theme.strain : Theme.lifting)
                        .symbolSize(point.isPR ? 90 : 30)
                        .symbol(point.isPR ? BasicChartSymbolShape.diamond : BasicChartSymbolShape.circle)
                }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Theme.secondaryText.opacity(0.35))
            }
        }
        .chartYScale(domain: .automatic(includesZero: volume))
        // Room at both ends so the last date label isn't clipped.
        .chartXScale(range: .plotDimension(padding: 12))
    }
}
