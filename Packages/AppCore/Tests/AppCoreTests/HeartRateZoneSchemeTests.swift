import Foundation
import Testing
@testable import AppCore

struct HeartRateZoneSchemeTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fixed pseudo-random stream, so the "noisy" series are the same every run.
    struct Noise {
        var state: UInt64
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    static let profiles = [
        HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55),
        HeartRateProfile(age: 34, sex: .male, restingHeartRate: 60, maxHeartRateOverride: 180),
        HeartRateProfile(age: 52, sex: .female, restingHeartRate: 48),
        HeartRateProfile(age: 41, sex: .female, restingHeartRate: 71.5, maxHeartRateOverride: 187.3),
        // An override too close to resting is ignored by the profile (Tanaka stands in).
        HeartRateProfile(age: 25, sex: .male, restingHeartRate: 62, maxHeartRateOverride: 70),
    ]

    // MARK: The default is today's behaviour

    @Test(arguments: profiles)
    func tensileSchemeGivesTheProfilesZoneForEveryHeartRate(profile: HeartRateProfile) {
        let scheme = HeartRateZoneScheme.tensile(profile: profile)
        // Every tenth of a beat from 30 to 230, which crosses each limit.
        for step in 0...2000 {
            let bpm = 30 + Double(step) * 0.1
            #expect(scheme.zone(for: bpm) == profile.zone(for: bpm), "bpm \(bpm)")
        }
        // Exactly on each limit, where the profile's arithmetic rounds its own way.
        for fraction in [0.5, 0.6, 0.7, 0.8, 0.9, 1.0] {
            let bpm = profile.heartRate(atReserve: fraction)
            #expect(scheme.zone(for: bpm) == profile.zone(for: bpm), "limit \(fraction)")
        }
    }

    @Test(arguments: profiles)
    func tensileSchemeReproducesStrainsZoneMinutesExactly(profile: HeartRateProfile) {
        var noise = Noise(state: 42)
        var samples: [HeartRateSample] = []
        var time = start
        // A day's worth of mixed readings: 5 s apart in a workout, minutes
        // apart outside one, with a few long gaps, across every zone.
        for index in 0..<4000 {
            let phase = Double(index) / 4000
            let target = profile.heartRate(atReserve: 0.2 + 0.85 * abs(sin(phase * 9)))
            samples.append(HeartRateSample(date: time, bpm: target + (noise.next() - 0.5) * 12))
            let pick = noise.next()
            time += pick < 0.7 ? 5 : pick < 0.93 ? 60 + noise.next() * 240 : pick < 0.98 ? 400 : 900
        }
        // Readings exactly on the limits too.
        for fraction in [0.5, 0.6, 0.7, 0.8, 0.9] {
            samples.append(HeartRateSample(date: time, bpm: profile.heartRate(atReserve: fraction)))
            time += 30
        }
        samples.shuffle()
        let expected = StrainCalculator().dailyStrain(heartRate: samples, strengthSessions: [], profile: profile).zoneMinutes
        let scheme = HeartRateZoneScheme.tensile(profile: profile)
        #expect(scheme.minutes(samples) == expected)
        #expect(expected.reduce(0, +) > 60)
        // And through `resolve`, which is what the app calls.
        let resolved = HeartRateZoneScheme.resolve(kind: .reserve, profile: profile)
        #expect(!resolved.fellBack)
        #expect(resolved.scheme.minutes(samples) == expected)
    }

    @Test func gapHandlingIsTheSameAsStrains() {
        let calculator = StrainCalculator()
        #expect(HeartRateZoneScheme.maxSampleGap == calculator.maxSampleGap)
        #expect(HeartRateZoneScheme.maxMinutesPerSample == calculator.maxMinutesPerSample)
    }

    @Test func ageFormulaIsTheProfiles() {
        for age in [18, 30, 45, 70] {
            let profile = HeartRateProfile(age: age, sex: .male, restingHeartRate: 60)
            #expect(HeartRateZoneScheme.estimatedMaximum(age: age) == profile.maxHeartRate)
        }
    }

    // MARK: Limits

    @Test func reserveLimitsInBeats() {
        // Resting 60, maximum 180: reserve 120, so zones start at 120, 132, 144, 156, 168.
        let scheme = HeartRateZoneScheme.reserve(resting: 60, maximum: 180)
        #expect(scheme.floor == 120)
        #expect(scheme.boundaries.map { $0.rounded() } == [132, 144, 156, 168])
        #expect(scheme.rangeText(forZone: 1) == "120–132")
        #expect(scheme.rangeText(forZone: 5) == "168+")
        #expect(scheme.zone(for: 119) == nil)
        #expect(scheme.zone(for: 150) == 3)
        #expect(scheme.zone(for: 240) == 5)
    }

    /// Every whole-beat heart rate gets the same zone from the badge
    /// (`zone(for:)`) as from the ranges shown (`band(forZone:)`): on a limit
    /// it belongs to the zone that starts there. 289 mismatches before the fix.
    @Test func zoneAndBandAgreeOnEveryWholeBeat() {
        var mismatches = 0
        for resting in stride(from: 45.0, through: 75, by: 1) {
            for maximum in stride(from: 170.0, through: 200, by: 1) {
                let scheme = HeartRateZoneScheme.reserve(resting: resting, maximum: maximum)
                for bpm in stride(from: 80.0, through: 210, by: 1) {
                    guard let zone = scheme.zone(for: bpm) else { continue }
                    guard let band = scheme.band(forZone: zone), bpm >= band.lower - 1e-6, bpm < band.upper else {
                        mismatches += 1
                        continue
                    }
                }
            }
        }
        #expect(mismatches == 0)
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55, maxHeartRateOverride: 185)
        #expect(profile.zone(for: 133) == 2)
        #expect(HeartRateZoneScheme.reserve(resting: 55, maximum: 185).zone(for: 133) == 2)
    }

    @Test func percentOfMaxLimitsAndTheirEdges() {
        let scheme = HeartRateZoneScheme.percentOfMax(maximum: 190, resting: 55)
        #expect(scheme.kind == .percentOfMax)
        #expect(scheme.floor == 95)
        // Typed out: the literal-array comparison was too slow for the macOS type checker.
        let expected: [Double] = [114, 133, 152, 171]
        #expect(zip(scheme.boundaries, expected).allSatisfy { abs($0 - $1) < 1e-9 })
        #expect(scheme.boundaries.count == 4)
        #expect(scheme.zone(for: 94.9) == nil)
        // A heart rate exactly on a limit is in the zone that starts there.
        #expect(scheme.zone(for: 95) == 1)
        #expect(scheme.zone(for: 0.6 * 190) == 2)
        #expect(scheme.zone(for: 0.6 * 190 - 0.01) == 1)
        #expect(scheme.zone(for: 0.7 * 190) == 3)
        #expect(scheme.zone(for: 0.8 * 190) == 4)
        #expect(scheme.zone(for: 0.9 * 190) == 5)
        #expect(scheme.zone(for: 0.9 * 190 - 0.01) == 4)
        #expect(scheme.zone(for: 230) == 5)
    }

    @Test func sameHeartRateIsADifferentZoneInEachScheme() {
        // Resting 55, maximum 185. 125 bpm is 54% of reserve and 68% of maximum.
        let reserve = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)
        let ofMax = HeartRateZoneScheme.percentOfMax(maximum: 185, resting: 55)
        #expect(reserve.zone(for: 125) == 1)
        #expect(ofMax.zone(for: 125) == 2)
        // Percent-of-max zone 2 (111–130) sits under the reserve scheme's zone 2 (133–146).
        #expect(ofMax.boundaries[1] < reserve.boundaries[0])
    }

    @Test func appleHealthZoneOneHasNoFloor() throws {
        let easy = HeartRateBand(lower: 107, upper: 133)
        let scheme = try #require(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [137, 149, 160, 172], easyBand: easy))
        #expect(scheme.zone(for: 40) == 1)
        #expect(scheme.zone(for: 136.9) == 1)
        #expect(scheme.zone(for: 137) == 2)
        #expect(scheme.zone(for: 172) == 5)
        #expect(scheme.rangeText(forZone: 1) == "under 137")
        #expect(scheme.rangeText(forZone: 3) == "149–160")
        // A lower limit from Health is kept when it makes sense, dropped when it doesn't.
        #expect(HeartRateZoneScheme.appleHealth(floor: 110, boundaries: [137, 149, 160, 172], easyBand: easy)?.floor == 110)
        #expect(HeartRateZoneScheme.appleHealth(floor: 140, boundaries: [137, 149, 160, 172], easyBand: easy)?.floor == nil)
        // Anything other than five zones isn't drawn.
        #expect(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [137, 149, 160], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.appleHealth(floor: nil, boundaries: [137, 149, 160, 172, 180], easyBand: easy) == nil)
    }

    @Test func customLimitsAreChecked() {
        let easy = HeartRateBand(lower: 107, upper: 133)
        let scheme = HeartRateZoneScheme.custom(starts: [110, 128, 142, 155, 168], easyBand: easy)
        #expect(scheme?.floor == 110)
        #expect(scheme?.boundaries == [128, 142, 155, 168])
        #expect(scheme?.zone(for: 109) == nil)
        #expect(scheme?.zone(for: 141.5) == 2)
        // Not rising, too few, or out of range: no scheme.
        #expect(HeartRateZoneScheme.custom(starts: [110, 128, 128, 155, 168], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.custom(starts: [110, 128, 120, 155, 168], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.custom(starts: [110, 128, 142, 155], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.custom(starts: [20, 128, 142, 155, 168], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.custom(starts: [110, 128, 142, 155, 300], easyBand: easy) == nil)
        #expect(HeartRateZoneScheme.custom(starts: [110, 128, 142, 155, .nan], easyBand: easy) == nil)
    }

    // MARK: Resolving the chosen scheme

    @Test func resolveFallsBackToTensileWhenAScheneCantBeBuilt() {
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
        let tensile = HeartRateZoneScheme.tensile(profile: profile)
        // Apple Health chosen, nothing from Health (iOS 26, or no zones yet).
        let noHealth = HeartRateZoneScheme.resolve(kind: .appleHealth, profile: profile)
        #expect(noHealth.fellBack)
        #expect(noHealth.requested == .appleHealth)
        #expect(noHealth.scheme == tensile)
        // Health has zones: they are used, with the profile's easy band.
        let health = HeartRateZoneScheme.resolve(kind: .appleHealth, profile: profile, appleBoundaries: [137, 149, 160, 172])
        #expect(!health.fellBack)
        #expect(health.scheme.boundaries == [137, 149, 160, 172])
        #expect(health.scheme.easyBand == tensile.easyBand)
        // Custom with nothing typed, or nonsense typed.
        #expect(HeartRateZoneScheme.resolve(kind: .custom, profile: profile).fellBack)
        #expect(HeartRateZoneScheme.resolve(kind: .custom, profile: profile, customStarts: [150, 140, 130, 120, 110]).fellBack)
        let custom = HeartRateZoneScheme.resolve(kind: .custom, profile: profile, customStarts: [110, 128, 142, 155, 168])
        #expect(!custom.fellBack)
        #expect(custom.scheme.kind == .custom)
        let ofMax = HeartRateZoneScheme.resolve(kind: .percentOfMax, profile: profile)
        #expect(ofMax.scheme.floor == 0.5 * profile.maxHeartRate)
        #expect(ofMax.scheme.easyBand == tensile.easyBand)
    }

    // MARK: Easy band

    @Test func easyBandIsModerateEffortOnReserve() {
        // Resting 55, maximum 185: 40% and 60% of the 130-beat reserve.
        let band = HeartRateZoneScheme.easyBand(resting: 55, maximum: 185)
        #expect(band.lower == 55 + 0.4 * 130)
        #expect(band.upper == 55 + 0.6 * 130)
        #expect(band.text == "107–133")
        #expect(band.contains(107))
        #expect(band.contains(132.9))
        #expect(!band.contains(133))
        #expect(band.side(of: 100) == .below)
        #expect(band.side(of: 120) == .inside)
        #expect(band.side(of: 133) == .above)
        // The easy band ends where Tensile's zone 2 starts: on a reserve scale
        // "easy" is zone 1 and just under it, not zone 2.
        let tensile = HeartRateZoneScheme.reserve(resting: 55, maximum: 185)
        #expect(band.upper == tensile.boundaries[0])
        // With no resting heart rate (the Watch alone): 64–77% of maximum.
        let alone = HeartRateZoneScheme.ageEstimate(age: 34)
        let maximum = HeartRateZoneScheme.estimatedMaximum(age: 34)
        #expect(alone.easyBand == HeartRateBand(lower: 0.64 * maximum, upper: 0.77 * maximum))
        #expect(alone.kind == .percentOfMax)
    }

    @Test func zoneBandsCoverTheScaleWithoutGaps() {
        let scheme = HeartRateZoneScheme.percentOfMax(maximum: 190)
        for zone in 1...4 {
            #expect(scheme.band(forZone: zone)?.upper == scheme.band(forZone: zone + 1)?.lower)
        }
        #expect(scheme.band(forZone: 5)?.upper == HeartRateBand.noUpperLimit)
        #expect(scheme.band(forZone: 0) == nil)
        #expect(scheme.band(forZone: 6) == nil)
        // A band and the zone lookup agree.
        for bpm in stride(from: 90.0, through: 200, by: 0.5) {
            guard let zone = scheme.zone(for: bpm) else { continue }
            #expect(scheme.band(forZone: zone)?.contains(bpm) == true)
        }
    }

    // MARK: Minutes

    @Test func minutesInZonesFromASteadyRun() {
        let scheme = HeartRateZoneScheme.percentOfMax(maximum: 190)
        // 30 minutes at 140 bpm (74% of maximum: zone 3), a reading every 5 s.
        let samples = (0...360).map { HeartRateSample(date: start.addingTimeInterval(Double($0) * 5), bpm: 140) }
        let minutes = scheme.minutes(samples)
        #expect(minutes.count == 5)
        #expect(abs(minutes[2] - 30) < 0.001)
        #expect(minutes.reduce(0, +) == minutes[2])
    }

    @Test func minutesCapLongGapsAndSkipDropouts() {
        let scheme = HeartRateZoneScheme.percentOfMax(maximum: 190)
        let samples = [
            HeartRateSample(date: start, bpm: 160),                            // stands for 60 s
            HeartRateSample(date: start.addingTimeInterval(60), bpm: 160),     // 5 min to the next: capped at 2 min
            HeartRateSample(date: start.addingTimeInterval(360), bpm: 160),    // 11 min to the next: not counted
            HeartRateSample(date: start.addingTimeInterval(1020), bpm: 100),   // zone 1 for 30 s
            HeartRateSample(date: start.addingTimeInterval(1050), bpm: 80),    // below zone 1; last reading counts for nothing
        ]
        let minutes = scheme.minutes(samples)
        #expect(minutes[3] == 3)
        #expect(minutes[0] == 0.5)
        #expect(minutes.reduce(0, +) == 3.5)
        #expect(scheme.minutes([]) == [0, 0, 0, 0, 0])
        #expect(scheme.minutes([samples[0]]) == [0, 0, 0, 0, 0])
    }

    // MARK: Storage

    @Test func schemesSurviveEncoding() throws {
        let profile = HeartRateProfile(age: 30, sex: .male, restingHeartRate: 55)
        let schemes = [
            HeartRateZoneScheme.tensile(profile: profile),
            HeartRateZoneScheme.percentOfMax(maximum: 187, resting: 55),
            HeartRateZoneScheme.resolve(kind: .appleHealth, profile: profile, appleBoundaries: [137, 149, 160, 172]).scheme,
            HeartRateZoneScheme.resolve(kind: .custom, profile: profile, customStarts: [110, 128, 142, 155, 168]).scheme,
        ]
        for scheme in schemes {
            let data = try JSONEncoder().encode(scheme)
            let decoded = try JSONDecoder().decode(HeartRateZoneScheme.self, from: data)
            #expect(decoded == scheme)
            // The decoded reserve scheme still agrees with the profile at a limit.
            #expect(decoded.zone(for: profile.heartRate(atReserve: 0.6)) == scheme.zone(for: profile.heartRate(atReserve: 0.6)))
        }
    }

    @Test func everyKindHasCopy() {
        for kind in HeartRateZoneScheme.Kind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(kind.explanation.hasSuffix("."))
        }
    }
}
