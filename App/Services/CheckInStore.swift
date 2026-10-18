import Foundation
import AppCore

/// Morning and evening check-ins, saved as JSON in Application Support, plus
/// the "what affects you" patterns built from them.
@Observable
final class CheckInStore {
    private struct Saved: Codable {
        var mornings: [String: MorningCheckIn] = [:]
        var evenings: [String: EveningCheckIn] = [:]
        /// Sleep score per morning, kept so patterns can use past nights.
        var sleepScores: [String: Double] = [:]
    }

    private var saved = Saved()
    private(set) var insights: [CheckInInsights.Insight] = []
    private(set) var daysUntilInsights = 14

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "checkins.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    private func key(_ day: Date) -> String { Dose.dayKey(Calendar.current.startOfDay(for: day)) }

    func morning(on day: Date = .now) -> MorningCheckIn? { saved.mornings[key(day)] }
    func evening(on day: Date = .now) -> EveningCheckIn? { saved.evenings[key(day)] }

    func save(_ checkIn: MorningCheckIn) {
        saved.mornings[key(checkIn.day)] = checkIn
        write()
    }

    func save(_ checkIn: EveningCheckIn) {
        saved.evenings[key(checkIn.day)] = checkIn
        write()
    }

    func recordSleepScore(_ score: Int?, morning: Date = .now) {
        guard let score, saved.sleepScores[key(morning)] != Double(score) else { return }
        saved.sleepScores[key(morning)] = Double(score)
        write()
    }

    private func write() {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Today's advice from this morning's answers.
    var advice: String? { morning().flatMap(CheckInCoaching.advice(for:)) }

    /// A focus that avoids sore muscles, from this morning's answers.
    var suggestedFocus: WorkoutFocus? { morning().flatMap(CheckInCoaching.focus(for:)) }

    /// Did a hard workout end within an hour of falling asleep last night?
    /// Hard = a logged session at RPE 7+, or any workout averaging 60%+ of heart-rate reserve.
    func detectLateWorkout(
        health: HealthKitClient,
        sleep: SleepCalculator.Result?,
        sessions: [StrengthSessionSummary],
        profile: HeartRateProfile?
    ) async -> Bool? {
        guard let bedtime = sleep?.bedtime else { return nil }
        let windowStart = bedtime.addingTimeInterval(-3600)
        let lifted = sessions.contains { $0.end > windowStart && $0.end <= bedtime && ($0.sessionRPE ?? 0) >= 7 }
        if lifted { return true }
        guard let profile, let workouts = try? await health.workoutIntervals(from: windowStart.addingTimeInterval(-4 * 3600), to: bedtime) else { return false }
        for workout in workouts where workout.end > windowStart && workout.end <= bedtime && workout.duration >= 10 * 60 {
            let heartRate = (try? await health.heartRatePerMinute(from: workout.start, to: workout.end)) ?? []
            guard !heartRate.isEmpty else { continue }
            let average = heartRate.map(\.bpm).reduce(0, +) / Double(heartRate.count)
            if profile.reserveFraction(for: average) >= 0.6 { return true }
        }
        return false
    }

    /// Rebuilds the patterns from saved check-ins and 90 days of HRV / resting HR.
    func refreshInsights(health: HealthKitClient, manualHRV: [Date: Double]) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let vitals = DailyVitals.merging((try? await health.nightlyVitals(days: 90, endingOn: today)) ?? [], manualHRV: manualHRV, manualOnlyHRV: true)
        var byMorning: [String: DailyVitals] = [:]
        for vital in vitals { byMorning[key(vital.date)] = vital }
        var waterByDay: [String: Double] = [:]
        for day in (try? await health.dailySeries(.dietaryWater, unit: .liter(), days: 91, cumulative: true)) ?? [] {
            waterByDay[key(day.date)] = day.value
        }

        var days: [CheckInDay] = []
        for offset in 0..<90 {
            guard let morning = calendar.date(byAdding: .day, value: -offset, to: today),
                  let previous = calendar.date(byAdding: .day, value: -1, to: morning) else { continue }
            let evening = saved.evenings[key(previous)]
            let checkIn = saved.mornings[key(morning)]
            let water = waterByDay[key(previous)]
            guard evening != nil || checkIn != nil || water != nil else { continue }
            let vital = byMorning[key(morning)]
            days.append(CheckInDay(
                morning: morning, evening: evening, checkIn: checkIn,
                hrv: vital?.hrvMilliseconds, restingHeartRate: vital?.restingHeartRate,
                sleepScore: saved.sleepScores[key(morning)],
                waterLiters: water
            ))
        }
        insights = CheckInInsights.analyze(days)
        daysUntilInsights = CheckInInsights.daysUntilReady(days)
    }

    /// Short summary for the AI coach.
    var coachSummary: String? {
        var parts: [String] = []
        if let morning = morning() {
            var line = "This morning:"
            if let rested = morning.rested { line += " rested \(rested)/5," }
            if let soreness = morning.soreness { line += " soreness \(soreness)/10" + (morning.soreAreas.isEmpty ? "," : " (\(morning.soreAreas.map(\.rawValue).joined(separator: ", "))),") }
            if let mood = morning.mood { line += " mood \(mood)/5," }
            if morning.isSick { line += " symptoms: \(morning.symptoms.map(\.rawValue).joined(separator: ", "))," }
            parts.append(String(line.dropLast()))
        }
        if let evening = evening(on: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now) {
            var line = "Last evening:"
            if let caffeine = evening.caffeineMg { line += " caffeine \(Int(caffeine)) mg," }
            if let drinks = evening.drinks { line += " \(drinks) drinks," }
            if let stress = evening.stress { line += " stress \(stress)/5," }
            parts.append(String(line.dropLast()))
        }
        let patterns = insights.prefix(3).map(\.sentence)
        if !patterns.isEmpty { parts.append("Personal patterns: " + patterns.joined(separator: "; ")) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
