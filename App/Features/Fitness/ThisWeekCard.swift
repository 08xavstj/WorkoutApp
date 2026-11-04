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
struct ThisWeekCard: View {
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @Environment(WeeklyPlanStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(AppRouter.self) private var router

    private var thisWeek: Date { WeeklyPlan.weekStart(containing: .now) }

    var body: some View {
        let plan = store.current
        let consistency = store.consistency(sessions: sessions, extra: metrics.recentTrainingDays)
        let done = store.doneWeekdays(sessions: sessions, extra: metrics.recentTrainingDays)
        VStack(alignment: .leading, spacing: 14) {
            header(consistency)
            if let plan {
                PlanDots(days: plan.sortedDays, done: done,
                         sessionsDone: store.sessionsDone(sessions: sessions, extra: metrics.recentTrainingDays))
                PlanTodaySlot(plan: plan, done: done)
            } else {
                noPlan
            }
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
    }

    private func header(_ consistency: Consistency.Result) -> some View {
        HStack(spacing: 10) {
            CardLabel(text: "This week", color: Theme.liftingText)
            Spacer()
            if consistency.plannedWeeks > 0 {
                // Green when most weeks were kept, otherwise plain grey: never red.
                Chip(text: consistency.label, color: consistency.score >= Consistency.keptFraction ? Theme.recoveryHigh : Theme.secondaryText)
                    .accessibilityLabel("Consistency: \(consistency.label) on plan")
            }
        }
    }

    private var noPlan: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No plan for this week yet")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            // Implementation intentions: Gollwitzer & Sheeran 2006 (d = 0.65 across 94 tests).
            Text("Pick your training days and a time, and decide now what you'll do when the day goes wrong. People who plan the when and what follow through far more often.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let last = store.lastPlan(before: thisWeek), !last.plannedDays.isEmpty {
                    PlanButton(title: "Same days as last week", filled: false) {
                        store.save(WeeklyPlan(weekStart: thisWeek, plannedDays: last.plannedDays))
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
                .accessibilityHint("Change your training days and times")
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
                        store.save(WeeklyPlan(weekStart: thisWeek, plannedDays: lighter.plannedDays, changes: store.current?.changes ?? []))
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
                        .fill(isDone ? Theme.recoveryHigh : Theme.track)
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
            Text("\(min(sessionsDone, days.count)) of \(days.count) done")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
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
