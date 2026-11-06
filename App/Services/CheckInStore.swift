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
        /// Strain per day (0-100), kept so patterns can test "a harder day than usual".
        var strains: [String: Double]? = [:]
        /// What your training days usually reach, from the last refresh.
        var usualTrainingStrain: Double?
        /// Your sleep need (h), from Settings at the last refresh (sleep-debt factor).
        var sleepNeedHours: Double?
    }

    private var saved = Saved()
    private(set) var insights: [CheckInInsights.Insight] = []
    private(set) var daysUntilInsights = 14
    /// Habits still short of 7 days each way ("Sauna 4/7 days").
    private(set) var habitProgress: [CheckInInsights.FactorProgress] = []
    /// Your next-morning numbers after drinking vs not.
    private(set) var alcoholFindings: [AlcoholEffect.Finding] = []
    /// Nights with a known drink count (0 or more), for the empty state.
    private(set) var alcoholNightsLogged = 0
    /// The last 30 days of moods: Health's (any app) first, the check-ins'
    /// where Health has nothing (`MoodHistory.merge`). Oldest first.
    private(set) var moods: [MoodSample] = []

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

    /// Keeps each day's strain, your usual training strain and your sleep
    /// need, so the mood patterns can use them (`CheckInInsights`).
    /// Today's value is overwritten on every call; finished days settle.
    func recordContext(dayStrains: [(date: Date, strain: Double)], usualTrainingStrain: Double?, sleepNeedHours: Double) {
        var changed = false
        var strains = saved.strains ?? [:]
        for day in dayStrains where strains[key(day.date)] != day.strain {
            strains[key(day.date)] = day.strain
            changed = true
        }
        if changed { saved.strains = strains }
        if saved.usualTrainingStrain != usualTrainingStrain {
            saved.usualTrainingStrain = usualTrainingStrain
            changed = true
        }
        if saved.sleepNeedHours != sleepNeedHours {
            saved.sleepNeedHours = sleepNeedHours
            changed = true
        }
        if changed { write() }
    }

    /// The check-ins' moods as State of Mind entries (morning = daily mood,
    /// evening = momentary emotion), for merging with Health's.
    private func checkInMoods(from start: Date) -> [MoodSample] {
        var samples: [MoodSample] = []
        for morning in saved.mornings.values where morning.day >= start {
            guard let mood = morning.mood else { continue }
            samples.append(MoodSample(
                // The check-in has no clock time: 8 am, never later than now.
                date: min(Date.now, morning.day.addingTimeInterval(8 * 3600)), valence: MoodScale.valence(mood: mood), kind: .daily,
                labels: morning.feelings ?? [], associations: morning.associations ?? [], fromThisApp: true
            ))
        }
        for evening in saved.evenings.values where evening.day >= start {
            guard let valence = evening.eveningValence else { continue }
            samples.append(MoodSample(
                date: min(Date.now, evening.day.addingTimeInterval(21 * 3600)), valence: valence, kind: .momentary,
                labels: evening.feelings ?? [], associations: evening.associations ?? [], fromThisApp: true
            ))
        }
        return samples
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
        let nights = (try? await health.sleepHistory(nights: 90)) ?? []
        let rmssd = await health.nightlyRMSSD(nights: nights).merging(manualHRV.filter { $0.value > 0 }) { _, typed in typed }
        let vitals = DailyVitals.merging((try? await health.nightlyVitals(days: 90, endingOn: today)) ?? [], manualHRV: rmssd, manualOnlyHRV: true)
        var byMorning: [String: DailyVitals] = [:]
        for vital in vitals { byMorning[key(vital.date)] = vital }
        var waterByDay: [String: Double] = [:]
        for day in (try? await health.dailySeries(.dietaryWater, unit: .liter(), days: 91, cumulative: true)) ?? [] {
            waterByDay[key(day.date)] = day.value
        }
        // Drinks your food app logged (used when there's no evening check-in).
        var drinksByDay: [String: Int] = [:]
        for day in (try? await health.dailySeries(.numberOfAlcoholicBeverages, unit: .count(), days: 91, cumulative: true)) ?? [] {
            drinksByDay[key(day.date)] = Int(day.value.rounded())
        }
        // When you fell asleep, by morning.
        var bedtimeByMorning: [String: Int] = [:]
        for night in (try? await health.sleepNights(nights: 90)) ?? [] {
            let morning = calendar.startOfDay(for: night.wake)
            guard let evening = calendar.date(byAdding: .day, value: -1, to: morning) else { continue }
            bedtimeByMorning[key(morning)] = Int(night.bedtime.timeIntervalSince(evening) / 60)
        }
        var alcoholNights: [AlcoholEffect.Night] = []
        // Mood (watch-features.md 4.1): Health's State of Mind for 90 days, this
        // app's own entries dropped (they mirror the check-ins), merged per day.
        let moodStart = calendar.date(byAdding: .day, value: -90, to: today) ?? today
        let healthMoods = (try? await health.stateOfMind(from: moodStart, to: .now)) ?? []
        let allMoods = MoodHistory.merge(health: healthMoods, checkIns: checkInMoods(from: moodStart))
        var moodByMorning: [String: Double] = [:]
        for day in MoodHistory.dailyValence(allMoods) {
            moodByMorning[key(day.day)] = day.valence
        }
        let moodWindow = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        moods = allMoods.filter { $0.date >= moodWindow }
        // Training days: any workout of 10 min or more, from any app.
        var trainingDays = Set<String>()
        for workout in (try? await health.workoutIntervals(from: moodStart, to: .now)) ?? [] where workout.duration >= 10 * 60 {
            trainingDays.insert(key(workout.start))
        }
        var mindfulByDay: [String: Double] = [:]
        for day in (try? await health.mindfulMinutes(days: 91)) ?? [] {
            mindfulByDay[key(day.date)] = day.value
        }
        // Sleep debt up to each morning: the running 14-night balance (`SleepDebt`).
        var debtByMorning: [String: Double] = [:]
        if let need = saved.sleepNeedHours {
            let ordered = nights.sorted { $0.wake < $1.wake }
            for (index, night) in ordered.enumerated() {
                let window = ordered[max(0, index - SleepDebt.nights + 1)...index].map(\.hoursAsleep)
                if let debt = SleepDebt.compute(nightlyHours: window, needHours: need) {
                    debtByMorning[key(calendar.startOfDay(for: night.wake))] = debt.hours
                }
            }
        }

        var days: [CheckInDay] = []
        for offset in 0..<90 {
            guard let morning = calendar.date(byAdding: .day, value: -offset, to: today),
                  let previous = calendar.date(byAdding: .day, value: -1, to: morning) else { continue }
            let evening = saved.evenings[key(previous)]
            let checkIn = saved.mornings[key(morning)]
            let water = waterByDay[key(previous)]
            let vital = byMorning[key(morning)]
            if let drinks = evening?.drinks ?? drinksByDay[key(previous)] {
                alcoholNights.append(AlcoholEffect.Night(
                    morning: morning, drinks: drinks, restingHeartRate: vital?.restingHeartRate,
                    hrv: vital?.hrvMilliseconds, sleepScore: saved.sleepScores[key(morning)]
                ))
            }
            let mood = moodByMorning[key(morning)]
            guard evening != nil || checkIn != nil || water != nil || mood != nil else { continue }
            days.append(CheckInDay(
                morning: morning, evening: evening, checkIn: checkIn,
                hrv: vital?.hrvMilliseconds, restingHeartRate: vital?.restingHeartRate,
                sleepScore: saved.sleepScores[key(morning)],
                waterLiters: water,
                bedtimeMinutes: bedtimeByMorning[key(morning)],
                moodValence: mood,
                // Workouts are known for the whole window, so a day with none is a rest day.
                trainedYesterday: trainingDays.contains(key(previous)),
                strainYesterday: saved.strains?[key(previous)],
                usualTrainingStrain: saved.usualTrainingStrain,
                sleepDebtHours: debtByMorning[key(morning)],
                mindfulMinutes: mindfulByDay[key(previous)] ?? 0
            ))
        }
        alcoholFindings = AlcoholEffect.compare(alcoholNights)
        insights = CheckInInsights.merged(CheckInInsights.analyze(days), alcohol: alcoholFindings)
        daysUntilInsights = CheckInInsights.daysUntilReady(days)
        habitProgress = CheckInInsights.uncovered(CheckInInsights.progress(days), by: insights)
        alcoholNightsLogged = alcoholNights.count
    }

    /// Short summary for the AI coach.
    var coachSummary: String? {
        var parts: [String] = []
        if let morning = morning() {
            var line = "This morning:"
            if let rested = morning.rested { line += " rested \(rested)/5," }
            if let soreness = morning.soreness { line += " soreness \(soreness)/10" + (morning.soreAreas.isEmpty ? "," : " (\(morning.soreAreas.map(\.rawValue).joined(separator: ", "))),") }
            if let mood = morning.mood {
                let feelings = (morning.feelings ?? []).map(MoodScale.readable).joined(separator: ", ").lowercased()
                line += " mood \(mood)/5" + (feelings.isEmpty ? "," : " (\(feelings)),")
            }
            if let associations = morning.associations, !associations.isEmpty { line += " on their mind: \(associations.map(MoodScale.readable).joined(separator: ", ").lowercased())," }
            if morning.isSick { line += " symptoms: \(morning.symptoms.map(\.rawValue).joined(separator: ", "))," }
            parts.append(String(line.dropLast()))
        }
        if let evening = evening(on: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now) {
            var line = "Last evening:"
            if let caffeine = evening.caffeineMg { line += " caffeine \(Int(caffeine)) mg," }
            if let total = evening.standardDrinks, let items = evening.alcohol {
                let kinds = Dictionary(grouping: items, by: \.kind).map { "\($0.value.count) \($0.key.label.lowercased())" }.sorted()
                line += " \(total.formatted(.number.precision(.fractionLength(1)))) standard drinks (\(kinds.joined(separator: ", ")))" + (evening.lastDrinkMinutes.map { ", last at \(DrinkVolume.clock($0))" } ?? "") + ","
            } else if let drinks = evening.drinks { line += " \(drinks) drinks," }
            if let stress = evening.stress { line += " stress \(stress)/5," }
            parts.append(String(line.dropLast()))
        }
        let patterns = insights.prefix(3).map(\.sentence)
        if !patterns.isEmpty { parts.append("Personal patterns: " + patterns.joined(separator: "; ")) }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}
