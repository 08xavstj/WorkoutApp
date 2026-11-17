import Foundation
import Observation
import AppCore

/// The insomnia path (`SleepWindow` in AppCore): its saved state as JSON in
/// Application Support (`SafeJSONFile`), and the glue to the rest of the app.
/// Nothing here shows anywhere until the owner's answers open the path; while
/// a course runs, tonight's bed-by window is the sleep window
/// (`DailyMetricsModel.bedtimeWindow`, `BedtimeWindow.sleepWindow`) and the
/// sleep-debt messages step aside (`sleepWindowOn`).
///
/// Not a SwiftData model: the schema is versioned and this is a few fields.
@Observable
final class SleepWindowStore {
    static let shared = SleepWindowStore()

    private(set) var state = SleepWindow.State()

    @ObservationIgnored private let file = SafeJSONFile.appSupport("sleep-window.json")
    /// False after a read that failed (phone locked): nothing is saved until a read works.
    @ObservationIgnored private var canSave = false
    /// The screenshot tour: answers live in memory only and never reach the file.
    @ObservationIgnored private let isDemo = DemoHealth.active != nil

    init() {
        reload()
    }

    /// Reads again if the last read couldn't (call on unlock and foreground).
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        guard !isDemo else { return }
        let loaded = file.loadLogged(SleepWindow.State.self)
        canSave = loaded.state.canSave
        if canSave { state = loaded.value ?? SleepWindow.State() }
    }

    private func write() {
        guard !isDemo else { return }
        file.saveLogged(state, canSave: canSave)
    }

    // MARK: Reading

    var course: SleepWindow.Course? { state.course }
    /// A course is running: the bed-by window is the sleep window.
    var isActive: Bool { state.course != nil }

    /// Tonight's bed-by window in sleep-window mode, nil when no course runs.
    func bedtimeWindow(sleepNeedHours: Double, now: Date = .now) -> BedtimeWindow.Result? {
        guard let course = state.course else { return nil }
        return BedtimeWindow.sleepWindow(minutes: course.windowMinutes, wakeMinutes: course.wakeMinutes,
                                         sleepNeedHours: sleepNeedHours, now: now)
    }

    /// The data's reason to raise the question (`SleepWindow.askReason`), only
    /// while the app may ask (not within 90 days of an answer, a "Not now", a
    /// refusal or a course).
    func askReason(nights: [SleepNight], checkIns: CheckInStore, now: Date = .now) -> SleepWindow.AskReason? {
        guard state.mayAsk(now: now) else { return nil }
        return SleepWindow.askReason(mornings: Self.mornings(checkIns, now: now), nights: Self.nights(nights), now: now)
    }

    // MARK: Answers and decisions

    func answer(_ answers: SleepWindow.Answers) {
        reloadIfUnavailable()
        state.answers = answers
        write()
    }

    /// "Not now" on the question: not raised again by itself for 90 days.
    func notNow(now: Date = .now) {
        reloadIfUnavailable()
        state.notNowDay = Calendar.current.startOfDay(for: now)
        write()
    }

    func refuse(_ refusals: [SleepWindow.Refusal], now: Date = .now) {
        reloadIfUnavailable()
        state.refusals = refusals
        state.refusedDay = Calendar.current.startOfDay(for: now)
        write()
    }

    func start(_ proposal: SleepWindow.Proposal, wakeMinutes: Int, now: Date = .now) {
        reloadIfUnavailable()
        state.course = SleepWindow.start(proposal, wakeMinutes: wakeMinutes, now: now)
        state.outcome = nil
        state.refusals = nil
        write()
    }

    // MARK: While it runs

    /// "Too sleepy": 15 minutes longer at once; finished if that reaches the regular window.
    func tooSleepy(sleepNeedHours: Double, now: Date = .now) {
        reloadIfUnavailable()
        guard let course = state.course else { return }
        let regular = SleepWindow.regularMinutes(sleepNeedHours: sleepNeedHours)
        state.course = SleepWindow.tooSleepy(course, regularMinutes: regular, now: now)
        if let updated = state.course, updated.windowMinutes >= regular {
            end(.reachedRegular, now: now)
        } else {
            write()
        }
    }

    /// He chose to keep going after the suggestion to see someone.
    func continuePastStall() {
        reloadIfUnavailable()
        state.course?.continuedPastStall = true
        write()
    }

    /// Stop at any time: the regular bed-by window is back at once.
    func stop(now: Date = .now) {
        reloadIfUnavailable()
        end(.stopped, now: now)
    }

    /// The eight-week question: still three or more bad nights a week?
    func answerStillStruggling(_ yes: Bool) {
        reloadIfUnavailable()
        state.outcome?.stillStruggling = yes
        write()
    }

    /// The ending has been read.
    func dismissOutcome() {
        reloadIfUnavailable()
        state.outcome = nil
        write()
    }

    private func end(_ ending: SleepWindow.Ending, refusals: [SleepWindow.Refusal] = [], now: Date) {
        guard let course = state.course else { return }
        let day = Calendar.current.startOfDay(for: now)
        state.outcome = SleepWindow.Outcome(ending: ending, day: day, weeks: course.reviews.count,
                                            wakeMinutes: course.wakeMinutes, refusals: refusals)
        state.endedDay = day
        state.course = nil
        write()
    }

    /// Runs the weekly reviews that are due and ends the course when it's
    /// done, or at once when the watch flags possible apnoea or the nights
    /// turn into a shift pattern. Called on every metrics refresh; does
    /// nothing without a course.
    func refresh(nights: [SleepNight], sleepNeedHours: Double, resting: Bool, apnoeaFlaggedNights: Int, now: Date = .now) {
        reloadIfUnavailable()
        guard let course = state.course else { return }
        let windowNights = Self.nights(nights)
        let stopReasons = SleepWindow.stopReasons(apnoeaFlaggedNights: apnoeaFlaggedNights, nights: windowNights)
        if !stopReasons.isEmpty {
            end(.excluded, refusals: stopReasons, now: now)
            return
        }
        let result = SleepWindow.advance(course, nights: windowNights,
                                         regularMinutes: SleepWindow.regularMinutes(sleepNeedHours: sleepNeedHours),
                                         resting: resting, now: now)
        guard result.course != course || result.outcome != nil else { return }
        state.course = result.course
        if let outcome = result.outcome {
            state.outcome = outcome
            state.endedDay = outcome.day
            state.course = nil
        }
        write()
    }

    // MARK: Conversions

    nonisolated static func nights(_ nights: [SleepNight]) -> [SleepWindow.Night] {
        nights.map { SleepWindow.Night(date: $0.date, asleepHours: $0.hoursAsleep, bedtime: $0.bedtime, wake: $0.wake) }
    }

    /// The last four weeks of morning check-ins, as far as sleep goes.
    static func mornings(_ checkIns: CheckInStore, now: Date = .now) -> [SleepWindow.MorningReport] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<SleepWindow.askDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let morning = checkIns.morning(on: day) else { return nil }
            return SleepWindow.MorningReport(day: day, rested: morning.rested, nightWakings: morning.nightWakings)
        }
    }

    /// What the data says before anything is offered: the apnoea screen
    /// (STOP-Bang, nil when never answered or over a year old), Apple Watch's
    /// apnoea flags and breathing disturbances, and a shift-work pattern.
    static func screening(declared: Set<SleepWindow.Exclusion>, stopBang: BodyMeasurementsStore.StopBangEntry?,
                          health: HealthKitClient?, nights: [SleepNight], now: Date = .now) async -> SleepWindow.Screening {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now
        let score = stopBang.flatMap { $0.date >= yearAgo ? $0.score : nil }
        var flagged = 0
        var rising = false
        if let health {
            flagged = ((try? await health.sleepApneaNights(days: 30)) ?? []).count
            let disturbances = (try? await health.breathingDisturbances(days: 60)) ?? []
            rising = IllnessWatch.breathingDisturbancesRising(nightly: disturbances.map(\.value))
        }
        return SleepWindow.Screening(declared: declared, stopBangScore: score, apnoeaFlaggedNights: flagged,
                                     breathingDisturbancesUp: rising,
                                     daytimeSleeps: SleepWindow.daytimeSleeps(Self.nights(nights)))
    }
}

extension DailyMetricsModel {
    /// The insomnia path's sleep window is on: sleep debt is paused and
    /// "sleep more" messages step aside (`SleepWindowStore`).
    var sleepWindowOn: Bool { SleepWindowStore.shared.isActive }
}
