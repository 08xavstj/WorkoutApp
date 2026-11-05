import Foundation
import AppCore

/// Nightly breathing disturbances (`appleSleepingBreathingDisturbances`, iOS
/// 18): the continuous series behind Apple's sleep-apnoea notification, shown
/// beside blood oxygen and the apnoea flags, and fed to the illness watch as a
/// rising 7-night trend (docs/research/watch-features.md 1.2).
extension VitalsModel {
    /// The stat for Health › Breathing. Apple doesn't publish the unit's
    /// meaning beyond "breathing disturbances", so the value is shown as a
    /// score against your own usual, not a clinical count.
    static func breathingDisturbancesStat(series: [DatedValue], today: Date) -> Stat {
        var stat = Stat(id: "breathingDisturbances", category: .breathing, title: "Nightly breathing disturbances",
                        icon: "waveform.path.ecg", unit: "", series: series)
        stat.chart = .bars
        stat.digits = 1
        stat.defaultDays = 30
        stat.about = "Apple Watch's nightly breathing-disturbance score (Series 9+/Ultra 2), the measure behind its sleep-apnoea notification. The notification catches about two thirds of moderate-to-severe cases, so a quiet month isn't an all-clear. What matters here is change: a week well above your usual counts as one sign in the illness watch, never an alert on its own, and it also shows up when sleeping on your back, after alcohol or with a cold."
        guard let last = series.last else {
            stat.footnote = "Needs an Apple Watch Series 9+/Ultra 2 with sleep tracking on."
            return stat
        }
        let values = series.map(\.value)
        let baseline = values.dropLast(IllnessWatch.breathingDisturbanceRecentNights).suffix(30)
        stat.value = last.value.formatted(.number.precision(.fractionLength(1)))
        if baseline.count >= IllnessWatch.breathingDisturbanceBaselineNights {
            let mean = baseline.reduce(0, +) / Double(baseline.count)
            let rising = IllnessWatch.breathingDisturbancesRising(nightly: values)
            stat.status = rising ? "Up on your usual this week" : "Around your usual"
            stat.tone = rising ? .caution : .good
            stat.gauge = mean > 0 ? min(1, last.value / (2 * mean)) : nil
            stat.footnote = rising
                ? "The last 7 nights average well above your 30-night usual. One sign for the illness watch; also common with a cold, alcohol or back sleeping."
                : "Compared with your own 30-night usual (\(mean.formatted(.number.precision(.fractionLength(1))))). Apple's notification catches about two thirds of cases."
        } else {
            stat.status = "Building your baseline"
            stat.footnote = "Needs about two weeks of nights before changes can be judged against your usual."
        }
        return stat
    }
}
