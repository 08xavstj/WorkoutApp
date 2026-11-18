import Foundation

/// Travel across time zones (docs/research/next-features-2026-11.md, I3;
/// the open item in qa-2026-11-17.md).
///
/// What was wrong: nights are dated and read on the phone's current clock,
/// so after a long flight the usual wake and bed times (and from them the
/// bed-by window and the caffeine cut-off) were the home times seen from the
/// new zone, e.g. a 06:30 wake in New York read as 12:30 in Paris, for a week
/// or two until enough new nights came in. Dose reminders jumped to the new
/// clock at once.
///
/// What it does now:
/// 1. A zone timeline (`Timeline`) records the phone's zone and when it
///    changed, so every night has the zone it was slept in (by its wake time).
/// 2. Each night's bed and wake times are read on its own zone's clock
///    (`sameWallClock`), so a 06:30 wake stays 06:30.
/// 3. After a change, those habitual times start where the body clock is
///    (home time, seen on the local clock) and move onto local time at
///    `eastHoursPerDay` / `westHoursPerDay` (`Change.remainingHours`). Dose
///    reminders move the same way (`Reminders.scheduleDoses`).
/// 4. After a shift of 5 hours or more, one card: melatonin near the local
///    bedtime (Herxheimer & Petrie, Cochrane 2002) and when to seek and avoid
///    light (Roach & Sargent 2019), with safety lines.
/// 5. Sleep regularity reads each day on its own zone's clock and leaves out
///    the day pairs of the shift (`SleepRegularity.travelAwareScore`).
public enum TravelShift {
    // MARK: Rates

    /// Hours a day the times move after an eastward flight. **App's choice,
    /// not checked at a source this round**: the research doc's rule of about
    /// 1 h a day east and 1.5 h a day west is the usual description of how
    /// fast the body clock re-entrains without help (it advances more slowly
    /// than it delays). Roach & Sargent 2019 (Front Physiol 10:927, PMC full
    /// text read 18 Nov 2026) explain why east is harder but give no daily
    /// rate; their pre-flight advice moves sleep 30-60 min a day.
    public static let eastHoursPerDay = 1.0
    /// Hours a day after a westward flight (app's choice, see `eastHoursPerDay`).
    public static let westHoursPerDay = 1.5
    /// The melatonin and light card from this shift: Herxheimer & Petrie
    /// (Cochrane 2002, CD001520, abstract read 18 Nov 2026) found melatonin
    /// reduced jet lag "from flights crossing five or more time zones".
    public static let jetLagCardHours = 5.0
    /// When the zone changed while the app wasn't open, the change is dated
    /// to the last time the old zone was seen, but no earlier than this
    /// before it was noticed (app's choice): nights in that gap go to the new
    /// zone, which during the shift leaves them out of the habitual times
    /// (harmless) rather than reading a night in Paris on New York's clock.
    public static let maxBackdate: TimeInterval = 2 * 86_400
    /// Changes kept, days (app's choice: longer than the 90 nights any screen reads).
    public static let keepDays = 120

    // MARK: Zones

    /// Signed hours `to`'s clock is ahead of `from`'s at `date` (positive =
    /// eastward), the shorter way round the globe (-12...12): Hawaii to
    /// Kiribati (+14 vs -10) is 0, the same clock time a day apart. Both read
    /// at the same moment, so a daylight-saving change inside one zone is
    /// never travel.
    public static func hoursAhead(from: TimeZone, to: TimeZone, at date: Date) -> Double {
        wrap(Double(to.secondsFromGMT(for: date) - from.secondsFromGMT(for: date)) / 3600)
    }

    static func wrap(_ hours: Double) -> Double {
        var value = hours.truncatingRemainder(dividingBy: 24)
        if value > 12 { value -= 24 }
        if value < -12 { value += 24 }
        return value
    }

    /// `date` moved so that, read in `current`, it shows the clock time it had
    /// in `zone`: a 06:30 New York wake read in Paris stays 06:30. Unchanged
    /// when the zones are the same or share the offset.
    public static func sameWallClock(_ date: Date, recordedIn zone: TimeZone, readIn current: TimeZone) -> Date {
        guard zone.identifier != current.identifier else { return date }
        return date.addingTimeInterval(TimeInterval(zone.secondsFromGMT(for: date) - current.secondsFromGMT(for: date)))
    }

    // MARK: A change

