import SwiftUI
import SwiftData
import AppCore

/// Today's "Up next": at most four small things to do, ordered by time of
/// day, each with an icon, one line and a trailing action; hidden when there's
/// nothing. It replaces the daily check-in, medications, sleep debt and daily
/// habits cards, which each took a full card (docs/research/ux-audit.md 4.3,
/// 4.6, H1, H2; HIG Layout: most important first, group related items, P7).
///
/// Rows: morning and evening check-in (until done), medication doses due
/// (with Take), the caffeine cut-off, the day's movement nudge, a weigh-in
/// reminder, the breathing offer and tonight's bed-by window. Today's planned
/// session is the Scores card's button, so it isn't repeated here; once today
/// is done or a rest day, the week's next session shows ("Next: Lower · 60
/// min", from the queue in `AdaptiveWeek`), and a session that wasn't the one
/// suggested asks why once (`SwapQuestionButton`).
struct UpNextCard: View {
    let habits: TodayHabits

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MedicationsModel.self) private var meds
    // Builder B: for the hypertension-notification row (watch-features.md 1.1).
    @Environment(VitalsModel.self) private var vitals
    // Easy cardio from the weekly plan (`CardioPlanner`).
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles
    // The week's queue (`AdaptiveWeek`) needs the logged sessions.
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    /// Most rows shown at once (ux-audit.md 4.6).
    private static let maximumRows = 4

    var body: some View {
        let items = Self.keepingCardio(upNextItems())
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(text: "Up next")
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    UpNextItemRow(item: item)
                }
            }
            .card()
        }
    }

    // MARK: Building the rows

    private func upNextItems() -> [UpNextItem] {
        let now = Self.minutesNow()
        var items: [UpNextItem] = []
        items += checkInItems(now: now)
        items += doseItems()
        if let caffeine = caffeineItem(now: now) { items.append(caffeine) }
        if let nudge = habits.movementNudge { items.append(movementItem(nudge, now: now)) }
        if WeighInNudge.isDue(goals: metrics.goals, lastWeighIn: metrics.lastWeighIn) {
            // Lose/gain goal with no weigh-in for 3+ days (`WeighInNudge`: Zheng 2015; Madigan 2015).
            items.append(UpNextItem(id: "weighin", minutes: settings.morningCheckInMinutes, kind: .info(
                icon: "scalemass", color: Theme.nutrition, title: WeighInNudge.title,
                detail: WeighInNudge.detail(lastWeighIn: metrics.lastWeighIn))))
        }
        if BreathingOfferRow.isOffered(metrics: metrics, checkIns: checkIns) {
            items.append(UpNextItem(id: "breathing", minutes: now, kind: .breathing))
        }
        if let bedtime = bedtimeItem() { items.append(bedtime) }
        if let cardio = cardioItem(now: now) { items.append(cardio) }
        items += weekQueueItems(now: now)
        // Builder B: the watch flagged possible hypertension and no 7-day home
        // check has been done since (`HomeBloodPressure.pendingHypertensionEvent`;
        // Apple's validation: sensitivity 41%, specificity 92%, watch-features.md 1.1).
        if let flagged = vitals.hypertensionPromptDate {
            items.append(UpNextItem(id: "bp-check", minutes: settings.morningCheckInMinutes, kind: .bloodPressure(flagged)))
        }
        return items.sorted { $0.minutes < $1.minutes }
    }

    /// Morning check-in until it's done; the evening one from noon until it's done.
    private func checkInItems(now: Int) -> [UpNextItem] {
        var items: [UpNextItem] = []
        if checkIns.morning() == nil {
            items.append(UpNextItem(id: "checkin-morning", minutes: settings.morningCheckInMinutes, kind: .checkIn(.morning)))
        }
        if checkIns.evening() == nil, now >= 12 * 60 {
            items.append(UpNextItem(id: "checkin-evening", minutes: settings.eveningCheckInMinutes, kind: .checkIn(.evening)))
        }
        return items
    }

    /// Today's doses that are due (their time has come) and not taken yet.
    /// The full list is in Health › Records › Medications (also the Log tab and Settings).
    private func doseItems() -> [UpNextItem] {
        meds.todayDoses
            .filter { !meds.isTaken($0) && $0.time <= .now }
            .map { UpNextItem(id: "dose-\($0.id)", minutes: $0.minutes, kind: .dose($0)) }
    }

    /// The caffeine cut-off before it passes, or a warning when today's last
    /// caffeine was late (`CaffeineTiming`).
    private func caffeineItem(now: Int) -> UpNextItem? {
        let caffeine = habits.caffeine(metrics: metrics, checkIns: checkIns, trainingMinutes: plans.todayPlan()?.time)
        guard caffeine.isLate || now < caffeine.cutoffMinutes else { return nil }
        return UpNextItem(id: "caffeine", minutes: caffeine.cutoffMinutes, kind: .info(
            icon: "cup.and.saucer.fill",
            color: caffeine.isLate ? Theme.recoveryModerate : Theme.sleep,
            title: caffeine.title,
            detail: caffeine.detail))
    }

    /// At most one nudge a day (`MovementBreaks`; Buffey 2022; Dunstan 2012).
    private func movementItem(_ nudge: MovementBreaks.Nudge, now: Int) -> UpNextItem {
        switch nudge {
        case .postMealWalk:
            UpNextItem(id: "movement", minutes: now, kind: .info(
                icon: "figure.walk", color: Theme.strain,
                title: MovementBreaks.postMealTitle, detail: MovementBreaks.postMealDetail))
        case .sedentary(let hours):
            UpNextItem(id: "movement", minutes: now, kind: .info(
                icon: "figure.walk.motion", color: Theme.strain,
                title: MovementBreaks.sedentaryTitle, detail: MovementBreaks.sedentaryDetail(hours: hours)))
        }
    }

    /// Tonight's bed-by window while there's sleep debt (`BedtimeWindow`: the
    /// wake time stays put, Windred et al., Sleep 2024, and repayment comes
    /// from going to bed earlier). Opens last night's sheet with the debt.
    private func bedtimeItem() -> UpNextItem? {
        guard let debt = metrics.sleepDebt, debt.level != .none, let window = metrics.bedtimeWindow else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: window.start)
        var minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A window after midnight still comes last today.
        if minutes < 12 * 60 { minutes += 24 * 60 }
        return UpNextItem(id: "bedtime", minutes: minutes, kind: .bedtime(
            title: "In bed by \(window.windowText) tonight",
            detail: "Sleep debt \(SleepText.hours(debt.hours))"))
    }

    /// The weekly plan's easy cardio on its day (any day in a flexible week)
    /// until a workout of that type is in Apple Health (`CardioPlanner.today`):
    /// the 15-minute version on a low-recovery day, nothing after a heavy leg
    /// session when strength is a goal (Schumann 2022).
    private func cardioItem(now: Int) -> UpNextItem? {
        let slots = plans.cardioSlots(goals: metrics.goals)
        guard let kind = slots.first?.kind else { return nil }
        let workouts = WeeklyPlanStore.cardioWorkouts(muscles: muscles, metrics: metrics)
        let calendar = Calendar.current
        let doneToday = CardioPlanner.doneDays(kind: kind, workouts: workouts, weekStart: WeeklyPlan.weekStart(containing: .now))
            .contains(calendar.startOfDay(for: .now))
        let heavyLowerToday = muscles.loggedSets.contains { set in
            calendar.isDateInToday(set.sessionStart) && set.isCompound && set.primary.contains(where: \.isLowerBody)
        }
        let lowRecovery = (metrics.recovery?.score ?? 100) < 34 || metrics.trainEasyToday
        guard let today = CardioPlanner.today(
            slots: slots, doneSlots: plans.cardioDone(slots: slots, workouts: workouts), doneToday: doneToday,
            weekday: calendar.component(.weekday, from: .now), goals: metrics.goals, lowRecovery: lowRecovery,
            liftedHeavyLowerToday: heavyLowerToday, strainRange: metrics.targetStrain
        ) else { return nil }
        return UpNextItem(id: "cardio", minutes: now, kind: .info(
            icon: today.kind.systemImage, color: Theme.oxygen, title: today.title, detail: today.detail))
    }

    /// A fixed week's queue (`AdaptiveWeek`): "Why the switch?" after a session
    /// that wasn't the suggested one (asked once), and the next session once
    /// today has none left ("Next: Lower · 60 min", tomorrow, with any soreness note).
    private func weekQueueItems(now: Int) -> [UpNextItem] {
        guard !metrics.restMode, plans.current?.isFlexible == false,
              let week = plans.adaptiveWeek(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns, muscles: muscles)
        else { return [] }
        var items: [UpNextItem] = []
        if let swap = plans.unansweredSwap(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns) {
            items.append(UpNextItem(id: "swap-why", minutes: now, kind: .swapQuestion(planned: swap.planned, chosen: swap.chosen)))
        }
        if week.today == nil, let next = week.next, let label = week.nextLabel {
            let when = Self.dayWord(next.date)
            let detail = next.note.map { "\(when) · \($0)" } ?? when
            items.append(UpNextItem(id: "next-session", minutes: now, kind: .info(
                icon: "dumbbell.fill", color: Theme.lifting, title: label, detail: detail)))
        } else if week.today == nil, let note = week.stillToDoNote {
            items.append(UpNextItem(id: "next-session", minutes: now, kind: .info(
                icon: "calendar", color: Theme.lifting, title: "Still to do this week", detail: note)))
        }
        return items
    }

    /// "Tomorrow", or the weekday ("Thursday").
    private static func dayWord(_ date: Date) -> String {
        Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide))
    }

    /// The first `maximumRows` rows, but the day's easy cardio isn't cut by
    /// the cap: it takes the place of the last row that isn't a dose or a
    /// blood-pressure check (rows are by time, so it still comes last).
    private static func keepingCardio(_ all: [UpNextItem]) -> [UpNextItem] {
        var shown = Array(all.prefix(maximumRows))
        guard let cardio = all.first(where: { $0.id == "cardio" }),
              !shown.contains(where: { $0.id == "cardio" }),
              let index = shown.lastIndex(where: { item in
                  switch item.kind {
                  case .dose, .bloodPressure: false
                  default: true
                  }
              }) else { return shown }
        shown.remove(at: index)
        shown.append(cardio)
        return shown
    }

    private static func minutesNow() -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// One Up next row's content.
