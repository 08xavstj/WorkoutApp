import SwiftUI
import SwiftData
import AppCore

/// Muscle recovery from logged sets (and runs/rides from the watch).
@Observable
final class MuscleModel {
    private(set) var states: [Muscle: MuscleRecovery.State] = [:]

    var suggestedFocus: WorkoutFocus? { MuscleRecovery.suggestedFocus(states) }

    func refresh(sessions: [WorkoutSession], library: ExerciseLibrary, health: HealthKitClient?) async {
        let now = Date.now
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

/// Simple shapes in a 100 x 220 box, scaled to fit.
nonisolated enum BodyPart: Sendable {
    case ellipse(CGRect)
    case capsule(CGRect)
    case rounded(CGRect, CGFloat)
}

nonisolated struct BodyShape: Shape {
    let parts: [BodyPart]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 100, rect.height / 220)
        let origin = CGPoint(x: rect.midX - 50 * scale, y: rect.midY - 110 * scale)
        func map(_ r: CGRect) -> CGRect {
            CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
        }
        var path = Path()
        for part in parts {
            switch part {
            case .ellipse(let r): path.addEllipse(in: map(r))
            case .capsule(let r):
                let m = map(r)
                path.addRoundedRect(in: m, cornerSize: CGSize(width: min(m.width, m.height) / 2, height: min(m.width, m.height) / 2))
            case .rounded(let r, let radius):
                path.addRoundedRect(in: map(r), cornerSize: CGSize(width: radius * scale, height: radius * scale))
            }
        }
        return path
    }
}

nonisolated enum BodyLayout {
    static func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    /// Mirrors a rect across the body's centre line.
    static func m(_ rect: CGRect) -> CGRect { CGRect(x: 100 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) }
    static func pair(_ part: (CGRect) -> BodyPart, _ rect: CGRect) -> [BodyPart] { [part(rect), part(m(rect))] }

    static let silhouette: [BodyPart] = [
        .ellipse(r(41, 1, 18, 21)),
        .rounded(r(44, 18, 12, 10), 3),
        .rounded(r(31, 25, 38, 62), 14),
        .rounded(r(33, 80, 34, 22), 9),
    ] + pair(BodyPart.capsule, r(20, 28, 13, 40))
      + pair(BodyPart.capsule, r(16, 64, 11, 32))
      + pair(BodyPart.ellipse, r(15, 93, 10, 12))
      + pair(BodyPart.capsule, r(32, 92, 17, 58))
      + pair(BodyPart.capsule, r(34, 146, 13, 58))
      + pair(BodyPart.capsule, r(33, 200, 14, 10))

    static let front: [Muscle: [BodyPart]] = [
        .traps: pair(BodyPart.ellipse, r(37, 24, 11, 7)),
        .shoulders: pair(BodyPart.ellipse, r(21, 27, 15, 16)),
        .chest: pair({ .rounded($0, 6) }, r(34, 32, 15.5, 15)),
        .biceps: pair(BodyPart.capsule, r(21.5, 44, 10, 21)),
        .forearms: pair(BodyPart.capsule, r(17, 66, 9, 26)),
        .abdominals: [.rounded(r(42.5, 49, 15, 33), 5)] + pair({ .rounded($0, 3) }, r(35, 51, 6.5, 26)),
        .quadriceps: pair(BodyPart.capsule, r(33.5, 96, 13, 46)),
        .adductors: pair(BodyPart.capsule, r(45, 98, 4.5, 26)),
        .calves: pair(BodyPart.capsule, r(36, 152, 9, 38)),
        .neck: [.rounded(r(46, 18, 8, 7), 2)],
    ]

    static let back: [Muscle: [BodyPart]] = [
        .traps: [.rounded(r(39, 21, 22, 20), 8)],
        .shoulders: pair(BodyPart.ellipse, r(21, 27, 15, 16)),
        .triceps: pair(BodyPart.capsule, r(21.5, 44, 10, 21)),
        .forearms: pair(BodyPart.capsule, r(17, 66, 9, 26)),
        .lats: pair({ .rounded($0, 7) }, r(33, 40, 12, 30)),
        .middleBack: [.rounded(r(45, 41, 10, 20), 4)],
        .lowerBack: [.rounded(r(40, 64, 20, 15), 6)],
        .glutes: pair(BodyPart.ellipse, r(34, 82, 16, 19)),
        .abductors: pair(BodyPart.capsule, r(31, 84, 4.5, 14)),
        .hamstrings: pair(BodyPart.capsule, r(34, 103, 12.5, 42)),
        .calves: pair(BodyPart.capsule, r(35, 149, 11.5, 36)),
    ]
}

