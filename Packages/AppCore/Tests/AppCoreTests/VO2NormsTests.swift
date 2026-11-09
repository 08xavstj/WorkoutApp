import Testing
@testable import AppCore

struct VO2NormsTests {
    /// FRIEND 2015 Table 3 values, copied in the test as a second check on the
    /// constants.
    @Test func tableMatchesFriend2015() {
        #expect(VO2Norms.cutPoints(age: 25, sex: .male) == [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3])
        #expect(VO2Norms.cutPoints(age: 35, sex: .male) == [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8])
        #expect(VO2Norms.cutPoints(age: 75, sex: .female) == [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1])
        #expect(VO2Norms.cutPoints(age: 45, sex: .female) == [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7])
    }

    @Test func everyRowRisesAndEveryColumnFallsWithAge() {
        for sex in BiologicalSex.allCases {
            let rows = VO2Norms.friendTreadmill[sex] ?? []
            #expect(rows.count == 6)
            for row in rows {
                #expect(row.count == VO2Norms.percentiles.count)
                #expect(zip(row, row.dropFirst()).allSatisfy { $0 < $1 })
            }
            for column in VO2Norms.percentiles.indices {
                let values = rows.map { $0[column] }
                #expect(zip(values, values.dropFirst()).allSatisfy { $0 > $1 }, "\(sex) \(column)")
            }
        }
    }

    /// One table: the medians, the fitness age and the percentiles agree.
    @Test func medianIsTheBiomarkerMedianAtEveryAge() {
        for sex in BiologicalSex.allCases {
            for age in 15...95 {
                #expect(abs(VO2Norms.median(age: age, sex: sex) - Biomarkers.medianVO2Max(age: age, sex: sex)) < 1e-9)
                let median = VO2Norms.median(age: age, sex: sex)
                #expect(abs(VO2Norms.percentile(vo2: median, age: age, sex: sex) - 50) < 1e-9)
            }
        }
    }

    @Test func interpolatesBetweenDecadesLikeTheMedian() {
        // 34-year-old man: 90% of the way from the 20s row to the 30s row.
        let cuts = VO2Norms.cutPoints(age: 34, sex: .male)
        #expect(abs(cuts[3] - (48.0 + (42.4 - 48.0) * 0.9)) < 1e-9)
        #expect(abs(cuts[5] - (61.8 + (56.5 - 61.8) * 0.9)) < 1e-9)
        // Flat outside 25-75.
        #expect(VO2Norms.cutPoints(age: 18, sex: .female) == VO2Norms.cutPoints(age: 25, sex: .female))
        #expect(VO2Norms.cutPoints(age: 90, sex: .male) == VO2Norms.cutPoints(age: 75, sex: .male))
    }

    @Test func percentileIsInterpolatedBetweenCutPoints() {
        // Man 35: 25th = 35.9, 50th = 42.4; halfway → 37.5th.
        #expect(abs(VO2Norms.percentile(vo2: (35.9 + 42.4) / 2, age: 35, sex: .male) - 37.5) < 1e-9)
        #expect(VO2Norms.percentile(vo2: 56.5, age: 35, sex: .male) == 90)
        #expect(VO2Norms.percentile(vo2: 10, age: 35, sex: .male) == 5)
        #expect(VO2Norms.percentile(vo2: 80, age: 35, sex: .male) == 95)
        // Never falls as VO₂ max rises.
        var last = 0.0
        for tenth in 100...800 {
            let value = VO2Norms.percentile(vo2: Double(tenth) / 10, age: 41, sex: .female)
            #expect(value >= last)
            last = value
        }
    }

    @Test func categoriesSitAtTheTableCutPoints() {
        // Man 35: 10th 30.2, 25th 35.9, 50th 42.4, 75th 49.2, 90th 56.5.
        func category(_ vo2: Double) -> VO2Norms.Category { VO2Norms.category(vo2: vo2, age: 35, sex: .male) }
        #expect(category(30.1) == .low)
        #expect(category(30.2) == .belowAverage)
        #expect(category(35.9) == .average)
        #expect(category(42.3) == .average)
        #expect(category(42.4) == .good)
        #expect(category(49.2) == .excellent)
        #expect(category(56.5) == .topTen)
        #expect(category(45).name == "Good")
        #expect(VO2Norms.Category.belowAverage.isBelowAverage)
        #expect(!VO2Norms.Category.average.isBelowAverage)
        #expect(Biomarkers.vo2MaxLabel(45, age: 35, sex: .male) == "Good")
    }

