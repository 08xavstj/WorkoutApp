import Foundation
import Testing
@testable import AppCore

struct TravelShiftTests {
    let newYork = TimeZone(identifier: "America/New_York")!
    let paris = TimeZone(identifier: "Europe/Paris")!
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    func date(_ zone: TimeZone, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar(zone).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// New York on 8 Nov at 17:00, Paris from 9 Nov at 09:00 (6 h east in November).
    func flightToParis() -> TravelShift.Timeline {
        var timeline = TravelShift.Timeline(zone: newYork.identifier, at: date(newYork, 11, 1, 8))
        timeline.observe(newYork, at: date(newYork, 11, 8, 17), calendar: calendar(newYork))
        timeline.observe(paris, at: date(paris, 11, 9, 9), calendar: calendar(paris))
        return timeline
    }

    // MARK: Zones

    @Test func hoursAhead() {
        let november = date(paris, 11, 9, 9)
        #expect(TravelShift.hoursAhead(from: newYork, to: paris, at: november) == 6)
        #expect(TravelShift.hoursAhead(from: paris, to: losAngeles, at: november) == -9)
        // The shorter way round: Honolulu (-10) to Kiritimati (+14) is the same clock time.
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!
        let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")!
        #expect(TravelShift.hoursAhead(from: honolulu, to: kiritimati, at: november) == 0)
        // Tokyo (+9) to Los Angeles (-8 in November): 17 h west is 7 h east the other way.
        #expect(TravelShift.hoursAhead(from: TimeZone(identifier: "Asia/Tokyo")!, to: losAngeles, at: november) == 7)
    }

    @Test func daylightSavingIsNotTravel() {
        var timeline = TravelShift.Timeline(zone: newYork.identifier, at: date(newYork, 10, 31, 12))
        // US clocks went back on 1 Nov 2026: same identifier, so nothing happens.
        #expect(timeline.observe(newYork, at: date(newYork, 11, 2, 12), calendar: calendar(newYork)) == nil)
        #expect(timeline.changes.isEmpty)
    }

    @Test func sameOffsetRenameIsNotAShift() {
        var timeline = TravelShift.Timeline(zone: paris.identifier, at: date(paris, 11, 1, 12))
        #expect(timeline.observe(berlin, at: date(berlin, 11, 2, 12), calendar: calendar(berlin)) == nil)
        #expect(timeline.zoneIdentifier(at: date(berlin, 11, 3, 0)) == berlin.identifier)
        #expect(timeline.activeChange(on: date(berlin, 11, 2, 12), calendar: calendar(berlin)) == nil)
    }

    @Test func sameWallClock() {
        let wake = date(newYork, 11, 5, 7, 30)
        let moved = TravelShift.sameWallClock(wake, recordedIn: newYork, readIn: paris)
        let parts = calendar(paris).dateComponents([.hour, .minute], from: moved)
        #expect(parts.hour == 7 && parts.minute == 30)
        #expect(TravelShift.sameWallClock(wake, recordedIn: paris, readIn: paris) == wake)
    }

    // MARK: The shift

    @Test func eastwardMovesAnHourADay() throws {
        let timeline = flightToParis()
        let change = try #require(timeline.activeChange(on: date(paris, 11, 9, 12), calendar: calendar(paris)))
        #expect(change.hours == 6)
        #expect(change.isEastward)
        #expect(change.shiftDays == 6)
        // Nights belong to Paris from the last time New York was seen.
        #expect(change.date == date(newYork, 11, 8, 17))
        let paris = calendar(self.paris)
        let expected: [Double] = [5, 4, 3, 2, 1, 0, 0]
        for (offset, hours) in expected.enumerated() {
            let day = paris.date(byAdding: .day, value: offset, to: date(self.paris, 11, 9, 12))!
            #expect(change.remainingHours(on: day, calendar: paris) == hours)
        }
        #expect(timeline.activeChange(on: date(self.paris, 11, 14, 12), calendar: paris) == nil)
    }

    @Test func westwardMovesAnHourAndAHalfADay() {
        let change = TravelShift.Change(date: date(paris, 11, 9, 9), from: paris.identifier, to: losAngeles.identifier,
                                        flightHours: -9, hours: -9)
        let la = calendar(losAngeles)
        #expect(change.shiftDays == 6)
        #expect(change.remainingHours(on: date(paris, 11, 9, 9), calendar: la) == -7.5)
        #expect(change.remainingMinutes(on: la.date(byAdding: .day, value: 4, to: date(paris, 11, 9, 9))!, calendar: la) == -90)
        #expect(change.remainingHours(on: la.date(byAdding: .day, value: 5, to: date(paris, 11, 9, 9))!, calendar: la) == 0)
    }

    @Test func smallChangesAreLocalAtOnce() {
        let change = TravelShift.Change(date: date(paris, 11, 9, 9), from: "Europe/London", to: paris.identifier, flightHours: 1, hours: 1)
        #expect(!change.isShifting(on: date(paris, 11, 9, 9), calendar: calendar(paris)))
        #expect(change.shiftDays == 1)
    }

    @Test func aQuickReturnCarriesWhatWasLeft() throws {
        var timeline = flightToParis()
        // Two days later (remaining then 4 h), back to New York: the body clock is 2 h ahead of New York.
        let observed = timeline.observe(newYork, at: date(newYork, 11, 10, 20), calendar: calendar(newYork))
        let back = try #require(observed)
        #expect(back.flightHours == -6)
        #expect(back.hours == -2)
        #expect(!back.warrantsJetLagCard)
    }

    // MARK: Habitual times

    @Test func habitualTimesStartOnHomeTimeAndMoveToLocal() throws {
        let timeline = flightToParis()
        let homeNights = (2...8).map { day in
            TravelShift.NightTimes(bedtime: date(newYork, 11, day - 1, 23), wake: date(newYork, 11, day, 7))
        }
        // A jet-lagged first night in Paris.
        let parisNight = TravelShift.NightTimes(bedtime: date(self.paris, 11, 10, 3), wake: date(self.paris, 11, 10, 11))
        let paris = calendar(self.paris)

        let arrival = TravelShift.habitual(homeNights + [parisNight], timeline: timeline, current: self.paris,
                                           now: date(self.paris, 11, 9, 15), calendar: paris)
        #expect(arrival.count == homeNights.count) // the Paris night is left out while the shift runs
        let first = try #require(arrival.first)
        // 07:00 home + 5 h still to go = 12:00 on the Paris clock.
        #expect(paris.component(.hour, from: first.wake) == 12)
        #expect(paris.component(.hour, from: first.bedtime) == 4)

        let done = TravelShift.habitual(homeNights + [parisNight], timeline: timeline, current: self.paris,
                                        now: date(self.paris, 11, 20, 15), calendar: paris)
        #expect(done.count == homeNights.count + 1)
        // Once on local time, home nights read on their own clock: 07:00.
        #expect(paris.component(.hour, from: try #require(done.first).wake) == 7)
    }

    @Test func habitualIsUnchangedWithoutTravel() {
        let timeline = TravelShift.Timeline(zone: paris.identifier, at: date(self.paris, 11, 1, 8))
        let nights = [TravelShift.NightTimes(bedtime: date(paris, 11, 4, 23), wake: date(paris, 11, 5, 7))]
        #expect(TravelShift.habitual(nights, timeline: timeline, current: paris, now: date(paris, 11, 6, 9), calendar: calendar(paris)) == nights)
    }

    // MARK: Card and light

    @Test func jetLagCardFromFiveHours() throws {
        let timeline = flightToParis()
        let paris = calendar(self.paris)
        let day = date(self.paris, 11, 10, 9)
        let card = try #require(TravelShift.jetLagCard(timeline, dismissed: nil, now: day, calendar: paris))
        #expect(TravelShift.jetLagCard(timeline, dismissed: card.date, now: day, calendar: paris) == nil)
        #expect(TravelShift.jetLagCard(timeline, dismissed: nil, now: date(self.paris, 11, 20, 9), calendar: paris) == nil)

        var short = TravelShift.Timeline(zone: "Europe/London", at: date(self.paris, 11, 1, 8))
        short.observe(TimeZone(identifier: "Asia/Dubai")!, at: date(self.paris, 11, 2, 8), calendar: paris)
        #expect(short.latestFlight?.hours == 4)
        #expect(TravelShift.jetLagCard(short, dismissed: nil, now: date(self.paris, 11, 2, 12), calendar: paris) == nil)
    }

    @Test func lightWindows() {
        // Wake 07:00 on the body clock: low point 04:00.
        let east = TravelShift.lightAdvice(isEastward: true, shiftedWakeMinutes: 7 * 60)
        #expect(east.seekStart == 4 * 60 && east.seekEnd == 7 * 60)
        #expect(east.avoidStart == 1 * 60 && east.avoidEnd == 4 * 60)
        let west = TravelShift.lightAdvice(isEastward: false, shiftedWakeMinutes: 7 * 60)
        #expect(west.seekStart == 1 * 60 && west.avoidStart == 4 * 60)
        // Wrapping past midnight: wake 01:00, low point 22:00.
        let late = TravelShift.lightAdvice(isEastward: true, shiftedWakeMinutes: 60)
        #expect(late.seekStart == 22 * 60 && late.seekEnd == 60 && late.avoidStart == 19 * 60)
    }

    // MARK: Regularity

    /// Asleep 23:00-07:00 on the local clock: New York for the mornings of
    /// 2-8 Nov, no night on the 9th (the flight), Paris for 10-24 Nov.
    func tripSleep() -> [DateInterval] {
        let home = (2...8).map { DateInterval(start: date(newYork, 11, $0 - 1, 23), end: date(newYork, 11, $0, 7)) }
        let away = (10...24).map { DateInterval(start: date(paris, 11, $0 - 1, 23), end: date(paris, 11, $0, 7)) }
        return home + away
    }

    @Test func travelIsNotIrregularSleep() throws {
        let paris = calendar(self.paris)
        let firstMorning = paris.startOfDay(for: date(self.paris, 11, 2, 12))
        let aware = try #require(SleepRegularity.travelAwareScore(asleep: tripSleep(), firstMorning: firstMorning, mornings: 23,
                                                                  timeline: flightToParis(), calendar: paris))
        #expect(aware == 100)
        // Without the zones the same sleep reads as irregular.
        let start = paris.date(bySettingHour: 12, minute: 0, second: 0, of: paris.date(byAdding: .day, value: -1, to: firstMorning)!)!
        let naive = try #require(SleepRegularity.score(asleep: tripSleep(), start: start, days: 23, calendar: paris))
        #expect(naive < aware)
    }

    @Test func regularityWithoutTravelIsUnchanged() {
        let paris = calendar(self.paris)
        let firstMorning = paris.startOfDay(for: date(self.paris, 11, 10, 12))
        // Varying bedtimes so the score isn't trivially 100.
        let asleep = (10...20).map { day in
            DateInterval(start: date(self.paris, 11, day - 1, 22).addingTimeInterval(Double(day % 3) * 3600), end: date(self.paris, 11, day, 7))
        }
        let timeline = TravelShift.Timeline(zone: self.paris.identifier, at: date(self.paris, 11, 1, 8))
        let start = paris.date(bySettingHour: 12, minute: 0, second: 0, of: paris.date(byAdding: .day, value: -1, to: firstMorning)!)!
        #expect(SleepRegularity.travelAwareScore(asleep: asleep, firstMorning: firstMorning, mornings: 11, timeline: timeline, calendar: paris)
                == SleepRegularity.score(asleep: asleep, start: start, days: 11, calendar: paris))
    }

    // MARK: Dose reminders

    @Test func doseShiftAppliesOnlyWithinWakingHours() {
        // No shift: the set time.
        #expect(TravelShift.doseReminderMinutes(setMinutes: 8 * 60, shiftMinutes: 0) == 8 * 60)
        // 08:00 dose, 5 h still to go east: 13:00 local, inside waking hours.
        #expect(TravelShift.doseReminderMinutes(setMinutes: 8 * 60, shiftMinutes: 300) == 13 * 60)
        // 20:00 dose + 5 h = 01:00: the night, so the set local time.
        #expect(TravelShift.doseReminderMinutes(setMinutes: 20 * 60, shiftMinutes: 300) == 20 * 60)
        // 09:00 dose, 4.5 h west = 04:30: before 07:00, so 09:00.
        #expect(TravelShift.doseReminderMinutes(setMinutes: 9 * 60, shiftMinutes: -270) == 9 * 60)
        // The edges count as waking hours.
        #expect(TravelShift.doseReminderMinutes(setMinutes: 21 * 60, shiftMinutes: 60) == 22 * 60)
        #expect(TravelShift.doseReminderMinutes(setMinutes: 8 * 60, shiftMinutes: -60) == 7 * 60)
        #expect(TravelShift.doseReminderMinutes(setMinutes: 21 * 60, shiftMinutes: 61) == 21 * 60)
    }

    @Test func doseReminderNeverLeavesTheDay() {
        for set in stride(from: 0, to: 1440, by: 15) {
            for shift in stride(from: -720, through: 720, by: 30) {
                let minutes = TravelShift.doseReminderMinutes(setMinutes: set, shiftMinutes: shift)
                #expect((0..<1440).contains(minutes))
                #expect(minutes == set || (7 * 60...22 * 60).contains(minutes))
            }
        }
    }
}
