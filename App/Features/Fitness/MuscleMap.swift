import SwiftUI
import SwiftData
import AppCore

/// Muscle recovery from logged sets (and runs/rides from the watch).
@Observable
final class MuscleModel {
    private(set) var states: [Muscle: MuscleRecovery.State] = [:]
    private(set) var deload: DeloadAdvisor.Advice?

    var suggestedFocus: WorkoutFocus? { MuscleRecovery.suggestedFocus(states) }

    func refresh(sessions: [WorkoutSession], library: ExerciseLibrary, health: HealthKitClient?, hrvBelowNormal: Bool = false) async {
        let now = Date.now
        // Best estimated 1RM per exercise per session, for the deload check.
        let sixWeeks = now.addingTimeInterval(-42 * 86_400)
        var lifts: [DeloadAdvisor.LiftPoint] = []
        for session in sessions where session.startedAt >= sixWeeks {
            for exercise in session.exercises {
                let best = exercise.sets.filter { $0.isCompleted && !$0.isWarmup }.map(\.estimatedOneRepMax).max() ?? 0
                if best > 0 { lifts.append(.init(exercise: exercise.name, date: session.startedAt, estimatedOneRepMax: best)) }
            }
        }
        deload = DeloadAdvisor.evaluate(lifts, hrvBelowNormal: hrvBelowNormal, now: now)
        let cutoff = now.addingTimeInterval(-10 * 86_400)
        var sets: [MuscleRecovery.WorkSet] = []
        for session in sessions where session.startedAt >= cutoff {
            for exercise in session.exercises {
                guard let info = library.exercise(id: exercise.exerciseID) else { continue }
                for set in exercise.sets where set.isCompleted && !set.isWarmup {
                    sets.append(MuscleRecovery.WorkSet(
                        date: set.completedAt ?? session.startedAt,
                        primary: info.primaryMuscles,
                        secondary: info.secondaryMuscles,
                        rpe: set.rpe ?? session.sessionRPE.map(Double.init)
                    ))
                }
            }
        }
        var cardio: [MuscleRecovery.Cardio] = []
        if let health, let workouts = try? await health.externalWorkouts(from: cutoff, to: now) {
            for workout in workouts where !workout.isStrength {
                let kind: MuscleRecovery.Cardio.Kind? = switch workout.name {
                case "Run": .run
                case "Ride": .ride
                case "Row": .row
                case "Hike", "Stairs": .hike
                default: nil
                }
                if let kind {
                    cardio.append(MuscleRecovery.Cardio(kind: kind, end: workout.end, minutes: Double(workout.minutes)))
                }
            }
        }
        states = MuscleRecovery.evaluate(sets: sets, cardio: cardio, now: now)
    }
}

// MARK: - Body drawing