private struct UpNextItem: Identifiable {
    enum Kind {
        case checkIn(CheckInKind)
        case dose(Dose)
        case breathing
        case bedtime(title: String, detail: String)
        /// Advice with no action, e.g. the caffeine cut-off.
        case info(icon: String, color: Color, title: String, detail: String?)
        /// Builder B: a watch hypertension notification waiting for the 7-day home check.
        case bloodPressure(Date)
        /// A session that wasn't the suggested one: ask why once (`SwapQuestionButton`).
        case swapQuestion(planned: WorkoutFocus, chosen: WorkoutFocus)
    }

    let id: String
    /// When it's due, in minutes after midnight (the sort order).
    let minutes: Int
    let kind: Kind
}

// MARK: - Rows

private struct UpNextItemRow: View {
    let item: UpNextItem

    var body: some View {
        switch item.kind {
        case .checkIn(let kind):
            CheckInUpNextRow(kind: kind)
        case .dose(let dose):
            DoseUpNextRow(dose: dose)
        case .breathing:
            BreathingOfferRow()
        case .bedtime(let title, let detail):
            BedtimeUpNextRow(title: title, detail: detail)
        case .info(let icon, let color, let title, let detail):
            UpNextRow(icon: icon, color: color, title: title, detail: detail)
                .accessibilityElement(children: .combine)
        case .bloodPressure(let flagged):
            BloodPressureUpNextRow(flagged: flagged)
        case .swapQuestion(let planned, let chosen):
            SwapQuestionButton(planned: planned, chosen: chosen)
        }
    }
}

