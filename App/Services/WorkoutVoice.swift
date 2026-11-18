import AppCore
import Foundation
import SwiftData

// The workout reminder's voice: a playful (or plain) line written from the
// day's own data. The rules, the lines and every check are in AppCore
// (`WorkoutBanter`, `WorkoutBanterLibrary`, `WorkoutBanterGuard`); this file
// gathers the facts from the app's models; `WorkoutVoiceStore` keeps each
// pending reminder's line on disk, and `WorkoutVoiceWriter` builds the
// notifications and, when Apple Intelligence is on, lets the on-device model
// write some of the lines. None of it uses the network.
// Research and reasons: docs/research/funny-nudges-2026-11.md.

/// What `Reminders.scheduleWorkoutReminders` needs from the main actor: the
/// tone and, for each planned slot (by its start), the facts a line may use.
nonisolated struct WorkoutVoiceContext: Sendable {
    var tone: WorkoutBanter.Tone = .playful
    /// Let the on-device model write some of the playful lines.
    var freshLines = true
    var facts: [Date: WorkoutBanter.Facts] = [:]
}

/// Gathers the facts for the reminder lines from the app's models.
enum WorkoutVoice {
    /// The models the facts come from.
    struct Sources {
        let settings: UserSettings
        let metrics: DailyMetricsModel
        let vitals: VitalsModel
        let checkIns: CheckInStore
        let plans: WeeklyPlanStore
        let muscles: MuscleModel
        let gym: GymStore
        let library: ExerciseLibrary
        let sessions: [WorkoutSession]
    }

    /// The tone and every slot's facts. Today's slot gets the day's own data
    /// (days off, the week's count, recovery, illness, pain, what stood out
    /// last session); later days only get what will still be true then.
    static func context(slots: [Reminders.PlannedSlot], from sources: Sources, now: Date = .now) -> WorkoutVoiceContext {
        var context = WorkoutVoiceContext(tone: sources.settings.workoutReminderTone,
                                          freshLines: sources.settings.workoutReminderFreshLines)
        guard sources.settings.workoutRemindersOn, !slots.isEmpty else { return context }
        let day = dayFacts(sources, now: now)
        let calendar = Calendar.current
        for slot in slots {
            context.facts[slot.start] = facts(for: slot, today: day.today, ahead: day.ahead, plans: sources.plans, now: now, calendar: calendar)
        }
        return context
    }

    /// What is known today (`today`) and the part of it that holds for later days (`ahead`).
    static func dayFacts(_ sources: Sources, now: Date) -> (today: WorkoutBanter.Facts, ahead: WorkoutBanter.Facts) {
        let finished = LiftRecordInputs.sessions(sources.sessions)
        let traits = LiftRecordInputs.traits(finished, library: sources.library)
        let profile = sources.gym.profile
        let unit = profile.unit
        let library = sources.library

        var ahead = WorkoutBanter.Facts()
        ahead.unit = unit
        ahead.leadMinutes = Reminders.workoutLeadMinutes
        // The next step is the next weight this gym can load (`GymProfile.nextLoad`), never a made-up jump.
        ahead.lift = WorkoutBanterFacts.lift(sessions: finished, traits: traits, now: now) { id, kilograms in
            let kind = ExerciseCatalog.exercise(id: id)?.load ?? EquipmentKind.fromLibrary(library.exercise(id: id)?.equipment)
            guard let kind, let next = profile.nextLoad(above: unit.fromKilograms(kilograms), on: kind) else { return nil }
            return unit.toKilograms(next)
        }
        let extra = sources.metrics.recentLiftingDays
        let weeks = WorkoutBanterFacts.weeksInARow(records: sources.plans.records(sessions: sources.sessions, extra: extra), now: now)
        if weeks >= 2 { ahead.weeksInARow = weeks }
        // Three or more low-mood mornings this week: plain words, no jokes (`MoodCare`, `Caution.keepPlain`).
        // Later days too: a line written ahead is rewritten on its own day with that day's mornings.
        // A positive PHQ-9 or GAD-7 in the last 4 weeks does the same (`MoodQuestionnaires.keepPlainDays`).
        ahead.keepPlain = MoodCare.keepPlain(lowMood: CoachNudges.lowMoodFinding(checkIns: sources.checkIns, now: now),
                                             screens: MoodScreenStore.shared.results, now: now)

        var today = ahead
        today.daysSinceLastSession = sources.plans.daysOff(sessions: sources.sessions, extra: extra, now: now)
        if let progress = sources.plans.progress(sessions: sources.sessions, extra: extra, now: now) {
            today.sessionsDone = progress.done
            today.sessionsPlanned = progress.target
        }
        today.neglected = WorkoutBanterFacts.neglected(lastTrained: sources.muscles.states.compactMapValues(\.lastTrained), now: now)
        today.standout = WorkoutBanterFacts.standout(sessions: finished, traits: traits, now: now)
        // The app's own safety states: any of them makes the reminder plain and kind (`WorkoutBanter.Caution`).
        if let recovery = sources.metrics.recovery, !sources.metrics.recoveryIsFromYesterday {
            today.recovery = sources.metrics.trainEasyToday ? .low : WorkoutBanterFacts.recoveryBand(score: recovery.score)
        }
        let illness = todayIllnessAlert(vitals: sources.vitals, metrics: sources.metrics, checkIns: sources.checkIns)
        today.illnessFlagged = illness?.level == .major || sources.checkIns.morning()?.isSick == true
        let pains = PainGuard.active(PainLogStore.shared.allReports(checkIns: sources.checkIns, health: []), today: now)
        today.painArea = pains.max { $0.level < $1.level }?.area.title.lowercased()
        today.restMode = sources.settings.isRestMode
        return (today, ahead)
    }

