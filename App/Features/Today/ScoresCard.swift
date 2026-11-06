import SwiftUI
import AppCore

/// Today's primary card: the strain, recovery and sleep rings, the coaching
/// line and **one** button chosen by the day's state (docs/research/ux-audit.md
/// 4.2, 4.6). Each ring opens its explanation: Strain › today's range and the
/// sessions that fit, Recovery › what moved it, Sleep › last night and sleep
/// debt. These are quick peeks, so they stay medium-detent sheets (ux-audit.md
/// 4.1 rule 6). "Ask why" opens Coach with the question.
///
/// One primary action per screen, most important first (HIG Layout;
/// ux-audit.md P7, H2); front page first, details on demand (P20).
struct ScoresCard: View {
    let sessions: [WorkoutSession]
    let askCoach: (String) -> Void

    @Environment(WorkoutLauncher.self) private var launcher
    @State private var sheet: TodayScoreSheet?
    /// A builder request from the Strain sheet, opened once the sheet has gone
    /// (only one sheet shows at a time; HIG Sheets).
    @State private var pendingBuilder: WorkoutLauncher.BuilderRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScoreRings(onSelect: { sheet = $0 })
            MinorIllnessLine()
            Divider().overlay(Theme.separator)
            CoachingSection(askCoach: askCoach, workoutRunning: sessions.contains(where: \.isActive))
            ScoresPrimaryButton(sessions: sessions)
        }
        .card()
        .sheet(item: $sheet, onDismiss: { openPendingBuilder() }) { which in
            sheetContent(which)
                .presentationDetents([.medium, .large])
                .presentationBackground(Theme.background)
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: TodayScoreSheet) -> some View {
        switch which {
        case .strain:
            StrainSheet(sessions: sessions, start: { focus, minutes in
                pendingBuilder = WorkoutLauncher.BuilderRequest(focus: focus, minutes: minutes)
                sheet = nil
            })
        case .recovery:
            RecoveryContributorsSheet()
        case .sleep:
            LastNightSleepSheet()
        }
    }

    private func openPendingBuilder() {
        guard let request = pendingBuilder else { return }
        pendingBuilder = nil
        launcher.openBuilder(focus: request.focus, minutes: request.minutes)
    }
}

/// Which ring's explanation is showing.
enum TodayScoreSheet: String, Identifiable {
    case strain, recovery, sleep
    var id: String { rawValue }
}

// MARK: - Rings

/// The three rings. They sit in a row and stack vertically at accessibility
/// text sizes, so the numbers can grow (ux-audit.md 4.8; HIG Typography).
private struct ScoreRings: View {
    let onSelect: (TodayScoreSheet) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Ring size: 100 pt in a row; grows with Dynamic Type once stacked.
    @ScaledMetric(relativeTo: .title) private var scaledRingSize: CGFloat = 100

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let size: CGFloat = stacked ? min(scaledRingSize, 160) : 100
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 20)) : AnyLayout(HStackLayout(alignment: .top))
        layout {
            ringButton(.strain, hint: "Shows today's range and workouts that fit") { strainRing(size: size) }
            ringButton(.recovery, hint: "Shows what moved your recovery") { recoveryRing(size: size) }
            ringButton(.sleep, hint: "Shows last night's sleep and sleep debt") { sleepRing(size: size) }
        }
    }

    private func ringButton<Ring: View>(_ which: TodayScoreSheet, hint: String, @ViewBuilder ring: () -> Ring) -> some View {
        let content = ring()
        return Button { onSelect(which) } label: {
            content
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
        .accessibilityIdentifier("ring-\(which.rawValue)") // UI tests (ScreenshotTests)
    }

    private func strainRing(size: CGFloat) -> some View {
        ScoreRing(
            title: "Strain",
            value: metrics.strain.map { "\(whole($0.strain))" } ?? "--",
            unit: metrics.strain == nil ? "" : "%",
            subtitle: strainSubtitle,
            progress: (metrics.strain?.strain ?? 0) / StrainCalculator.maximum,
            colors: Theme.strainColors,
            size: size
        )
    }

    /// "Rest day · up to 25%" on the plan's rest days, else "Range 50–70%".
    private var strainSubtitle: String {
        guard let target = metrics.targetStrain else { return "Day strain" }
        if metrics.dayGuidance?.isRestDay == true {
            return "Rest day · up to \(whole(target.upperBound))%"
        }
        return "Range \(strainRangeText(target))"
    }

    private func recoveryRing(size: CGFloat) -> some View {
        ScoreRing(
            title: "Recovery",
            value: metrics.recovery.map { "\($0.score)" } ?? "--",
            unit: metrics.recovery == nil ? "" : "%",
            subtitle: recoverySubtitle,
            progress: Double(metrics.recovery?.score ?? 0) / 100,
            colors: RecoveryWording.colors(for: metrics.recovery?.status),
            size: size
        )
    }

    private var recoverySubtitle: String? {
        metrics.recovery.map { result in
            if let note = metrics.recoveryNote { return note }
            guard !result.isCalibrated else { return RecoveryWording.label(for: result.status) }
            let left = max(1, RecoveryCalculator().minimumBaselineDays - (metrics.baseline?.nights ?? 0))
            return "Learning · \(left) more night\(left == 1 ? "" : "s")"
        }
    }

    private func sleepRing(size: CGFloat) -> some View {
        ScoreRing(
            title: "Sleep",
            value: metrics.sleep.map { "\($0.score)" } ?? "--",
            unit: "",
            subtitle: metrics.sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            progress: Double(metrics.sleep?.score ?? 0) / 100,
            colors: Theme.sleepColors,
            size: size
        )
    }
}