/// Builder B: opens the blood pressure sheet (`AppRouter.showBloodPressure`)
/// after an Apple Watch hypertension notification (watch-features.md 1.1).
private struct BloodPressureUpNextRow: View {
    let flagged: Date
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button { router.showBloodPressure = true } label: {
            UpNextRow(
                icon: "heart.text.square.fill",
                color: Theme.heart,
                title: "7-day blood pressure check",
                detail: "Your watch flagged possible high blood pressure on \(flagged.formatted(date: .abbreviated, time: .omitted))"
            ) {
                UpNextChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the blood pressure log")
    }
}

private struct CheckInUpNextRow: View {
    let kind: CheckInKind
    @Environment(AppRouter.self) private var router

    var body: some View {
        let isMorning = kind == .morning
        Button { router.checkIn = kind } label: {
            UpNextRow(
                icon: isMorning ? "sun.max.fill" : "moon.stars.fill",
                color: Theme.secondaryText,
                title: isMorning ? "Morning check-in · 1 min" : "Evening check-in · 1 min",
                detail: isMorning ? "How you slept and how you feel" : "Caffeine, drinks and how the day went"
            ) {
                UpNextChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the check-in")
    }
}

/// A dose that's due, with Take (the full list with undo is in Medications).
private struct DoseUpNextRow: View {
    let dose: Dose
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        UpNextRow(
            icon: "pills.fill",
            color: Theme.secondaryText,
            title: dose.name,
            detail: [dose.dose, dose.time.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · ")
        ) {
            Button("Take") { meds.toggle(dose) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityLabel("Take \(dose.name)")
        }
    }
}

private struct BedtimeUpNextRow: View {
    let title: String
    let detail: String
    @State private var showingSleep = false

    var body: some View {
        Button { showingSleep = true } label: {
            UpNextRow(icon: "bed.double.fill", color: Theme.sleep, title: title, detail: detail) {
                UpNextChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows last night's sleep and your sleep debt")
        .sheet(isPresented: $showingSleep) {
            LastNightSleepSheet()
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
    }
}

/// The row layout: icon, a line (and an optional detail), then a trailing
/// action or chevron. At least 44 pt tall (HIG Accessibility; ux-audit.md P23).
private struct UpNextRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String?
    let trailing: Trailing

    init(icon: String, color: Color, title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.color = color
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(systemName: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

extension UpNextRow where Trailing == EmptyView {
    /// A row with nothing trailing (advice only).
    init(icon: String, color: Color, title: String, detail: String? = nil) {
        self.init(icon: icon, color: color, title: title, detail: detail) { EmptyView() }
    }
}

/// The trailing chevron of a row that opens something.
private struct UpNextChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}