    /// One slot's facts: the day's (or the week's) plus the session itself.
    static func facts(for slot: Reminders.PlannedSlot, today: WorkoutBanter.Facts, ahead: WorkoutBanter.Facts,
                      plans: WeeklyPlanStore, now: Date, calendar: Calendar) -> WorkoutBanter.Facts {
        var facts = calendar.isDate(slot.start, inSameDayAs: now) ? today : ahead
        facts.sessionName = slot.focus.map { WorkoutBanterFacts.dayName(for: $0) } ?? slot.name
        facts.sessionMinutes = slot.minutes
        if let short = slot.shortMinutes, let minutes = slot.minutes, short < minutes { facts.shortMinutes = short }
        let parts = calendar.dateComponents([.hour, .weekday], from: slot.start)
        facts.hour = parts.hour
        facts.weekday = parts.weekday
        facts.isDeloadWeek = plans.projectedBlockWeek(now: slot.start)?.isDeload ?? false
        // A planned busy week holds, it doesn't build (`BusyWeek`): no line asks for a record or calls a lift stuck.
        if plans.plan(containing: slot.start)?.isBusy == true { facts.lift = nil }
        return facts
    }

    // MARK: Preview (Settings › Notifications › "Show me one")

    struct Preview: Equatable {
        var pick: WorkoutBanter.Pick
        /// What the line was written for, or why it is plain today.
        var note: String
    }

    /// A line as a reminder could carry it today, from today's data. Nothing
    /// is used up: the history is only read. `shown` are the previews already
    /// on screen, so each tap gives another line in another register.
    static func preview(from sources: Sources, shown: [WorkoutBanter.Pick], now: Date = .now) -> Preview {
        let calendar = Calendar.current
        let trainingDays = WeeklyPlanStore.trainingDays(sessions: sources.sessions, extra: sources.metrics.recentLiftingDays)
        let slots = sources.plans.reminderSlots(trainingDays: trainingDays, now: now).sorted { $0.start < $1.start }
        let day = dayFacts(sources, now: now)
        var facts = day.today
        var note = "Nothing is planned this week yet."
        if let slot = slots.first(where: { calendar.isDate($0.start, inSameDayAs: now) }) {
            facts = Self.facts(for: slot, today: day.today, ahead: day.ahead, plans: sources.plans, now: now, calendar: calendar)
            note = "Written for today's session."
        } else if let next = slots.first(where: { $0.start > now }) {
            // Nothing planned today: the next session, with today's numbers.
            facts = Self.facts(for: next, today: day.today, ahead: day.today, plans: sources.plans, now: now, calendar: calendar)
            note = "Written for \(next.start.formatted(.dateTime.weekday(.wide)))'s session, with today's numbers."
        } else {
            facts.isRestDay = true
        }
        switch facts.caution {
        case .restMode: note = "Rest mode is on, so no workout reminders are sent."
        case .illness: note = "Illness is flagged today, so the reminder stays plain."
        case .pain: note = "Pain is logged, so the reminder stays plain."
        case .lowRecovery: note = "Recovery is low today, so the reminder stays plain."
        case .keepPlain: note = "Mood has been low lately, so reminders stay plain for now. The reminder itself never says why."
        case .restDay, nil: break
        }
        var history = WorkoutVoiceStore.shared.history()
        let key = Reminders.dayKey(now, calendar: calendar)
        for (index, pick) in shown.enumerated() {
            history.record(WorkoutBanter.History.Entry(dayKey: "preview|\(index)", lineID: pick.lineID, situation: pick.situation,
                                                       register: pick.register, opening: WorkoutBanter.opening(of: pick.text),
                                                       motif: WorkoutBanter.motif(of: pick.text), text: pick.text))
        }
        let pick = WorkoutBanter.pick(facts: facts, tone: sources.settings.workoutReminderTone, history: history,
                                      seed: WorkoutBanter.seed(for: "preview|\(key)|\(shown.count)"))
        return Preview(pick: pick, note: note)
    }
}
