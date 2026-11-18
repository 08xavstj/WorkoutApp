import Foundation
import Testing
@testable import AppCore

struct OneDeviceBaselineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var today: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 18))! }

    func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

    /// One value a night for the given day offsets (0 is today, -1 yesterday).
    func nights(_ offsets: some Sequence<Int>, value: Double) -> [Date: Double] {
        Dictionary(uniqueKeysWithValues: offsets.map { (day($0), value) })
    }

    @Test func theRingCarriesTheBaselineWhenItHasTheNight() {
        let choice = OneDeviceBaseline.choose(ring: nights(-29...0, value: 60), watch: nights(-29...0, value: 40),
                                              latest: today, calendar: calendar)
        #expect(choice.device == .ring)
        #expect(choice.isEstablished)
        // Only the ring's nights: never a watch night mixed in.
        #expect(Set(choice.nights.values) == [60])
        #expect(choice.nights.count == 30)
    }

    @Test func aNightWithoutTheRingUsesTheWatchsOwnBaseline() {
        // The ring was off last night (or Oura hasn't synced yet): today is scored
        // against the watch's own nights, not the ring's history.
        let choice = OneDeviceBaseline.choose(ring: nights(-29 ... -1, value: 60), watch: nights(-29...0, value: 40),
                                              latest: today, calendar: calendar)
        #expect(choice.device == .watch)
        #expect(Set(choice.nights.values) == [40])
        #expect(choice.nights[today] == 40)
    }

    @Test func aRingNightWithoutAnEstablishedWatchStaysOnTheRing() {
        // The watch has too few nights for a baseline of its own: the ring stays, and today has no value.
        let choice = OneDeviceBaseline.choose(ring: nights(-29 ... -1, value: 60), watch: nights(-3...0, value: 40),
                                              latest: today, calendar: calendar)
        #expect(choice.device == .ring)
        #expect(choice.nights[today] == nil)
        #expect(Set(choice.nights.values) == [60])
    }

    @Test func aNewRingWaitsUntilItHasFourteenNights() {
        let watch = nights(-29...0, value: 40)
        let early = OneDeviceBaseline.choose(ring: nights(-12...0, value: 60), watch: watch, latest: today, calendar: calendar)
        #expect(early.device == .watch)
        let ready = OneDeviceBaseline.choose(ring: nights(-13...0, value: 60), watch: watch, latest: today, calendar: calendar)
        #expect(ready.device == .ring)
        #expect(OneDeviceBaseline.minimumNights == 14)
        #expect(OneDeviceBaseline.windowNights == 30)
    }

    @Test func withNeitherEstablishedTheLongerRecordWins() {
        let ringMore = OneDeviceBaseline.choose(ring: nights(-5...0, value: 60), watch: nights(-3...0, value: 40),
                                                latest: today, calendar: calendar)
        #expect(ringMore.device == .ring)
        #expect(!ringMore.isEstablished)
        let watchMore = OneDeviceBaseline.choose(ring: nights(-2...0, value: 60), watch: nights(-6...0, value: 40),
                                                 latest: today, calendar: calendar)
        #expect(watchMore.device == .watch)
        let tie = OneDeviceBaseline.choose(ring: nights(-3...0, value: 60), watch: nights(-3...0, value: 40),
                                           latest: today, calendar: calendar)
        #expect(tie.device == .ring)
    }

    @Test func onlyOneDeviceOrNone() {
        let watchOnly = OneDeviceBaseline.choose(ring: [:], watch: nights(-2...0, value: 40), latest: today, calendar: calendar)
        #expect(watchOnly.device == .watch)
        #expect(watchOnly.nights.count == 3)
        let ringOnly = OneDeviceBaseline.choose(ring: nights(-2...0, value: 60), watch: [:], latest: today, calendar: calendar)
        #expect(ringOnly.device == .ring)
        let none = OneDeviceBaseline.choose(ring: [:], watch: [:], latest: today, calendar: calendar)
        #expect(none == OneDeviceBaseline.Choice(device: nil, nights: [:], isEstablished: false))
    }

    @Test func oldNightsOutsideTheWindowDontEstablishADevice() {
        // The ring has 20 nights, but all more than 30 days ago.
        let choice = OneDeviceBaseline.choose(ring: nights(-60 ... -41, value: 60), watch: nights(-14...0, value: 40),
                                              latest: today, calendar: calendar)
        #expect(choice.device == .watch)
        #expect(choice.isEstablished)
    }

    @Test func futureZeroAndOddValuesAreDropped() {
        var ring = nights(-14...0, value: 60)
        ring[day(1)] = 70 // tomorrow: not yet
        ring[day(-15)] = 0
        ring[day(-16)] = .nan
        let choice = OneDeviceBaseline.choose(ring: ring, watch: [:], latest: today, calendar: calendar)
        #expect(choice.nights[day(1)] == nil)
        #expect(choice.nights[day(-15)] == nil)
        #expect(choice.nights[day(-16)] == nil)
        #expect(choice.nights.count == 15)
    }

    @Test func valuesAreKeyedByTheMorning() {
        let lateEvening = today.addingTimeInterval(9 * 3600) // a reading keyed at its clock time
        let choice = OneDeviceBaseline.choose(ring: [lateEvening: 61], watch: [:], latest: today, calendar: calendar)
        #expect(choice.nights == [today: 61])
    }

    // MARK: Breathing rate by device

    @Test func breathingRateIsAveragedPerNightAndDevice() {
        let readings: [(date: Date, value: Double, device: BaselineDevice)] = [
            (today.addingTimeInterval(-2 * 3600), 14, .watch), // 10 pm: filed under this morning
            (today.addingTimeInterval(3 * 3600), 16, .watch),
            (today.addingTimeInterval(4 * 3600), 13.5, .ring), // Oura's one nightly value
            (day(-1).addingTimeInterval(3 * 3600), 15, .watch),
            (today.addingTimeInterval(3 * 3600), 0, .watch), // ignored
        ]
        let means = OneDeviceBaseline.nightlyMeans(readings, calendar: calendar)
        #expect(means.watch == [today: 15, day(-1): 15])
        // Never the 14.5 a device-blind average of ring and watch would give.
        #expect(means.ring == [today: 13.5])
    }

    // MARK: Sleeping heart rate from the watch

    @Test func watchSleepingHeartRateSkipsOurasMinutes() {
        let start = today.addingTimeInterval(-7 * 3600)
        func minutes(_ bpm: Double, count: Int = 120) -> [HeartRateSample] {
            (0..<count).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) }
        }
        let sources = [
            HeartRateMerge.Source(name: "Oura Ring (Oura)", samples: minutes(50)),
            HeartRateMerge.Source(name: "Alex's Apple Watch (Health)", samples: minutes(56)),
        ]
        let value = OneDeviceBaseline.watchSleepingHeartRate(sources, from: start, to: today)
        #expect(value == 56)
    }

    @Test func watchSleepingHeartRateUsesOneSourceWithEnoughMinutes() {
        let start = today.addingTimeInterval(-7 * 3600)
        func minutes(_ bpm: Double, count: Int) -> [HeartRateSample] {
            (0..<count).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 60), bpm: bpm) }
        }
        // Two non-ring sources aren't averaged: the one with the most minutes is used.
        let two = [HeartRateMerge.Source(name: "Apple Watch", samples: minutes(56, count: 300)),
                   HeartRateMerge.Source(name: "iPhone", samples: minutes(70, count: 80))]
        #expect(OneDeviceBaseline.watchSleepingHeartRate(two, from: start, to: today) == 56)
        // Under 60 minutes: no value.
        let short = [HeartRateMerge.Source(name: "Apple Watch", samples: minutes(56, count: 59))]
        #expect(OneDeviceBaseline.watchSleepingHeartRate(short, from: start, to: today) == nil)
        // Minutes outside the sleep don't count.
        #expect(OneDeviceBaseline.watchSleepingHeartRate(two, from: today, to: today.addingTimeInterval(3600)) == nil)
    }

    // MARK: SDNN out when the ring carries the HRV baseline

    @Test func removingHRVKeepsRestingHeartRate() {
        let vitals = [DailyVitals(date: today, hrvMilliseconds: 45, restingHeartRate: 52)]
        #expect(DailyVitals.removingHRV(vitals) == [DailyVitals(date: today, hrvMilliseconds: nil, restingHeartRate: 52)])
    }

    @Test func withSDNNRemovedTheRingsGapsStayEmpty() {
        // The ring has 20 of the last 30 nights; Health's SDNN has all 30.
        let ring = nights(-19...0, value: 60).filter { $0.key != day(-5) }
        let sdnn = (-29...0).map { DailyVitals(date: day($0), hrvMilliseconds: 40, restingHeartRate: 55) }
        let mixed = DailyVitals.resolvingHRV(sdnn, overnightRMSSD: ring, today: today, calendar: calendar)
        // Without removal, the ring's missing night is filled from the watch's SDNN by a ratio.
        #expect(mixed.vitals.first { $0.date == day(-5) }?.hrvMilliseconds != nil)
        let ringOnly = DailyVitals.resolvingHRV(DailyVitals.removingHRV(sdnn), overnightRMSSD: ring, today: today, calendar: calendar)
        #expect(ringOnly.metric == .rmssd)
        #expect(ringOnly.vitals.first { $0.date == day(-5) }?.hrvMilliseconds == nil)
        #expect(ringOnly.vitals.first { $0.date == day(-5) }?.restingHeartRate == 55)
        #expect(Set(ringOnly.vitals.compactMap(\.hrvMilliseconds)) == [60])
    }
}

