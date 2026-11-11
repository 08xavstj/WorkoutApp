import SwiftUI
import SwiftData
import AppCore

/// Fitness › This week, the tab's primary card (docs/research/ux-audit.md
/// 4.6 Fitness): this week's planned days as dots, today's slot with Start
/// and Short version, the rolling 4-week consistency score, the deload line,
/// a kind restart after a week off, and Edit plan / Review. With no plan:
/// Plan your week (and Same days as last week).
///
/// Moved from Today's `ConsistencyCard` (same logic and wording). It is a
/// consistency score, never a streak: missing one day didn't hurt habit
/// formation (Lally et al. 2010) and showing a broken streak lowers
/// engagement (Silverman & Barasch 2023), so a missed day is a grey dot, not
/// a red one, and there is no "broken" anywhere.
///
/// A fixed-day plan runs as a queue (`AdaptiveWeek`): a session done on
/// another day ticks its own dot (Upper done Tuesday ticks Monday's Upper),
/// today shows the next session not done yet, a session moved for soreness
/// says so, and the week's "why a different workout?" answers are listed.
///
/// A flexible plan (`WeeklyPlan.Mode.flexible`) shows "2 of 4 done · 3 days
/// left" with one dot per session, and the next session's focus from the
/// coverage rule (`MuscleCoverage`): the week only needs its total.
struct ThisWeekCard: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(AppRouter.self) private var router
    @Environment(MuscleModel.self) private var muscles
    @Environment(CheckInStore.self) private var checkIns

    private var thisWeek: Date { WeeklyPlan.weekStart(containing: .now) }

    var body: some View {
        let plan = store.current
        let consistency = store.consistency(sessions: sessions, extra: metrics.recentLiftingDays)
        // Fixed week as a queue (`AdaptiveWeek`): dots tick the matching planned session, not the weekday.
        let queue = plan?.isFlexible == false
            ? store.adaptiveWeek(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns, muscles: muscles)
            : nil
        let done = queue?.doneWeekdays ?? store.doneWeekdays(sessions: sessions, extra: metrics.recentLiftingDays)
        VStack(alignment: .leading, spacing: 14) {
            header(consistency)
            TravelGymChip() // only while a travel gym is active
            if let plan, plan.isFlexible {
                FlexibleWeekRow(plan: plan, sessions: sessions)
                FlexibleNextSlot(sessions: sessions)
            } else if let plan {
                PlanDots(days: plan.sortedDays, done: done,
                         sessionsDone: store.sessionsDone(sessions: sessions, extra: metrics.recentLiftingDays))
                if let queue {
                    QueueTodaySlot(week: queue, sessions: sessions)
                } else {
                    PlanTodaySlot(plan: plan, done: done)
                }
            } else {
                noPlan
            }
            if plan != nil { CardioWeekRows() }
            ThisWeekDeloadLine()
            if let note = consistency.note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            restart
            planLinks(hasPlan: plan != nil)
        }
        .card(tint: Theme.lifting)
        // The Monday review reminder follows its settings (one repeating notification, "review|weekly").
        .task(id: "\(settings.weeklyReviewOn)|\(settings.weeklyReviewMinutes)") {
            await Reminders.scheduleWeeklyReview(enabled: settings.weeklyReviewOn, minutes: settings.weeklyReviewMinutes)
        }
        // This week's per-muscle set targets (`VolumeProgression`) and the cardio-only days, once muscles have loaded.
        .task(id: muscles.hasRefreshed) {
            store.refreshVolume(muscles: muscles)
        }
        // The queue for today's guidance, reminders and the watch (as on Today's Scores card).
        .task(id: store.adaptiveKey(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns) + (muscles.hasRefreshed ? "|m" : "")) {
            let week = store.refreshAdaptive(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns, muscles: muscles)
            if metrics.adaptiveWeek != week { metrics.adaptiveWeek = week }
        }
    }

    private func header(_ consistency: Consistency.Result) -> some View {
        HStack(spacing: 10) {
            CardLabel(text: "This week", color: Theme.liftingText)
            Spacer()
            if consistency.plannedWeeks > 0 {
                // Green when most weeks were kept, otherwise plain grey: never red.
                Chip(text: Self.chipText(consistency.label), color: consistency.score >= Consistency.keptFraction ? Theme.recoveryHigh : Theme.secondaryText)
                    .accessibilityLabel("Consistency: \(consistency.label) on plan")
            }
        }
    }

    /// "4 of 4 weeks kept" rather than a bare "4 of 4 weeks"; other labels
    /// ("Getting going") as they are.
    private static func chipText(_ label: String) -> String {
        label.hasSuffix(" weeks") || label.hasSuffix(" week") ? label + " kept" : label
    }

    private var noPlan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No plan for this week yet")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            // Implementation intentions: Gollwitzer & Sheeran 2006 (d = 0.65 across 94 tests). The
            // flexible option (sessions a week, any days) rests on autonomy support (Teixeira 2012;
            // Ntoumanis 2021) and is offered as a choice, not a recommendation.
            Text("Pick how many sessions this week, or fixed days and a time, and decide now what you'll do when the day goes wrong. People who plan the when and what follow through far more often.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let last = store.lastPlan(before: thisWeek), !last.plannedDays.isEmpty {
                    PlanButton(title: last.isFlexible ? "Same as last week" : "Same days as last week", filled: false) {
                        store.save(WeeklyPlan(weekStart: thisWeek,
                                              plannedDays: store.newWeekDays(from: last.plannedDays, weekStart: thisWeek, sessions: sessions),
                                              mode: last.mode, sessionsPerWeek: last.sessionsPerWeek, cardio: last.cardio))
                    }
                }
                PlanButton(title: "Plan your week", filled: true) { router.showWeeklyPlan = true }
            }
        }
    }

    /// Edit plan (only with a plan; without one, Plan your week is above) and
    /// Review: text buttons with 44 pt targets (ux-audit.md 4.8, P23).
    private func planLinks(hasPlan: Bool) -> some View {
        HStack(spacing: 20) {
            if hasPlan {
                PlanTextButton(title: "Edit plan", systemImage: "calendar.badge.clock") {
                    router.showWeeklyPlan = true
                }
                .accessibilityHint("Change your training days, or how many sessions a week")
            }
            PlanTextButton(title: "Review", systemImage: "chart.bar.doc.horizontal") {
                router.showWeeklyReview = true
            }
            .accessibilityHint("Last week in numbers and three changes for this week")
            Spacer(minLength: 0)
        }
    }

    /// After 7+ days without a session (and not in rest mode): a smaller plan
    /// and no summary of what was missed (Marlatt & Gordon 1985; Semenchuk
    /// 2018; Mujika & Padilla 2000, all from memory in the report).
    @ViewBuilder
    private var restart: some View {
        if !settings.isRestMode,
           let daysOff = store.daysOff(sessions: sessions, extra: metrics.recentTrainingDays),
           let lighter = RestartPlan.make(daysOff: daysOff, lastPlan: store.lastPlan(before: thisWeek) ?? store.current,
                                          goals: settings.goalsSet ? settings.goals : nil) {
            Divider().overlay(Theme.separator)
            VStack(alignment: .leading, spacing: 8) {
                Label("Welcome back", systemImage: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.recoveryHighText)
                Text(lighter.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let current = store.current, !current.plannedDays.isEmpty,
                   current.plannedDays.allSatisfy({ $0.minutes <= $0.shortVersionMinutes }) {
                    Chip(text: "Lighter week set", color: Theme.recoveryHigh)
                } else {
                    PlanButton(title: "Use this lighter week", filled: true) {
                        // Keeps the plan's mode; a flexible restart week asks for the lighter count on any days.
                        let template = store.current ?? store.lastPlan(before: thisWeek)
                        store.save(WeeklyPlan(weekStart: thisWeek, plannedDays: lighter.plannedDays, changes: store.current?.changes ?? [],
                                              mode: template?.mode ?? .fixedDays,
                                              sessionsPerWeek: template?.isFlexible == true ? lighter.plannedDays.count : nil,
                                              cardio: template?.cardio))
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

/// One dot per planned day: green when done, grey when not (a missed day is
/// not an error), today outlined.
private struct PlanDots: View {
    let days: [PlannedDay]
    let done: Set<Int>
    let sessionsDone: Int

    var body: some View {
        let today = Calendar.current.component(.weekday, from: .now)
        HStack(alignment: .top, spacing: 14) {
            ForEach(days) { day in
                let isDone = done.contains(day.weekday)
                VStack(spacing: 4) {
                    Circle()
                        .fill(isDone ? Theme.recoveryHigh : Theme.pendingMark)
                        .frame(width: 14, height: 14)
                        .overlay {
                            if day.weekday == today && !isDone {
                                Circle().strokeBorder(Theme.lifting, lineWidth: 2)
                            }
                        }
                    Text(WeeklyPlan.weekdayName(day.weekday))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(WeeklyPlan.weekdayName(day.weekday)): \(isDone ? "done" : "planned")")
            }
            Spacer(minLength: 0)
            Text(summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    /// "2 of 4 done · +2 other workouts": the count matches the ticked dots;
    /// training on days that weren't planned is named separately.
    private var summary: String {
        let plannedDone = days.filter { done.contains($0.weekday) }.count
        let other = max(0, sessionsDone - plannedDone)
        let base = "\(plannedDone) of \(days.count) done"
        guard other > 0 else { return base }
        return base + " · +\(other) other workout" + (other == 1 ? "" : "s")
    }
}

/// Flexible week: one dot per session, filled by count (any day counts), and
/// "2 of 4 done · 3 days left".
private struct FlexibleWeekRow: View {
    let plan: WeeklyPlan
    let sessions: [WorkoutSession]

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(WeeklyPlanStore.self) private var store

    var body: some View {
        // Through the store, so days that were only easy cardio don't count toward the lifting quota.
        let progress = store.progress(sessions: sessions, extra: metrics.recentLiftingDays)
            ?? plan.progress(trainingDays: WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentLiftingDays))
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<max(progress.target, 0), id: \.self) { index in
                    Circle()
                        .fill(index < progress.done ? Theme.recoveryHigh : Theme.pendingMark)
                        .frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            Text(progress.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sessions this week: \(progress.label)")
    }
}

/// Flexible week: the next session (focus from `MuscleCoverage`, length from
/// the plan) with Start / Short version, the day's guidance when it says rest
/// or easy, and "Week done" once the quota is met.
private struct FlexibleNextSlot: View {
    let sessions: [WorkoutSession]

    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(MuscleModel.self) private var muscles
    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        let progress = store.progress(sessions: sessions, extra: metrics.recentLiftingDays)
        if let progress, progress.isMet {
            Text(progress.trainedToday
                 ? "Done today, and that's the week's \(progress.target). Rest days until Monday."
                 : "Week done: all \(progress.target) sessions. Rest days until Monday; a walk is good.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else if let progress, progress.trainedToday {
            Chip(text: "Done today", color: Theme.recoveryHigh)
            Text("\(progress.remaining) to go, \(max(0, progress.daysLeft - 1)) more \(progress.daysLeft - 1 == 1 ? "day" : "days") this week. Any day you feel good is a training day.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else if let next = store.nextSession(sessions: sessions, extra: metrics.recentLiftingDays, muscles: muscles) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Next: \(next.day.focus.shortTitle), \(next.day.minutes) min")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(nextLine(next.coverage))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    PlanButton(title: "Start", filled: true) {
                        launcher.openBuilder(focus: next.day.focus, minutes: next.day.minutes)
                    }
                    // The minimum version (Swann 2021; report rec. 7).
                    PlanButton(title: "Short version · \(next.day.shortVersionMinutes) min", filled: false) {
                        launcher.openBuilder(focus: next.day.focus, minutes: next.day.shortVersionMinutes)
                    }
                }
            }
        }
    }

    /// Why this focus (the coverage rule), then today's guidance when it
    /// says rest or easy (`TrainingDayPlanner.flexibleGuidance`).
    private func nextLine(_ coverage: MuscleCoverage.Result?) -> String {
        var parts: [String] = []
        if let reason = coverage?.reason {
            parts.append(reason.prefix(1).uppercased() + reason.dropFirst() + ".")
        } else {
            parts.append("Any day you feel good is a training day; the week only needs its total.")
        }
        if let guidance = metrics.dayGuidance, guidance.kind != .training {
            parts.append(guidance.reason)
        }
        return parts.joined(separator: " ")
    }
}

/// The week's easy cardio (`CardioPlanner`): "Easy ride · 30 min" with its
/// day (or "Any day") and a tick once Apple Health has a workout of that type
/// that day, then the minutes toward the 150-300 band (WHO 2020, Bull et al.).
private struct CardioWeekRows: View {
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(MuscleModel.self) private var muscles
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let slots = store.cardioSlots(goals: metrics.goals)
        if !slots.isEmpty {
            let done = store.cardioDone(slots: slots, workouts: WeeklyPlanStore.cardioWorkouts(muscles: muscles, metrics: metrics))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(slots) { slot in
                    CardioSlotRow(slot: slot, isDone: done.contains(slot.index))
                }
                if let line = CardioPlanner.bandLine(store.current?.cardio, goals: metrics.goals) {
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CardioSlotRow: View {
    let slot: CardioPlanner.Slot
    let isDone: Bool

    var body: some View {
        let day = slot.weekday.map { WeeklyPlan.weekdayName($0) } ?? "Any day"
        let status = isDone ? "done" : "planned"
        HStack(spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isDone ? Theme.recoveryHigh : Theme.secondaryText)
            Label("\(slot.kind.title) · \(slot.minutes) min", systemImage: slot.kind.systemImage)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text(day)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.kind.title), \(slot.minutes) minutes, \(day): \(status)")
    }
}

/// A fixed week's queue (`AdaptiveWeek`): today's session (wherever the
/// calendar had it) with Start / Short version, or the next one once today is
/// done or a rest day; soreness moves, sessions still to do, this week's
/// swaps and, once, "why the switch?" after a different session.
private struct QueueTodaySlot: View {
    let week: AdaptiveWeek.Result
    let sessions: [WorkoutSession]

    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let slot = week.today {
                todaySession(slot)
            } else {
                upNext
            }
            if week.today != nil || week.next != nil, let note = week.stillToDoNote {
                QueueNote(text: note, systemImage: "calendar")
            }
            ForEach(store.swapLines(weekStart: week.weekStart), id: \.self) { line in
                QueueNote(text: "Swapped " + line, systemImage: "arrow.triangle.swap")
            }
            if let swap = store.unansweredSwap(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns) {
                SwapQuestionButton(planned: swap.planned, chosen: swap.chosen)
            }
        }
    }

    @ViewBuilder
    private func todaySession(_ slot: AdaptiveWeek.Slot) -> some View {
        let day = slot.session
        let moved = slot.isMoved ? " · from " + WeeklyPlan.weekdayName(slot.plannedWeekday) : ""
        Text("Today \(day.clockText()): \(day.focus.shortTitle), \(day.minutes) min\(moved)")
            .font(.headline)
            .foregroundStyle(Theme.primaryText)
        if let note = slot.note {
            QueueNote(text: note, systemImage: "figure.cooldown")
        } else if let ifThen = day.ifThen, !ifThen.isEmpty {
            Text(ifThen)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        HStack(spacing: 10) {
            PlanButton(title: "Start", filled: true) {
                launcher.openBuilder(focus: day.focus, minutes: slot.short ? day.shortVersionMinutes : day.minutes)
            }
            // The minimum version (Swann 2021; report rec. 7).
            PlanButton(title: "Short version · \(day.shortVersionMinutes) min", filled: false) {
                launcher.openBuilder(focus: day.focus, minutes: day.shortVersionMinutes)
            }
        }
    }

    @ViewBuilder
    private var upNext: some View {
        if week.liftedToday {
            Chip(text: "Done today", color: Theme.recoveryHigh)
        }
        if let next = week.next, let label = week.nextLabel {
            Text("\(label), \(Self.dayWord(next.date))")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            if let note = next.note ?? week.moveNote {
                QueueNote(text: note, systemImage: "figure.cooldown")
            }
        } else if let note = week.stillToDoNote {
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Rest day. That's the week's plan done; the review sets the next one.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    /// "tomorrow", or "Thu".
    private static func dayWord(_ date: Date) -> String {
        Calendar.current.isDateInTomorrow(date) ? "tomorrow" : WeeklyPlan.weekdayName(Calendar.current.component(.weekday, from: date))
    }
}

/// A small icon line under the queue's session.
private struct QueueNote: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Today's planned session with Start / Short version, or the next planned day.
private struct PlanTodaySlot: View {
    let plan: WeeklyPlan
    let done: Set<Int>

    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        let weekday = Calendar.current.component(.weekday, from: .now)
        if let today = plan.day(for: weekday) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(timeWord(today)) \(today.clockText()): \(today.focus.shortTitle), \(today.minutes) min")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                if let ifThen = today.ifThen, !ifThen.isEmpty {
                    Text(ifThen)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                if done.contains(weekday) {
                    Chip(text: "Done today", color: Theme.recoveryHigh)
                } else {
                    HStack(spacing: 10) {
                        PlanButton(title: "Start", filled: true) {
                            launcher.openBuilder(focus: today.focus, minutes: today.minutes)
                        }
                        // The minimum version: on a low day the goal is open, "do the short one and see" (Swann 2021; report rec. 7).
                        PlanButton(title: "Short version · \(today.shortVersionMinutes) min", filled: false) {
                            launcher.openBuilder(focus: today.focus, minutes: today.shortVersionMinutes)
                        }
                    }
                }
            }
        } else if let next = plan.sortedDays.first(where: { WeeklyPlan.order($0.weekday) > WeeklyPlan.order(weekday) }) {
            Text("Rest day. Next: \(WeeklyPlan.weekdayName(next.weekday)) \(next.clockText()), \(next.focus.shortTitle.lowercased()).")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        } else if plan.plannedDays.isEmpty {
            Text("No training days planned this week.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        } else {
            Text("Rest day. That's the week's plan done; the review sets the next one.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func timeWord(_ day: PlannedDay) -> String {
        let now = Calendar.current.dateComponents([.hour, .minute], from: .now)
        let minutesNow = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        if day.time < minutesNow - 30 { return "Today" }
        switch day.time {
        case ..<(12 * 60): return "This morning"
        case ..<(17 * 60): return "This afternoon"
        default: return "Tonight"
        }
    }
}

/// The deload line: a chip naming the training block's planned deload, or
/// the stalled-lifts advice, with one line of what it means. Tapping opens
/// the Strength page, which holds the full deload card and its research
/// (Bell et al., Sports Med Open 2023 consensus; `TrainingBlock`,
/// `DeloadAdvisor`; ux-audit.md 4.3).
private struct ThisWeekDeloadLine: View {
    @Environment(MuscleModel.self) private var muscles
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(DailyMetricsModel.self) private var metrics

    private struct Info {
        let chip: String
        let line: String
        let color: Color
    }

    private var info: Info? {
        if let week = plans.projectedBlockWeek(hrvBelowNormal: metrics.trainEasyToday), week.isDeload {
            return Info(chip: "Planned deload this week", line: week.note, color: Theme.oxygen)
        }
        if let advice = muscles.deload {
            return Info(
                chip: advice.strong ? "Time for a deload week" : "Consider a lighter week",
                line: "Stalled: " + advice.stalledLifts.joined(separator: ", "),
                color: advice.strong ? Theme.recoveryModerate : Theme.oxygen
            )
        }
        return nil
    }

    var body: some View {
        if let info {
            NavigationLink {
                StrengthDetailView()
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Chip(text: info.chip, color: info.color)
                        Text(info.line)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Shows what a deload changes and why")
        }
    }
}

/// Capsule button in the card's two styles (gradient or raised).
private struct PlanButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(filled ? .white : Theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(filled ? AnyShapeStyle(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Theme.cardRaised), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A small text button with an icon and a 44 pt hit target.
private struct PlanTextButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