    @Test func categoryAgreesWithPercentile() {
        for sex in BiologicalSex.allCases {
            for age in [20, 34, 47, 63, 80] {
                for tenth in 120...750 {
                    let vo2 = Double(tenth) / 10
                    let category = VO2Norms.category(vo2: vo2, age: age, sex: sex)
                    let percentile = VO2Norms.percentile(vo2: vo2, age: age, sex: sex)
                    #expect(percentile >= category.lowerPercentile - 1e-9 || category == .low, "\(sex) \(age) \(vo2)")
                    if let next = VO2Norms.Category(rawValue: category.rawValue + 1) {
                        #expect(percentile < next.lowerPercentile + 1e-9, "\(sex) \(age) \(vo2)")
                    }
                }
            }
        }
    }

    /// The user's example: a 34-year-old man reading 45.
    @Test func standingInWords() {
        let standing = VO2Norms.standing(vo2: 45, age: 34, sex: .male)
        #expect(standing.category == .good)
        // 50th 42.96, 75th 49.8 → about the 57.5th, rounded to 5 → "55th".
        #expect(abs(standing.percentile - 57.46) < 0.01)
        #expect(standing.percentileText == "About the 55th percentile for men your age")
        #expect(VO2Norms.standing(vo2: 12, age: 34, sex: .female).percentileText == "Below the 5th percentile for women your age")
        #expect(VO2Norms.standing(vo2: 70, age: 34, sex: .male).percentileText == "Above the 95th percentile for men your age")
        #expect(VO2Norms.ordinal(1) == "1st")
        #expect(VO2Norms.ordinal(12) == "12th")
        #expect(VO2Norms.ordinal(22) == "22nd")
        #expect(VO2Norms.ordinal(93) == "93rd")
    }

    @Test func averageAdultIsThePooledFriendMean() {
        // (4611 × 37.9 + 3172 × 27.6) / 7783, FRIEND 2015 Table 2.
        #expect(abs(VO2Norms.averageAdult - 33.70) < 0.01)
    }

    @Test func referencesForAThirtyFourYearOldMan() throws {
        let refs = VO2Norms.references(age: 34, sex: .male)
        #expect(refs.map(\.kind) == [.sameSex, .otherSex, .adult, .topTen])
        #expect(abs(refs[0].value - Biomarkers.medianVO2Max(age: 34, sex: .male)) < 1e-9)
        #expect(abs(refs[1].value - Biomarkers.medianVO2Max(age: 34, sex: .female)) < 1e-9)
        #expect(refs[0].shortLabel == "Avg man")
        #expect(refs[1].shortLabel == "Avg woman")
        #expect(abs(refs[3].value - (61.8 + (56.5 - 61.8) * 0.9)) < 1e-9)
    }

    @Test func scaleCoversTheTableAndYourValues() {
        let scale = VO2Norms.scale(age: 34, sex: .male)
        let cuts = VO2Norms.cutPoints(age: 34, sex: .male)
        #expect(scale.lowerBound <= cuts[0] && scale.upperBound >= cuts[6])
        #expect(scale.lowerBound.truncatingRemainder(dividingBy: 5) == 0)
        #expect(scale.upperBound.truncatingRemainder(dividingBy: 5) == 0)
        let wide = VO2Norms.scale(age: 34, sex: .male, including: [75, 18])
        #expect(wide.upperBound >= 77 && wide.lowerBound <= 16)
    }

    @Test func segmentsTileTheScale() {
        for sex in BiologicalSex.allCases {
            let scale = VO2Norms.scale(age: 34, sex: sex)
            let segments = VO2Norms.segments(age: 34, sex: sex, scale: scale)
            #expect(segments.map(\.category) == VO2Norms.Category.allCases)
            #expect(segments.first?.range.lowerBound == scale.lowerBound)
            #expect(segments.last?.range.upperBound == scale.upperBound)
            for (a, b) in zip(segments, segments.dropFirst()) {
                #expect(a.range.upperBound == b.range.lowerBound)
            }
        }
    }

    @Test func tipsFitLevelAndGoals() {
        let low = VO2Norms.tips(category: .belowAverage, lifts: true, losingWeight: false)
        #expect(low.count == 3)
        #expect(low[0].text.contains("easy"))
        #expect(low.contains { $0.evidence.contains("Schumann") })
        let high = VO2Norms.tips(category: .excellent, lifts: false, losingWeight: true)
        #expect(high[0].text.contains("4 × 4"))
        #expect(high.contains { $0.text.contains("per kilogram") })
        #expect(!high.contains { $0.evidence.contains("Schumann") })
        let all = VO2Norms.tips(category: .topTen, lifts: true, losingWeight: true)
        #expect(all.count == 4)
        #expect(all[1].text.contains("top 10%"))
        for category in VO2Norms.Category.allCases {
            for tip in VO2Norms.tips(category: category, lifts: true, losingWeight: true) {
                #expect(!tip.evidence.isEmpty)
            }
        }
    }

    @Test func assessCarriesTheCategory() throws {
        let points = [DayValue(date: .now, value: 45)]
        let result = try #require(CardioFitness.assess(points, age: 34, sex: .male))
        #expect(result.category == .good)
        #expect(result.label == "Good")
    }
}