struct WorkoutOverlapTests {
    struct Workout: Equatable {
        var name: String
        var start: Double
        var end: Double
        var ring: Bool
    }

    func dedupe(_ workouts: [Workout]) -> [String] {
        WorkoutOverlap.removingRingDuplicates(workouts, isRing: \.ring, interval: {
            DateInterval(start: Date(timeIntervalSince1970: $0.start * 60), end: Date(timeIntervalSince1970: $0.end * 60))
        }).map(\.name)
    }

    @Test func aRingWorkoutOverAWatchWorkoutIsDropped() {
        // Oura auto-detected the same run the watch recorded: its calories would count twice.
        let workouts = [Workout(name: "watch run", start: 0, end: 40, ring: false),
                        Workout(name: "oura run", start: 2, end: 45, ring: true)]
        #expect(dedupe(workouts) == ["watch run"])
    }

    @Test func aRingWorkoutOnItsOwnIsKept() {
        let workouts = [Workout(name: "watch run", start: 0, end: 40, ring: false),
                        Workout(name: "oura walk", start: 120, end: 150, ring: true)]
        #expect(dedupe(workouts) == ["watch run", "oura walk"])
        #expect(dedupe([Workout(name: "oura walk", start: 0, end: 30, ring: true)]) == ["oura walk"])
    }