    public struct Change: Codable, Sendable, Equatable, Identifiable {
        /// From when nights belong to the new zone: the last time the old zone
        /// was seen, at most `maxBackdate` before `noticed`.
        public var date: Date
        /// When the phone was first seen in the new zone; the shift's days
        /// count from this day (the arrival day, as near as the app can tell).
        public var noticed: Date
        public var from: String
        public var to: String
        /// The flight's own difference, `hoursAhead(from:to:)`.
        public var flightHours: Double
        /// The shift the body clock has to make: the flight's difference plus
        /// any shift still under way from an earlier change (a return after
        /// two days in Paris is a smaller shift than the outward flight),
        /// wrapped to -12...12. Positive = eastward (an advance).
        public var hours: Double

        public var id: Date { date }

        public init(date: Date, noticed: Date? = nil, from: String, to: String, flightHours: Double, hours: Double) {
            self.date = date
            self.noticed = noticed ?? date
            self.from = from
            self.to = to
            self.flightHours = flightHours
            self.hours = hours
        }

        public var isEastward: Bool { hours > 0 }
        public var hoursPerDay: Double { isEastward ? TravelShift.eastHoursPerDay : TravelShift.westHoursPerDay }

        /// Days until the times are on local time (1 for a shift of up to an
        /// hour east or 1.5 h west, which is on local time at once).
        public var shiftDays: Int { max(1, Int((abs(hours) / hoursPerDay - 1e-9).rounded(.up))) }

