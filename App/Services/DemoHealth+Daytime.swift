import Foundation
import AppCore

/// Demo data for the daytime vitals view (`HealthKitClient+Daytime`): what an
/// Apple Watch Series 12 would add to the demo's days. Made up, like the rest
/// of `DemoHealth`, and a deterministic function of the day, so the
/// screenshots repeat.
nonisolated extension DemoHealth {
    /// HRV (SDNN, ms), a reading every five minutes, day and night: the
    /// night's value while asleep (`hrv`), lower while awake and lowest in the
    /// early afternoon, very low in a workout and climbing back for 90
    /// minutes after it.
    func daytimeHRV(from start: Date, to end: Date) -> [DaytimeVitals.Reading] {
        let first = max(start, day(historyDays))
        let last = min(end, now)
        guard first < last else { return [] }
        let nights = sleepHistory(nights: daysAgo(of: first) + 2)
        let workouts = workoutIntervals(from: first.addingTimeInterval(-3 * 3600), to: last)
        var readings: [DaytimeVitals.Reading] = []
        var slot = (first.timeIntervalSince1970 / 300).rounded(.up)
        let lastSlot = last.timeIntervalSince1970 / 300
        while slot < lastSlot {
            let date = Date(timeIntervalSince1970: slot * 300)
            let index = Int(slot)
            let daysAgo = self.daysAgo(of: date)
            let wobble: Double = Self.noise(index, 50)
            let value: Double
            if let night = nights.first(where: { date >= $0.bedtime && date < $0.wake }) {
                value = hrv(max(0, self.daysAgo(of: night.date))) + 6 * wobble
            } else if workouts.contains(where: { date >= $0.start && date < $0.end }) {
                value = 12 + 3 * wobble
            } else {
                // 39 ms on waking, 33 by mid-afternoon, 36 late in the evening.
                // (Split up so the type checker stays quick.)
                let hour: Double = date.timeIntervalSince(calendar.startOfDay(for: date)) / 3600
                let progress: Double = min(1, max(0, (hour - 7) / 16))
                let dip: Double = 6 * sin(progress * Double.pi)
                let dayEffect: Double = 2 * Self.noise(daysAgo, 51)
                var awake: Double = 39 - dip + dayEffect + 5 * wobble
                if let ended = workouts.last(where: { date >= $0.end && date < $0.end.addingTimeInterval(90 * 60) }) {
                    // Back up from about 60% over the 90 minutes after a workout.
                    let recovered: Double = date.timeIntervalSince(ended.end) / (90 * 60)
                    awake *= 0.6 + 0.4 * recovered
                }
                value = awake
            }
            readings.append(DaytimeVitals.Reading(date: date, value: max(5, value)))
            slot += 1
        }
        return readings
    }

    /// Blood oxygen in percent, a reading every half hour: 95-98.
    func daytimeBloodOxygen(from start: Date, to end: Date) -> [DaytimeVitals.Reading] {
        let first = max(start, day(historyDays))
        let last = min(end, now)
        guard first < last else { return [] }
        var readings: [DaytimeVitals.Reading] = []
        var slot = (first.timeIntervalSince1970 / 1800).rounded(.up)
        let lastSlot = last.timeIntervalSince1970 / 1800
        while slot < lastSlot {
            let raw: Double = 96.5 + 1.5 * Self.noise(Int(slot), 53)
            let value = raw.rounded()
            readings.append(DaytimeVitals.Reading(date: Date(timeIntervalSince1970: slot * 1800 + 420), value: value))
            slot += 1
        }
        return readings.filter { $0.date < last }
    }

    /// Steps per minute: the weekday commute (8:15-8:33) and lunch walk
    /// (12:40-12:55), where the demo's heart rate also rises, and a short walk
    /// across the room about every three quarters of an hour from 7:00 to 22:00.
    func stepsPerMinute(from start: Date, to end: Date) -> [DaytimeVitals.StepMinute] {
        let first = max(start, day(historyDays))
        let last = min(end, now)
        guard first < last else { return [] }
        var result: [DaytimeVitals.StepMinute] = []
        var minute = (first.timeIntervalSince1970 / 60).rounded(.up)
        let lastMinute = last.timeIntervalSince1970 / 60
        var dayStart = calendar.startOfDay(for: first)
        var nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        var workday = isWorkday(dayStart)
        while minute < lastMinute {
            let date = Date(timeIntervalSince1970: minute * 60)
            if date >= nextDay {
                dayStart = calendar.startOfDay(for: date)
                nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
                workday = isWorkday(dayStart)
            }
            let minuteOfDay = date.timeIntervalSince(dayStart) / 60
            let index = Int(minute)
            if workday, (495..<513).contains(minuteOfDay) || (760..<775).contains(minuteOfDay) {
                result.append(DaytimeVitals.StepMinute(start: date, steps: 104 + 6 * Self.noise(index, 54)))
            } else if (420..<1320).contains(minuteOfDay), index % 47 < 2 {
                result.append(DaytimeVitals.StepMinute(start: date, steps: 55))
            }
            minute += 1
        }
        return result
    }

    private func isWorkday(_ day: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday != 1 && weekday != 7
    }
}
