import Foundation
import Observation
import AppCore

/// Apple's own Readiness, Sleep score and Health Age, as the owner brought
/// them in (from a screenshot, typed, or from a Shortcut), with Tensile's own
/// number for the same day beside each (`AppleScoreLog` in AppCore).
///
/// Apple gives apps no way to read these (docs/research/apple-scores-2026-11.md),
/// so this is the only place they live. A JSON file in Application Support
/// (`SafeJSONFile`), like `SleepScoreLog`; no SwiftData model.
///
/// One shared instance, because the Shortcuts action (`LogAppleScoresIntent`)
/// writes to it from outside any view.
@Observable
final class AppleScoresStore {
    static let shared = AppleScoresStore()

    private(set) var log = AppleScoreLog()

    @ObservationIgnored private let file = SafeJSONFile.appSupport("apple-scores.json")
    /// False after a read that failed (phone locked): nothing is saved until a read works.
    @ObservationIgnored private var canSave = false
    /// Demo mode shows made-up numbers and never touches the file.
    @ObservationIgnored private let demo = DemoHealth.active

    private init() {
        if let demo {
            log = demo.appleScores()
            mirrorHealthAge()
        } else {
            reload()
        }
    }

    // MARK: File

    /// Reads again if the last read couldn't (a launch while the phone was locked).
    func reloadIfUnavailable() {
        if demo == nil, !canSave { reload() }
    }

    private func reload() {
        let loaded = file.loadLogged(AppleScoreLog.self)
        canSave = loaded.state.canSave
        guard canSave else { return }
        log = loaded.value ?? AppleScoreLog()
        migrateTypedHealthAge()
    }

    private func write() {
        mirrorHealthAge()
        guard demo == nil else { return }
        file.saveLogged(log, canSave: canSave)
    }

    /// Whether a change can be kept (always in demo mode, where it stays in memory).
    private func canChange() -> Bool {
        reloadIfUnavailable()
        return demo != nil || canSave
    }

    // MARK: The first version's Health Age

    /// The first version kept one typed Health Age in UserDefaults
    /// (`AppleHealthAge`). It moves into the log once, on the day it was typed.
    private func migrateTypedHealthAge() {
        guard log.latest(.healthAge) == nil, let typed = AppleHealthAge.saved else { return }
        // No date was saved by the very first build: count it as typed today.
        let typedAt = typed.date.timeIntervalSince1970 > 0 ? typed.date : Date.now
        if log.record(.healthAge, value: typed.years, day: AppleScoreLog.key(for: typedAt), at: typedAt, source: .migrated) {
            file.saveLogged(log, canSave: canSave)
        }
    }

    /// The latest Health Age stays in UserDefaults too, where Health › Key
    /// measures reads it (`@AppStorage(AppleHealthAge.valueKey)`).
    private func mirrorHealthAge() {
        let defaults = UserDefaults.standard
        if let latest = log.latest(.healthAge) {
            if defaults.integer(forKey: AppleHealthAge.valueKey) != latest.reading.value {
                defaults.set(latest.reading.value, forKey: AppleHealthAge.valueKey)
            }
            let typedAt = latest.reading.recordedAt.timeIntervalSince1970
            if defaults.double(forKey: AppleHealthAge.dateKey) != typedAt {
                defaults.set(typedAt, forKey: AppleHealthAge.dateKey)
            }
        } else if defaults.object(forKey: AppleHealthAge.valueKey) != nil {
            defaults.removeObject(forKey: AppleHealthAge.valueKey)
            defaults.removeObject(forKey: AppleHealthAge.dateKey)
        }
    }

    // MARK: Days

    /// Now, or demo mode's fixed morning.
    var now: Date { demo?.now ?? .now }

    var todayKey: String { AppleScoreLog.key(for: now) }

    static func key(_ day: Date) -> String { AppleScoreLog.key(for: day) }

    // MARK: Reading

    func reading(_ kind: AppleScoreKind, on day: Date) -> AppleScoreLog.Reading? {
        log.reading(kind, day: Self.key(day))
    }

    func latest(_ kind: AppleScoreKind) -> AppleScoreLog.Entry? {
        log.latest(kind)
    }

    /// The daily numbers that haven't been added for today.
    var missingToday: [AppleScoreKind] {
        AppleScoreKind.allCases.filter { $0.isDaily && log.reading($0, day: todayKey) == nil }
    }

    /// The line for the on-device coach, or nil without any numbers.
    var coachLine: String? {
        log.coachLine(today: todayKey)
    }

    // MARK: Changing

    /// Saves the given numbers for `day`. Returns the kinds that were saved:
    /// a value outside its range is left out, and nothing is saved while the
    /// file can't be read.
    @discardableResult
    func save(_ values: [AppleScoreKind: Int], on day: Date, source: AppleScoreLog.Source) -> [AppleScoreKind] {
        guard canChange() else { return [] }
        let key = Self.key(day)
        let recordedAt = now
        var saved: [AppleScoreKind] = []
        for kind in AppleScoreKind.allCases {
            guard let value = values[kind] else { continue }
            if log.record(kind, value: value, day: key, at: recordedAt, source: source) { saved.append(kind) }
        }
        if !saved.isEmpty {
            fillSleepScores()
            write()
        }
        return saved
    }

    func remove(_ kind: AppleScoreKind, day: String) {
        guard canChange() else { return }
        log.remove(kind, day: day)
        write()
    }

    // MARK: Tensile's own numbers

    /// Keeps Tensile's numbers beside Apple's for the days they belong to, so
    /// the two can be compared later. Called after each refresh of the scores
    /// (`RootView`) and when the Apple scores screen opens.
    ///
    /// - recovery: today's score, or yesterday's while last night isn't over
    ///   (`DailyMetricsModel.recoveryIsFromYesterday`);
    /// - sleep score: from `SleepScoreLog`, for any recent morning;
    /// - body age: the current estimate, beside a Health Age entered today.
    func keepAppValues(recovery: Int?, recoveryIsFromYesterday: Bool, bodyAge: Int?) {
        guard !log.isEmpty, canChange() else { return }
        var changed = false
        let calendar = Calendar.current
        if let recovery {
            let day = recoveryIsFromYesterday ? calendar.date(byAdding: .day, value: -1, to: now) ?? now : now
            if log.setAppValue(.readiness, recovery, day: Self.key(day)) { changed = true }
        }
        if let bodyAge, log.setAppValue(.healthAge, bodyAge, day: todayKey) { changed = true }
        if fillSleepScores() { changed = true }
        if changed { write() }
    }

    /// Fills Tensile's sleep score in beside Apple's for the last two weeks of
    /// mornings that lack it. True when something changed (not yet written).
    @discardableResult
    private func fillSleepScores() -> Bool {
        let calendar = Calendar.current
        var changed = false
        for offset in 0..<14 {
            guard let morning = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = Self.key(morning)
            guard log.reading(.sleepScore, day: key) != nil, log.days[key]?.appSleepScore == nil,
                  let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: morning)),
                  let score = SleepScoreLog.recentScores(before: next, days: 1).first else { continue }
            if log.setAppValue(.sleepScore, score, day: key) { changed = true }
        }
        return changed
    }
}
