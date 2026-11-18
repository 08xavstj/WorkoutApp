import Foundation
import AppCore

/// Walking speed (`walkingSpeed`, iPhone): a tracked stat with a 90-day
/// trend, graded only from 60 (`WalkingSpeed`; docs/research/next-features-2026-11.md,
/// §4a row 7, §5 item 10). Apple's heart events are read in the same refresh
/// (`heartEvents`) and shown as one line on the Heart page.
extension VitalsModel {
    static func walkingSpeedStat(series: [DatedValue], age: Int, miles: Bool, now: Date) -> Stat {
        let daily = series.map { DayValue(date: $0.date, value: $0.value) }
        let average = WalkingSpeed.recentAverage(daily, now: now)
        let trend = WalkingSpeed.trend(daily, now: now)
        let unit = miles ? "mph" : "km/h"
        var stat = Stat(
            id: "walkingSpeed", category: .activity, title: "Walking speed", icon: "figure.walk.motion",
            value: average.map { WalkingSpeed.display($0, miles: miles).formatted(.number.precision(.fractionLength(1))) },
            unit: unit,
            status: WalkingSpeed.status(average: average, trend: trend, age: age, miles: miles),
            tone: .neutral,
            series: series.map { DatedValue(date: $0.date, value: WalkingSpeed.display($0.value, miles: miles)) }
        )
        if let average, let grade = WalkingSpeed.grade(metersPerSecond: average, age: age) {
            stat.tone = grade == .slower ? .caution : .good
        }
        stat.digits = 1
        stat.defaultDays = 90
        stat.footnote = average == nil ? "Measured by your iPhone while you walk with it in a pocket." : "7-day average of your iPhone's everyday walking speed."
        let slow = WalkingSpeed.display(WalkingSpeed.slowBelow, miles: miles).formatted(.number.precision(.fractionLength(1)))
        let brisk = WalkingSpeed.display(WalkingSpeed.brisk, miles: miles).formatted(.number.precision(.fractionLength(1)))
        stat.about = "Your usual walking pace, measured by your iPhone as you walk. Faster walkers live longer: each 0.1 m/s (about 0.4 km/h) faster went with 6% lower risk of death across 13 cohorts (Liu et al. 2024), but these are observational studies, mostly in older adults. Under \(WalkingSpeed.gradedFromAge) almost everyone is near the top, so the app only tracks the trend; from \(WalkingSpeed.gradedFromAge) it compares you with the lines from Studenski et al. (JAMA 2011): under \(slow) \(unit) slower, \(brisk) \(unit) or more brisk. Those came from short walking tests in a clinic, so the iPhone's everyday number is a guide, not the same test."
        return stat
    }
}