/// One side of the body with each muscle filled by `color(for:)`.
struct BodyFigure: View {
    let muscles: [Muscle: [BodyPart]]
    let color: (Muscle) -> Color

    var body: some View {
        ZStack {
            BodyShape(parts: BodyLayout.silhouette)
                .fill(Theme.track.shadow(.inner(color: Color.black.opacity(0.12), radius: 2, y: 1)))
            ForEach(Array(muscles.keys), id: \.self) { muscle in
                let fill = color(muscle)
                BodyShape(parts: muscles[muscle] ?? [])
                    .fill(LinearGradient(colors: [fill.opacity(0.75), fill], startPoint: .top, endPoint: .bottom))
                    .overlay(BodyShape(parts: muscles[muscle] ?? []).stroke(Color.white.opacity(0.7), lineWidth: 1))
            }
        }
        .aspectRatio(100 / 220, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Card

struct MuscleMapCard: View {
    @Environment(MuscleModel.self) private var model
    @State private var mode = Mode.recovery

    enum Mode: String, CaseIterable, Identifiable {
        case recovery = "Recovery"
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
                VStack(spacing: 4) {
                    BodyFigure(muscles: BodyLayout.front) { color(states[$0]) }
                    Text("Front").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                VStack(spacing: 4) {
                    BodyFigure(muscles: BodyLayout.back) { color(states[$0]) }
                    Text("Back").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 250)
            .frame(maxWidth: .infinity)
            legend
            details(states)
        }
        .card(tint: Theme.heart)
    }

    private func color(_ state: MuscleRecovery.State?) -> Color {
        guard let state else { return Theme.track }
        switch mode {
        case .recovery:
            guard state.lastTrained != nil, state.recovery < 99 else { return Theme.track }
            switch state.status {
            case .fresh: return Theme.recoveryHigh
            case .recovering: return Theme.recoveryModerate
            case .fatigued: return Theme.recoveryLow
            }
        case .volume:
            switch state.volume {
            case .none: return Theme.track
            case .low: return Theme.oxygenLight
            case .productive: return Theme.recoveryHigh
            case .high: return Theme.recoveryLow
            }
        }
    }

    private var legend: some View {
        let items: [(String, Color)] = mode == .recovery
            ? [("Fresh", Theme.recoveryHigh), ("Recovering", Theme.recoveryModerate), ("Fatigued", Theme.recoveryLow)]
            : [("Under 10 sets", Theme.oxygenLight), ("10-20 sets", Theme.recoveryHigh), ("Over 20", Theme.recoveryLow)]
        return HStack(spacing: 12) {
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
                Text("Log a gym session and the muscles you worked light up here, then fade back to grey as they recover.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !overworked.isEmpty {
                row("exclamationmark.triangle.fill", Theme.recoveryLow,
                    "Overworked: \(overworked.map(\.muscle.name).joined(separator: ", "))",
                    "Over 20 hard sets this week and not recovered. Give them 2-3 days or cut volume; more sets past this point add fatigue, not muscle.")
            }
            if !resting.isEmpty {
                row("hourglass", Theme.recoveryModerate, "Still recovering",
                    resting.prefix(4).map { state in
                        let hours = state.hoursUntilFresh.map { " ~\(Int($0.rounded(.up)))h" } ?? ""
                        return "\(state.muscle.name) \(Int(state.recovery))%\(hours)"
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
