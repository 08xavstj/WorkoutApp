import SwiftUI
import AppCore

// Two sections of the weekly plan editor (`WeeklyPlanView`): "When life gets
// in the way" (a planned busy week, beside rest mode) and Apple Calendar.

/// A busy week chosen in advance (`BusyWeek`): one or two short sessions that
/// hold what you have, beside the rest mode switch. Lasts this week only.
struct BusyWeekSection: View {
    /// Sessions in the busy week, nil for a normal week.
    @Binding var sessions: Int?
    /// The week as it stands without the busy week (days, mode).
    let standing: WeeklyPlan
    /// Busy weeks in a row before this one.
    let weeksInARow: Int

    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        Section {
            Toggle("Busy week", isOn: isBusy)
                .accessibilityIdentifier("plan.busyWeek")
            if let count = sessions {
                Picker("Sessions", selection: countBinding) {
                    Text("1 session").tag(1)
                    Text("2 sessions").tag(2)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plan.busyWeek.sessions")
                Text(BusyWeek.summary(sessions: count))
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(preview(count)) { day in
                    LabeledContent(standing.isFlexible ? "Any day" : WeeklyPlan.weekdayName(day.weekday),
                                   value: "\(day.clockText()) · \(day.focus.shortTitle) · \(day.minutes) min")
                }
            }
            Toggle("Rest mode (sick or resting)", isOn: Binding(
                get: { settings.isRestMode },
                set: { on in
                    settings.setRestMode(on)
                    metrics.restMode = on
                }
            ))
            .accessibilityIdentifier("plan.restMode")
        } header: {
            Text("When life gets in the way")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        var text = "Busy week: each main lift for one or two hard sets at your usual weights. "
        text += BusyWeek.evidence(age: settings.ageIsSet ? settings.age : nil)
        if weeksInARow >= 1 {
            text += " The week counts as kept once you do a session; the review asks after \(BusyWeek.reviewAfterWeeks) in a row whether to build again."
        } else {
            text += " The week counts as kept once you do a session."
        }
        text += " Rest mode pauses strain targets and workout nudges for 3 days, for when you're ill."
        return text
    }

    private func preview(_ count: Int) -> [PlannedDay] {
        BusyWeek.plan(from: standing, sessions: count).sortedDays
    }

    private var isBusy: Binding<Bool> {
        Binding(
            get: { sessions != nil },
            set: { on in sessions = on ? BusyWeek.defaultSessions : nil }
        )
    }

    private var countBinding: Binding<Int> {
        Binding(get: { sessions ?? BusyWeek.defaultSessions }, set: { sessions = $0 })
    }
}

/// Fitness › This week, in a planned busy week: what the week does, and a
/// way back to the normal week.
struct BusyWeekNote: View {
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label("Busy week: \(sessionsText). \(BusyWeek.headline)", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("thisWeek.busyWeek")
            Spacer(minLength: 4)
            Button("Normal week") {
                store.setBusyWeek(sessions: nil)
                store.refreshBlock(hrvBelowNormal: metrics.trainEasyToday)
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minHeight: 44)
            .accessibilityHint("Goes back to this week's usual plan")
            .accessibilityIdentifier("thisWeek.busyWeek.end")
        }
    }

    private var sessionsText: String {
        let count = store.current?.busy?.sessions ?? BusyWeek.defaultSessions
        return count == 1 ? "one short session" : "two short sessions"
    }
}

/// The weekly review, after `BusyWeek.reviewAfterWeeks` busy weeks in a row:
/// "Build again this week?" Nothing at all before that.
struct BusyWeekReviewCard: View {
    let thisWeek: Date

    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @State private var answered = false

    var body: some View {
        if !answered, let question = BusyWeek.reviewQuestion(plans: store.plans, thisWeek: thisWeek) {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Busy weeks", color: Theme.liftingText)
                Text(question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A busy week keeps strength and muscle for a while; building them takes the normal plan. Either is fine.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button("Build again") { buildAgain() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("review.busyWeek.build")
                    Button("Another busy week") { anotherBusyWeek() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("review.busyWeek.again")
                }
                .font(.subheadline.weight(.semibold))
            }
            .card(tint: Theme.lifting)
        }
    }

    /// This week back to the standing plan (it already is, unless it was made busy).
    private func buildAgain() {
        store.setBusyWeek(sessions: nil)
        store.refreshBlock(hrvBelowNormal: metrics.trainEasyToday)
        answered = true
    }

    /// One more busy week, made from the standing plan.
    private func anotherBusyWeek() {
        let lastBusy = store.plans.last { $0.weekStart < thisWeek && $0.isBusy }?.busy?.sessions ?? BusyWeek.defaultSessions
        if store.plan(for: thisWeek) == nil, var last = store.lastPlan(before: thisWeek) {
            last.weekStart = thisWeek
            last.changes = []
            last.rotation = nil
            store.save(last)
        }
        store.setBusyWeek(sessions: lastBusy)
        store.refreshBlock(hrvBelowNormal: metrics.trainEasyToday)
        answered = true
    }
}

/// "Show sessions in Calendar": off by default; asks for calendar access
/// only when switched on (`PlanCalendarSync`).
struct PlanCalendarSection: View {
    @AppStorage(PlanCalendarSync.enabledKey) private var isOn = false
    @State private var denied = false

    var body: some View {
        Section {
            Toggle("Show sessions in Calendar", isOn: Binding(get: { isOn }, set: { switchTo($0) }))
                .accessibilityIdentifier("plan.calendar")
            if denied {
                Text("Calendar access is off for Tensile. Turn it on in Settings › Apps › Tensile › Calendars, then try again.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Apple Calendar")
        } footer: {
            // Milkman et al., PNAS 2011: a written date and time raised follow-through more than a date alone.
            Text("Puts this week's and next week's sessions in a calendar called \"\(PlanCalendar.calendarTitle)\" and keeps them in step when the plan changes. Writing down the day and the time made people more likely to follow through than the day alone (Milkman 2011). iOS lets an app change or remove its own events only with full calendar access, so that is what it asks for; Tensile reads only its own calendar. Turning this off removes that calendar.")
        }
    }

    private func switchTo(_ on: Bool) {
        guard on else {
            isOn = false
            denied = false
            PlanCalendarSync.shared.turnedOff()
            return
        }
        Task {
            let granted = await PlanCalendarSync.requestAccess()
            denied = !granted
            isOn = granted
            if granted { PlanCalendarSync.shared.accessGranted() }
        }
    }
}
