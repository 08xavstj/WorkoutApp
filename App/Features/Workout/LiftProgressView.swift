import SwiftUI
import SwiftData
import Charts
import AppCore

/// One exercise over time: estimated 1RM per session with personal records,
/// the best set and the volume.
struct LiftProgressView: View {
    let exerciseID: String
    let name: String

    @Environment(UserSettings.self) private var settings
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var showVolume = false
    @State private var selectedDate: Date?

    private var unit: WeightUnit { settings.weightUnit }

    /// Points in the display unit.
    private var points: [LiftProgress.Point] {
        let logged = sessions.filter { !$0.isActive }.compactMap { session -> LiftProgress.LoggedSession? in
            let sets = session.exercises
                .filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter { $0.isCompleted && !$0.isWarmup }
                .map { LiftProgress.LoggedSet(weight: unit.display($0.weightKg), reps: $0.reps, rpe: $0.rpe) }
            return sets.isEmpty ? nil : LiftProgress.LoggedSession(date: session.startedAt, sets: sets)
        }
        return LiftProgress.points(logged)
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
                    sessionList(points)
                    Text("Estimated 1RM is the most you could lift once, worked out from your best set and how many reps you had left (Epley formula with RPE). It's a way to compare sessions, not a test.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func summary(_ points: [LiftProgress.Point]) -> some View {
        let best = points.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }
        let first = points.first?.estimatedOneRepMax ?? 0
        let last = points.last?.estimatedOneRepMax ?? 0
        let change = first > 0 ? (last / first - 1) * 100 : 0
        return HStack(spacing: 0) {
            item("Best e1RM", best.map { "\(number($0.estimatedOneRepMax)) \(unit.rawValue)" } ?? "–")
            item("Sessions", "\(points.count)")
            item("Since first", points.count > 1 ? "\(change >= 0 ? "+" : "")\(Int(change.rounded()))%" : "–")
            item("PRs", "\(points.filter(\.isPR).count)")
        }
        .card()
    }

    private func item(_ title: String, _ value: String) -> some View {
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
    }

    private func chartCard(_ points: [LiftProgress.Point]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Show", selection: $showVolume) {
                Text("Estimated 1RM").tag(false)
                Text("Volume").tag(true)
            }
            .pickerStyle(.segmented)
            if let selectedDate, let point = nearest(selectedDate, in: points) {
                Text("\(point.date.formatted(date: .abbreviated, time: .omitted)): \(number(point.bestWeight)) \(unit.rawValue) × \(point.bestReps) · e1RM \(number(point.estimatedOneRepMax)) · volume \(number(point.volume))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            } else {
                Text("Touch the chart to see a session")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Chart {
                ForEach(points) { point in
                    if showVolume {
                        BarMark(x: .value("Date", point.date, unit: .day), y: .value("Volume", point.volume))
                            .foregroundStyle(Theme.lifting.gradient)
                            .cornerRadius(4)
                    } else {
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
                if let selectedDate, let point = nearest(selectedDate, in: points) {
                    RuleMark(x: .value("Selected", point.date))
                        .foregroundStyle(Theme.secondaryText.opacity(0.35))
                }
            }
            .chartYScale(domain: .automatic(includesZero: showVolume))
            .chartXSelection(value: $selectedDate)
            .frame(height: 220)
            if !showVolume {
                Label("Diamonds are personal records", systemImage: "diamond.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func sessionList(_ points: [LiftProgress.Point]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "Sessions", color: Theme.lifting)
                .padding(.bottom, 8)
            ForEach(points.reversed()) { point in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        Text("\(point.sets) sets · best \(number(point.bestWeight)) \(unit.rawValue) × \(point.bestReps)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                    }
                    Spacer()
                    if point.isPR {
                        Chip(text: "PR", color: Theme.strain)
                    }
                    Text(number(point.estimatedOneRepMax))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                        .accessibilityLabel("Estimated one rep max \(number(point.estimatedOneRepMax)) \(unit.rawValue)")
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }
            }
        }
        .card()
    }

    private func nearest(_ date: Date, in points: [LiftProgress.Point]) -> LiftProgress.Point? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