/// Muscle outlines (see BodyMapData.swift), scaled to fit while keeping proportions.
nonisolated struct PolygonShape: Shape {
    let polygons: [[Double]]
    /// minX, minY, maxX, maxY of the whole figure, so every region scales the same.
    let bounds: [Double]

    func path(in rect: CGRect) -> Path {
        let width = bounds[2] - bounds[0]
        let height = bounds[3] - bounds[1]
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY - height * scale / 2
        var path = Path()
        for polygon in polygons where polygon.count >= 6 {
            for index in stride(from: 0, to: polygon.count - 1, by: 2) {
                let point = CGPoint(x: originX + (polygon[index] - bounds[0]) * scale,
                                    y: originY + (polygon[index + 1] - bounds[1]) * scale)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }
}

/// One side of the body, each muscle region filled by `color(for:)`.
struct BodyFigure: View {
    let data: [(String, [Double])]
    let bounds: [Double]
    /// Region names: Muscle raw values, "upperBack" (lats + upper back) or "body".
    let color: (String) -> Color

    var body: some View {
        let regions = Dictionary(grouping: data, by: \.0).mapValues { $0.map(\.1) }
        ZStack {
            ForEach(regions.keys.sorted(), id: \.self) { region in
                let shape = PolygonShape(polygons: regions[region] ?? [], bounds: bounds)
                shape.fill(color(region))
                    .overlay(shape.stroke(Theme.card, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round)))
            }
        }
        .aspectRatio((bounds[2] - bounds[0]) / (bounds[3] - bounds[1]), contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

struct MuscleMapCard: View {
    @Environment(MuscleModel.self) private var model
    @State private var mode = Mode.recovery

    enum Mode: String, CaseIterable, Identifiable {
        case recovery = "Rest status"
        case volume = "This week"
        var id: String { rawValue }
    }

    var body: some View {
        let states = model.states
        VStack(alignment: .leading, spacing: 14) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    BodyFigure(data: BodyMapData.front, bounds: BodyMapData.backBounds) { color(region: $0, states) }
                    Text("Front").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 6) {
                    BodyFigure(data: BodyMapData.back, bounds: BodyMapData.backBounds) { color(region: $0, states) }
                    Text("Back").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 300)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary(states))
            legend
            details(states)
        }
        .card(tint: Theme.heart)
    }

    /// Colour for a drawn region; "upperBack" shows the more tired of lats and upper back.
    private func color(region: String, _ states: [Muscle: MuscleRecovery.State]) -> Color {
        if region == "upperBack" {
            let pair = [states[.lats], states[.middleBack]].compactMap { $0 }
            let worst = mode == .recovery ? pair.min { $0.recovery < $1.recovery } : pair.max { $0.weeklySets < $1.weeklySets }
            return color(worst)
        }
        guard let muscle = Muscle(rawValue: region) else { return Theme.bodyNeutral }
        return color(states[muscle])
    }

    private func color(_ state: MuscleRecovery.State?) -> Color {
        guard let state else { return Theme.bodyNeutral }
        switch mode {
        case .recovery:
            // Grey = not trained recently; green = trained and ready again.
            guard state.lastTrained != nil else { return Theme.bodyNeutral }
            if state.recovery >= 99 { return Theme.recoveryHigh }
            switch state.status {
            case .fresh: return Theme.recoveryHigh
            case .recovering: return Theme.recoveryModerate
            case .fatigued: return Theme.recoveryLow
            }
        case .volume:
            switch state.volume {
            case .none: return Theme.bodyNeutral
            case .low: return Theme.oxygenLight
            case .productive: return Theme.recoveryHigh
            case .high: return Theme.strain
            }
        }
    }

    /// What the figures show, for VoiceOver.
    private func accessibilitySummary(_ states: [Muscle: MuscleRecovery.State]) -> String {
        let trained = Muscle.allCases.compactMap { states[$0] }.filter { $0.lastTrained != nil }
        guard !trained.isEmpty else { return "Body map: no muscles trained recently." }
        let parts = trained.map { state in
            mode == .recovery
                ? "\(state.muscle.name) \(state.recovery >= 99 ? "ready" : (state.status == .fatigued ? "tired" : "recovering"))"
                : "\(state.muscle.name) \(state.weeklySets.formatted(.number.precision(.fractionLength(0...1)))) sets"
        }
        return "Body map: " + parts.joined(separator: ", ")
    }

    private var legend: some View {
        let items: [(String, Color)] = mode == .recovery
            ? [("Ready", Theme.recoveryHigh), ("Recovering", Theme.recoveryModerate), ("Tired", Theme.recoveryLow), ("Not trained", Theme.bodyNeutral)]
            : [("Under 10 sets", Theme.oxygenLight), ("10-20 sets", Theme.recoveryHigh), ("Over 20", Theme.strain)]
        // Wraps at large text sizes instead of overflowing.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 9, height: 9)
                    Text(item.0).font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func details(_ states: [Muscle: MuscleRecovery.State]) -> some View {
        let all = Muscle.allCases.compactMap { states[$0] }
        let overworked = all.filter(\.isOverworked)
        let resting = all.filter { $0.status != .fresh && !$0.isOverworked }.sorted { $0.recovery < $1.recovery }
        let major: [Muscle] = [.chest, .lats, .middleBack, .shoulders, .quadriceps, .hamstrings, .glutes, .biceps, .triceps]
        let under = all.filter { major.contains($0.muscle) && $0.volume != .productive && $0.volume != .high }
        VStack(alignment: .leading, spacing: 10) {
            if all.allSatisfy({ $0.lastTrained == nil }) {
                Text("Log a gym session and the muscles you worked light up here: red when tired, amber while recovering, green once ready again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !overworked.isEmpty {
                row("exclamationmark.triangle.fill", Theme.recoveryLow,
                    "Overworked: \(overworked.map(\.muscle.name).joined(separator: ", "))",
                    "Over 20 hard sets (sets taken close to failure) this week and not recovered. Give them 2-3 days or cut volume; more sets past this point add fatigue, not muscle.")
            }
            if !resting.isEmpty {
                row("hourglass", Theme.recoveryModerate, "Still recovering",
                    resting.prefix(4).map { state in
                        let hours = state.hoursUntilFresh.map { " — ready in ~\(Int($0.rounded(.up))) h" } ?? ""
                        return "\(state.muscle.name)\(hours)"
                    }.joined(separator: " · "))
            }
            if mode == .volume, !under.isEmpty, !all.allSatisfy({ $0.lastTrained == nil }) {
                row("arrow.up.circle.fill", Theme.oxygen, "Could use more this week",
                    under.map { "\($0.muscle.name) \($0.weeklySets.formatted(.number.precision(.fractionLength(0...1))))" }.joined(separator: " · ")
                    + ". Aim for 10-20 hard sets per muscle a week.")
            }
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primaryText)
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