// MARK: - Coaching

/// The coaching line, this morning's check-in advice, and "Ask why".
private struct CoachingSection: View {
    let askCoach: (String) -> Void
    /// A workout is in progress: the line says so instead of offering another.
    var workoutRunning = false

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns

    /// What "Ask why" sends to Coach.
    private static let question = "How should I train today, and why?"

    var body: some View {
        let coaching: (text: String, highlight: String?) = workoutRunning
            ? ("Workout in progress. Resume it below.", nil)
            : TrainerSuggestions.coachingLine(metrics: metrics)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Label("Coaching", systemImage: "sparkle")
                    .font(Theme.Typography.cardLabel)
                    .textCase(.uppercase)
                    .tracking(Theme.Typography.cardLabelTracking)
                    .foregroundStyle(Theme.strainTextColor)
                Spacer(minLength: 8)
                Button("Ask why") { askCoach(Self.question) }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.strainTextColor)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                    .accessibilityHint("Opens Coach with this question")
            }
            coachingText(coaching)
            if let advice = checkIns.advice {
                // From this morning's check-in (`CheckInCoaching`).
                Text(advice)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func coachingText(_ coaching: (text: String, highlight: String?)) -> some View {
        if let highlight = coaching.highlight {
            let lead = Text(coaching.text).foregroundStyle(Theme.primaryText)
            let accent = Text(highlight).foregroundStyle(Theme.strainTextColor).fontWeight(.semibold)
            Text("\(lead) \(accent)")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        } else if !coaching.text.isEmpty {
            Text(coaching.text)
                .font(.body)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The one button

/// One button chosen by state (ux-audit.md 4.6): "Start Push · 45 min" when a
/// session is planned today and not done yet ("Start Push (short) · 15 min" on
/// an easy day); on a rest or recovery day the plan's guidance wins, so a
/// planned session only gets a quiet "Train anyway" option; "Start workout"
/// when today is below its range, nothing is planned and you haven't trained;
/// otherwise none. Nothing in rest mode, which pauses workout nudges. The full choice
/// (short version, other sessions) stays in the Strain sheet and Fitness ›
/// This week.
private struct ScoresPrimaryButton: View {
    let sessions: [WorkoutSession]

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles
    @Environment(WorkoutLauncher.self) private var launcher

    private struct Choice {
        var title: String
        var focus: WorkoutFocus?
        var minutes: Int?
        /// A quiet option (rest and recovery days), not the main call to action.
        var secondary = false
    }

    var body: some View {
        if let running = sessions.first(where: \.isActive) {
            // A workout in progress: resume it, never a second one (`WorkoutLauncher.running`).
            ResumeWorkoutButton(session: running) { launcher.activeSession = running }
        } else if let choice {
            Button {
                launcher.openBuilder(focus: choice.focus, minutes: choice.minutes)
            } label: {
                Label(choice.title, systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(choice.secondary ? Theme.strainTextColor : Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.horizontal, 12)
                    .background(Self.fill(secondary: choice.secondary), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the workout builder")
        }
    }

    private static func fill(secondary: Bool) -> AnyShapeStyle {
        secondary
            ? AnyShapeStyle(Theme.cardRaised)
            : AnyShapeStyle(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing))
    }

    /// "Start Push · 45 min", or the short version on an easy day.
    private static func start(_ day: PlannedDay, short: Bool) -> Choice {
        let minutes = short ? min(day.shortVersionMinutes, day.minutes) : day.minutes
        let name = short ? day.focus.shortTitle + " (short)" : day.focus.shortTitle
        return Choice(title: "Start \(name) · \(minutes) min", focus: day.focus, minutes: minutes)
    }

    private var choice: Choice? {
        guard !metrics.restMode else { return nil }
        // The plan's rest or recovery day comes first (`TrainingDayPlanner`): a
        // session still planned today is only a quiet, short "Train anyway".
        if metrics.dayGuidance?.isRestDay == true {
            guard let planned = plannedToday else { return nil }
            let minutes = min(planned.shortVersionMinutes, planned.minutes)
            let name = planned.focus.shortTitle
            return Choice(title: "Train anyway · \(name) (short) · \(minutes) min", focus: planned.focus, minutes: minutes, secondary: true)
        }
        let short = metrics.dayGuidance?.kind == .easyTraining
        if let planned = plannedToday {
            return Self.start(planned, short: short)
        }
        // A flexible week (`WeeklyPlan.Mode.flexible`): the next session, with the coverage rule's focus.
        if let next = flexibleNext {
            return Self.start(next, short: short)
        }
        // A session missed in the last two days moved to today (`TrainingDayPlanner`).
        if let guidance = metrics.dayGuidance, guidance.kind == .makeUp, let focus = guidance.focus,
           metrics.activities.isEmpty {
            return Choice(title: "Start \(focus.shortTitle) (moved)", focus: focus, minutes: nil)
        }
        guard metrics.activities.isEmpty, let target = metrics.targetStrain else { return nil }
        let status = StrainPlanner().status(current: metrics.strain?.strain ?? 0, target: target)
        guard case .below = status else { return nil }
        let strength = TrainerSuggestions.make(metrics: metrics, settings: settings, sessions: sessions)
            .first { $0.option.kind == .strength }
        return Choice(title: "Start workout", focus: strength?.focus, minutes: strength?.minutes)
    }

    /// In a flexible week, the session to do next (`WeeklyPlanStore.nextSession`:
    /// focus from `MuscleCoverage`), unless the quota is met, a session was
    /// logged today, or today's guidance is a rest day. On an easy day the
    /// button offers the short version (`start(_:short:)`).
    private var flexibleNext: PlannedDay? {
        guard plans.current?.isFlexible == true, metrics.activities.isEmpty,
              metrics.dayGuidance?.isRestDay != true,
              let progress = plans.progress(sessions: sessions, extra: metrics.recentTrainingDays), !progress.trainedToday,
              let next = plans.nextSession(sessions: sessions, extra: metrics.recentTrainingDays, muscles: muscles) else { return nil }
        return next.day
    }

    /// Today's planned session from this week's plan, unless a session was
    /// already logged today (as on the This week card).
    private var plannedToday: PlannedDay? {
        guard let today = plans.todayPlan() else { return nil }
        let weekday = Calendar.current.component(.weekday, from: .now)
        let done = plans.doneWeekdays(sessions: sessions, extra: metrics.recentTrainingDays)
        return done.contains(weekday) ? nil : today
    }
}

/// "Resume Upper Body · 1:11" while a workout runs: the one button goes back
/// to it instead of offering a second start.
private struct ResumeWorkoutButton: View {
    let session: WorkoutSession
    let resume: () -> Void

    var body: some View {
        Button(action: resume) {
            TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                let elapsed = workoutElapsedText(context.date.timeIntervalSince(session.startedAt))
                Label("Resume \(session.name) · \(elapsed)", systemImage: "play.fill")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.horizontal, 12)
                    .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing),
                                in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the workout in progress")
    }
}