        /// Hours the habitual times still sit away from local time on `day`
        /// (local times = habitual + this; positive after an eastward flight,
        /// so later on the local clock). The first step counts on the arrival
        /// day, so a one-hour change is on local time straight away; after
        /// `shiftDays` it is 0.
        public func remainingHours(on day: Date, calendar: Calendar = .current) -> Double {
            let start = calendar.startOfDay(for: noticed)
            let elapsed = max(0, calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: day)).day ?? 0)
            let left = max(0, abs(hours) - hoursPerDay * Double(elapsed + 1))
            return left < 1e-9 ? 0 : (isEastward ? left : -left)
        }

        /// `remainingHours` in whole minutes, for times of day.
        public func remainingMinutes(on day: Date, calendar: Calendar = .current) -> Int {
            Int((remainingHours(on: day, calendar: calendar) * 60).rounded())
        }

        public func isShifting(on day: Date, calendar: Calendar = .current) -> Bool {
            remainingHours(on: day, calendar: calendar) != 0
        }

        /// The last day of the shift (the day `remainingHours` is still not 0).
        public func lastShiftDay(calendar: Calendar = .current) -> Date {
            calendar.date(byAdding: .day, value: shiftDays - 2, to: calendar.startOfDay(for: noticed)) ?? noticed
        }

        /// The melatonin and light card applies (`jetLagCardHours`). Read on
        /// the body-clock shift, not the flight: a return after two days away
        /// isn't a 5-zone shift.
        public var warrantsJetLagCard: Bool { abs(hours) >= TravelShift.jetLagCardHours - 1e-9 }
    }

    // MARK: The zone timeline

    /// The phone's zone over time: the first zone seen and every change since.
    public struct Timeline: Codable, Sendable, Equatable {
        /// The zone before the first kept change.
        public var firstZone: String
        /// Oldest first.
        public var changes: [Change]
        public var lastZone: String
        public var lastSeen: Date

        public init(zone: String, at date: Date) {
            firstZone = zone
            changes = []
            lastZone = zone
            lastSeen = date
        }

        /// The latest change of clock (a flight), skipping zone renames with the same offset.
        public var latestFlight: Change? { changes.last { $0.flightHours != 0 } }

        /// Notes the phone's zone now. Returns the change when the clock
        /// moved: a new identifier with the same offset (Paris to Berlin) only
        /// updates the zone, and a daylight-saving change keeps the identifier.
        @discardableResult
        public mutating func observe(_ current: TimeZone, at now: Date, calendar: Calendar = .current) -> Change? {
            defer {
                lastZone = current.identifier
                lastSeen = max(lastSeen, now)
                prune(now: now)
            }
            guard current.identifier != lastZone, let previous = TimeZone(identifier: lastZone) else { return nil }
            let flight = TravelShift.hoursAhead(from: previous, to: current, at: now)
            let date = min(now, max(lastSeen, now.addingTimeInterval(-TravelShift.maxBackdate)))
            guard flight != 0 else {
                // Same clock: nights keep reading the same, so no change is needed. The
                // zone is still recorded (as a zero change) so each night's zone is right.
                changes.append(Change(date: date, noticed: now, from: lastZone, to: current.identifier, flightHours: 0, hours: 0))
                return nil
            }
            let carried = latestFlight?.remainingHours(on: now, calendar: calendar) ?? 0
            let change = Change(date: date, noticed: now, from: lastZone, to: current.identifier, flightHours: flight,
                                hours: TravelShift.wrap(carried + flight))
            changes.append(change)
            return change
        }

        /// The zone the phone was in at `date`.
        public func zoneIdentifier(at date: Date) -> String {
            var zone = firstZone
            for change in changes where change.date <= date { zone = change.to }
            return zone
        }

        public func zone(at date: Date) -> TimeZone? { TimeZone(identifier: zoneIdentifier(at: date)) }

        /// The latest change while its times are still moving on `day`; nil
        /// once they're on local time.
        public func activeChange(on day: Date, calendar: Calendar = .current) -> Change? {
            guard let latest = latestFlight, latest.hours != 0, latest.isShifting(on: day, calendar: calendar) else { return nil }
            return latest
        }

        mutating func prune(now: Date) {
            let cutoff = now.addingTimeInterval(-Double(TravelShift.keepDays) * 86_400)
            while let first = changes.first, first.date < cutoff, changes.count > 1 {
                firstZone = first.to
                changes.removeFirst()
            }
        }
    }

    // MARK: Habitual times

    public struct NightTimes: Sendable, Equatable {
        public var bedtime: Date
        public var wake: Date

        public init(bedtime: Date, wake: Date) {
            self.bedtime = bedtime
            self.wake = wake
        }
    }

    /// The nights to take usual bed and wake times from (the bed-by window,
    /// the caffeine cut-off), each read on its own zone's clock and moved by
    /// today's remaining shift. While a shift runs, nights slept since the
    /// change are left out: they are the jet-lagged nights the shift is
    /// steering, and counting them would move the times twice. Unchanged when
    /// the timeline has no changes.
    public static func habitual(_ nights: [NightTimes], timeline: Timeline, current: TimeZone, now: Date,
                                calendar: Calendar = .current) -> [NightTimes] {
        guard !timeline.changes.isEmpty else { return nights }
        let active = timeline.activeChange(on: now, calendar: calendar)
        let shift = TimeInterval((active?.remainingMinutes(on: now, calendar: calendar) ?? 0) * 60)
        return nights.compactMap { night in
            if let active, night.wake >= active.date { return nil }
            let zone = timeline.zone(at: night.wake) ?? current
            return NightTimes(bedtime: sameWallClock(night.bedtime, recordedIn: zone, readIn: current).addingTimeInterval(shift),
                              wake: sameWallClock(night.wake, recordedIn: zone, readIn: current).addingTimeInterval(shift))
        }
    }

    // MARK: The jet-lag card

    /// The card shows while the latest change of 5 hours or more is still
    /// shifting, unless it was dismissed.
    public static func jetLagCard(_ timeline: Timeline, dismissed: Date?, now: Date, calendar: Calendar = .current) -> Change? {
        guard let active = timeline.activeChange(on: now, calendar: calendar), active.warrantsJetLagCard,
              dismissed != active.date else { return nil }
        return active
    }

    /// Melatonin, as the Cochrane review found it (Herxheimer & Petrie 2002,
    /// CD001520; 10 trials, 9 usable). Evidence moderate: small trials.
    public static let melatoninLines = [
        "Melatonin 0.5 to 5 mg taken close to your target bedtime here (10 pm to midnight) reduced jet lag in 9 of 10 trials after flights across 5 or more time zones; for every 2 people who take it, 1 more is helped than with a placebo (NNT 2). 5 mg helps you fall asleep a little faster than 0.5 mg; more than 5 mg did no better.",
        "It helps more the more zones you cross, and more flying east than west.",
        "Timing matters: taken early in the day it makes you sleepy and slows the switch to local time.",
    ]

    /// The review's safety lines: case reports of harm in people with
    /// epilepsy and in people taking warfarin.
    public static let melatoninSafety = "If you take warfarin or another blood thinner, or have epilepsy, ask a doctor before taking melatonin. In some countries it needs a prescription."

    /// Light timing (Roach & Sargent 2019, a narrative review built mostly on
    /// lab phase-response curves and models; no field trial of light timing,
    /// so weak to moderate). The body clock's low point (core temperature
    /// minimum) sits about 3 hours before your usual wake time on home time
    /// (melatonin starts about 2 h before bed and the minimum comes about 7 h
    /// later; their 23:00-07:00 sleeper has it at 04:00). Light in the ~3 h
    /// before it moves the clock later, in the ~3 h after it moves it earlier.
    public struct LightAdvice: Sendable, Equatable {
        /// Minutes after local midnight, 0..<1440; a window can wrap past midnight.
        public var seekStart: Int
        public var seekEnd: Int
        public var avoidStart: Int
        public var avoidEnd: Int
        public var isEastward: Bool
    }

    /// Hours before the usual wake time that the body clock's low point sits (Roach 2019).
    public static let lowPointHoursBeforeWake = 3.0
    /// Width of the seek and avoid windows, hours (Roach 2019: "~3 h").
    public static let lightWindowHours = 3.0

    /// - Parameter shiftedWakeMinutes: the usual wake time with today's shift
    ///   (`habitual`), minutes after local midnight: where the body clock
    ///   thinks morning is, on the local clock.
    public static func lightAdvice(isEastward: Bool, shiftedWakeMinutes: Int) -> LightAdvice {
        let low = shiftedWakeMinutes - Int(lowPointHoursBeforeWake * 60)
        let width = Int(lightWindowHours * 60)
        func day(_ minutes: Int) -> Int { ((minutes % 1440) + 1440) % 1440 }
        // East needs an advance: light after the low point, none before it. West the reverse.
        let after = (day(low), day(low + width))
        let before = (day(low - width), day(low))
        let seek = isEastward ? after : before
        let avoid = isEastward ? before : after
        return LightAdvice(seekStart: seek.0, seekEnd: seek.1, avoidStart: avoid.0, avoidEnd: avoid.1, isEastward: isEastward)
    }
}