    @Test func aSmallOverlapIsNotADuplicate() {
        // A 10-minute overlap of a 60-minute ring walk and a 40-minute watch run: under half the shorter one.
        let workouts = [Workout(name: "watch run", start: 0, end: 40, ring: false),
                        Workout(name: "oura walk", start: 30, end: 90, ring: true)]
        #expect(dedupe(workouts) == ["watch run", "oura walk"])
        // Touching end to start isn't an overlap.
        let touching = [Workout(name: "watch run", start: 0, end: 40, ring: false),
                        Workout(name: "oura walk", start: 40, end: 70, ring: true)]
        #expect(dedupe(touching) == ["watch run", "oura walk"])
    }

    @Test func aShortWatchRecordingInsideALongRingWorkoutCounts() {
        // Half of the shorter one is enough, whichever device recorded it.
        let workouts = [Workout(name: "oura hike", start: 0, end: 120, ring: true),
                        Workout(name: "watch hike", start: 10, end: 40, ring: false)]
        #expect(dedupe(workouts) == ["watch hike"])
        #expect(WorkoutOverlap.duplicateShare == 0.5)
    }

    @Test func nonRingWorkoutsAreNeverDropped() {
        // Two other apps' overlapping recordings are left to the existing linking rules.
        let workouts = [Workout(name: "watch run", start: 0, end: 40, ring: false),
                        Workout(name: "strava run", start: 0, end: 40, ring: false)]
        #expect(dedupe(workouts) == ["watch run", "strava run"])
    }
}

struct PKCETests {
    @Test func challengeMatchesRFC7636AppendixB() {
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierMatchesRFC7636AppendixBOctets() {
        let octets: [UInt8] = [116, 24, 223, 180, 151, 153, 224, 37, 79, 250, 96, 125, 216, 173, 187, 186,
                               22, 212, 37, 77, 105, 214, 191, 240, 91, 88, 5, 88, 83, 132, 141, 121]
        #expect(PKCE.base64URL(octets) == "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    }

    @Test func sha256MatchesTheStandardVectors() {
        func hex(_ text: String) -> String {
            SHA256.hash(Array(text.utf8)).map { byte in
                let digits = String(byte, radix: 16)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
        }
        #expect(hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        // Longer than one 64-byte block, and a length that pads into a second block.
        #expect(hex(String(repeating: "a", count: 1000)) == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
        #expect(hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    @Test func verifiersAreLongEnoughAndURLSafe() {
        var generator = SeededGenerator(seed: 7)
        let first = PKCE.makeVerifier(using: &generator)
        let second = PKCE.makeVerifier(using: &generator)
        #expect(first.count == 43) // RFC 7636 §4.1: 43-128 characters
        #expect(first != second)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(first.allSatisfy { allowed.contains($0) })
        #expect(PKCE.makeVerifier().count == 43)
    }

    /// SplitMix64, only so the test is repeatable.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
}