// MARK: - Sleep regularity across a time-zone change

extension SleepRegularity {
    /// The Sleep Regularity Index with travel taken out:
    /// - Each noon-to-noon day starts at noon on the clock of the zone the
    ///   night was slept in (`TravelShift.Timeline.zoneIdentifier` at that
    ///   morning), so a 23:00-07:00 sleeper in New York and then Paris is
    ///   compared clock to clock and reads as regular, not as an 8-hour jump.
    /// - The day pairs of a shift are left out (as if one day had no data):
    ///   from the pair ending on the change's morning to the pair ending on
    ///   the morning after its last shift day, and any pair whose two zones
    ///   have different clocks. Those nights move on purpose (the shift plan
    ///   moves bed-by by an hour or more a night), so they aren't counted as
    ///   irregular sleep. With fewer than `minimumPairs` pairs left the index
    ///   is nil, the same as with too few nights.
    /// With no changes in the timeline this is exactly `score(asleep:start:days:calendar:)`.
    /// - Parameters:
    ///   - firstMorning: the first night's morning (start of day, current calendar).
    ///   - mornings: how many mornings from `firstMorning` (inclusive) to compare.
    public static func travelAwareScore(asleep: [DateInterval], firstMorning: Date, mornings: Int,
                                        timeline: TravelShift.Timeline, calendar: Calendar = .current) -> Int? {
        guard mornings >= 2 else { return nil }
        let morningDates = (0..<mornings).compactMap { calendar.date(byAdding: .day, value: $0, to: firstMorning) }
        guard morningDates.count == mornings else { return nil }
        // The zone of the night ending each morning: where the phone was at 09:00
        // that morning on the current clock (app's choice; any time near waking works).
        let zones = morningDates.map { timeline.zone(at: $0.addingTimeInterval(9 * 3600)) ?? calendar.timeZone }
        let dayStarts = zip(morningDates, zones).map { morning, zone -> Date in
            // Noon the day before, on that zone's clock.
            var local = calendar
            local.timeZone = zone
            let previous = calendar.date(byAdding: .day, value: -1, to: morning) ?? morning.addingTimeInterval(-86_400)
            var parts = calendar.dateComponents([.year, .month, .day], from: previous)
            parts.hour = 12
            return local.date(from: parts) ?? previous.addingTimeInterval(12 * 3600)
        }
        var skip = Set<Int>()
        for index in 0..<(mornings - 1)
        where TravelShift.hoursAhead(from: zones[index], to: zones[index + 1], at: morningDates[index + 1]) != 0 {
            skip.insert(index)
        }
        for change in timeline.changes where change.hours != 0 {
            guard let first = calendar.dateComponents([.day], from: firstMorning, to: calendar.startOfDay(for: change.date)).day,
                  let arrival = calendar.dateComponents([.day], from: firstMorning, to: calendar.startOfDay(for: change.noticed)).day
            else { continue }
            // Pairs ending on the mornings from the change's day to `shiftDays` after
            // arrival (the morning after the last shifted night); pair index = ending - 1.
            for ending in first...max(first, arrival + change.shiftDays) where ending >= 1 && ending < mornings {
                skip.insert(ending - 1)
            }
        }
        return index(asleep: asleep, dayStarts: dayStarts, skippingPairs: skip).map { Int(min(100, max(0, $0)).rounded()) }
    }
}
