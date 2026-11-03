import SwiftUI
import SwiftData
import AppCore
import UserNotifications
import os

@main
struct WorkoutAppApp: App {
    @State private var settings = UserSettings()
    @State private var library = ExerciseLibrary()
    @State private var metrics = DailyMetricsModel()
    @State private var biology = BiologyModel()
    @State private var vitals = VitalsModel()
    @State private var coach: CoachModel
    @State private var gym = GymStore()
    @State private var launcher = WorkoutLauncher()
    @State private var refresher: AppRefresher
    @State private var recorder: LiveWorkoutRecorder
    @State private var router: AppRouter
    @State private var medications = MedicationsModel()
    @State private var checkIns = CheckInStore()
    @State private var muscles = MuscleModel()
    @State private var conditions = ConditionsModel()
    @State private var progressPhotos: ProgressPhotosModel
    @State private var labs: LabsModel
    @State private var weeklyPlans = WeeklyPlanStore()
    @State private var measurements = BodyMeasurementsStore()
    private let health: HealthKitClient
    private let container: ModelContainer

    init() {
        let health = HealthKitClient()
        self.health = health
        // Register for Health updates at launch (also when iOS wakes the app in
        // the background after a Garmin sync), so scores and the widget refresh.
        let refresher = AppRefresher()
        _refresher = State(initialValue: refresher)
        if health.isAvailable {
            health.enableBackgroundDelivery()
            health.observeChanges {
                Task { @MainActor in refresher.refreshSoon() }
            }
        }
        _recorder = State(initialValue: LiveWorkoutRecorder(store: health.store))
        // One Claude client (and one signed-in Supabase user) for the coach and photo analysis.
        let cloud = CloudCoach()
        _coach = State(initialValue: CoachModel(cloud: cloud))
        _progressPhotos = State(initialValue: ProgressPhotosModel(cloud: cloud))
        _labs = State(initialValue: LabsModel(cloud: cloud))
        // Notification taps and "Taken" buttons arrive through the router.
        let router = AppRouter()
        _router = State(initialValue: router)
        UNUserNotificationCenter.current().delegate = router
        #if DEBUG
        // Diagnostics: `-openCheckInAtLaunch morning` opens the check-in during
        // launch, the way tapping a notification while the app is closed does.
        if let kind = UserDefaults.standard.string(forKey: "openCheckInAtLaunch"),
           let url = URL(string: "workoutapp://checkin/\(kind)") {
            router.open(url)
        }
        // UI tests: `-scheduleTestCheckIn morning` schedules a real check-in
        // notification 10 seconds from now, the same as the daily reminder.
        if let kind = UserDefaults.standard.string(forKey: "scheduleTestCheckIn") {
            Task { await Reminders.scheduleTestCheckIn(kind: kind) }
        }
        #endif
        Reminders.registerCategories()
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: WorkoutSchemaV2.self),
                migrationPlan: WorkoutMigrationPlan.self
            )
        } catch {
            fatalError("Couldn't open the workout database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(library)
                .environment(metrics)
                .environment(biology)
                .environment(vitals)
                .environment(coach)
                .environment(gym)
                .environment(launcher)
                .environment(refresher)
                .environment(recorder)
                .environment(router)
                .environment(medications)
                .environment(checkIns)
                .environment(muscles)
                .environment(conditions)
                .environment(progressPhotos)
                .environment(labs)
                .environment(weeklyPlans)
                .environment(measurements)
                .environment(\.healthClient, health)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.strain)
        }
        .modelContainer(container)
    }
}

extension EnvironmentValues {
    @Entry var healthClient: HealthKitClient?
}

/// Lets any screen ask for a data refresh (pull to refresh) without owning the logic.
@Observable
final class AppRefresher {
    @ObservationIgnored var perform: (() async -> Void)?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func refresh() async {
        await perform?()
    }

    /// Refreshes shortly, folding bursts of Health updates into one refresh.
    func refreshSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }
}

enum AppTab: Hashable {
    case today, fitness, coach, biology, add
}

struct RootView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(CoachModel.self) private var coach
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(AppRouter.self) private var router
    @Environment(MedicationsModel.self) private var medications
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MuscleModel.self) private var muscles
    @Environment(ConditionsModel.self) private var conditions
    @Environment(ProgressPhotosModel.self) private var progressPhotos
    @Environment(WeeklyPlanStore.self) private var weeklyPlans
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(ExerciseLibrary.self) private var library
    @Environment(GymStore.self) private var gym
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.healthClient) private var health
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var selection: AppTab = .today

    var body: some View {
        @Bindable var launcher = launcher
        @Bindable var router = router
        TabView(selection: $selection) {
            Tab("Home", systemImage: "house", value: AppTab.today) {
                TodayView(askCoach: { question in
                    coach.pendingQuestion = question
                    selection = .coach
                })
            }
            Tab("Fitness", systemImage: "waveform.path.ecg", value: AppTab.fitness) {
                FitnessView()
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                CoachView()
            }
            Tab("Biology", systemImage: "heart", value: AppTab.biology) {
                BiologyView()
            }
            Tab("Add", systemImage: "plus", value: AppTab.add, role: .search) {
                QuickAddView()
            }
        }
        .onOpenURL { url in
            router.open(url)
        }
        .sheet(isPresented: $router.showHRVEntry) {
            HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $router.showMedications) {
            MedicationsView()
        }
        .sheet(isPresented: $router.showProgressPhotos) {
            ProgressPhotosView(runAnalysis: analyzeProgressPhotos)
        }
        .sheet(item: $router.checkIn, onDismiss: scheduleCheckInReminders) { kind in
            CheckInView(kind: kind)
        }
        .modifier(WeeklySheets(router: router))
        .modifier(MeasurementSheets(router: router))
        .sheet(item: $launcher.builderRequest) { request in
            WorkoutBuilderView(initialFocus: request.focus, initialMinutes: request.minutes)
        }
        .fullScreenCover(item: $launcher.activeSession) { session in
            ActiveWorkoutView(session: session)
        }
        .sheet(isPresented: Binding(
            get: { !settings.hasOnboarded },
            set: { if !$0 { settings.hasOnboarded = true } }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            refresher.perform = { await refreshMetrics() }
            // After an update adds new health stats, ask for just those.
            if settings.hasOnboarded && !Self.skipHealthPrompt {
                await health?.requestAuthorizationIfNeeded()
                // Takes effect only once Health access is granted (safe to repeat).
                health?.enableBackgroundDelivery()
            }
            scheduleHRVReminder()
            await refreshMetrics()
            scheduleCheckInReminders() // after the refresh, so the evening reminder carries tonight's bed-by window
            measurements.scheduleReminders() // monthly waist, 6-monthly grip ("measure|waist", "measure|grip")
            await Reminders.scheduleDoses()
            await Reminders.startMedsActivityIfNeeded()
            // Keep today's numbers current while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if scenePhase == .active { await refreshMetrics() }
            }
        }
        .modifier(PendingLinkOpener(router: router))
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                medications.reload()
                Task {
                    await refreshMetrics()
                    scheduleCheckInReminders()
                    await Reminders.scheduleDoses()
                    await Reminders.startMedsActivityIfNeeded()
                }
            }
        }
        // Settings and data changes, in their own modifier so the body stays
        // small enough for the type checker.
        .modifier(SettingsReactions(
            settings: settings, router: router, plans: weeklyPlans.plans,
            finishedSessionCount: finishedSessionCount, hrvValues: hrvReadings.map(\.milliseconds),
            reloadMedications: { medications.reload() },
            openWorkout: { if let active = sessions.first(where: \.isActive) { launcher.activeSession = active } },
            refresh: { Task { await refreshMetrics() } },
            scheduleHRV: scheduleHRVReminder,
            scheduleCheckIns: scheduleCheckInReminders,
            scheduleWorkouts: scheduleWorkoutReminders,
            setRestMode: { metrics.restMode = settings.isRestMode }
        ))
    }

    /// UI tests pass `-skipHealthPrompt YES` to act like a phone that has
    /// already answered the Apple Health permission screen.
    private static var skipHealthPrompt: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "skipHealthPrompt")
        #else
        false
        #endif
    }

    private var finishedSessionCount: Int {
        sessions.filter { !$0.isActive }.count
    }

    var manualHRV: [Date: Double] {
        var result: [Date: Double] = [:]
        for reading in hrvReadings where result[reading.date] == nil {
            result[reading.date] = reading.milliseconds
        }
        return result
    }

    private func refreshMetrics() async {
        guard let health else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: .now) ?? .now
        let recent = sessions
            .filter { !$0.isActive && $0.startedAt >= cutoff }
            .map(\.strainSummary)
        await settings.syncProfile(from: health)
        let goalProtein = settings.goalsSet ? GoalPlanner.proteinPerKg(settings.goals) : 1.6
        metrics.proteinGramsPerKg = max(goalProtein, medications.proteinGramsPerKg ?? 0)
        metrics.medicationProteinPerKg = medications.proteinGramsPerKg
        gym.style = settings.goalsSet ? GoalPlanner.trainingStyle(settings.goals) : .balanced
        metrics.plannedSessionTomorrow = plannedSlots().first { Calendar.current.isDateInTomorrow($0.start) }?.start // bed-by window
        await metrics.refresh(health: health, settings: settings, sessions: recent, manualHRV: manualHRV)
        // Body age uses waist-to-height instead of BMI while a waist reading is under 90 days old (`BodyMeasurementsStore`).
        vitals.waistToHeightRatio = measurements.freshWaistToHeightRatio(heightCm: metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil))
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent,
                             sleepConsistency: metrics.sleepConsistency, sleepSpreadMinutes: metrics.sleepSpreadMinutes)
        checkIns.recordSleepScore(metrics.sleep?.score)
        await conditions.refresh(settings: settings)
        // Hot days (by estimated WBGT) lower the strain target (less once you're heat-acclimatised).
        conditions.heatAcclimation = HeatAdvice.acclimation(hotDays: conditions.hotDays, trainingDays: metrics.recentTrainingDays)
        conditions.heatTrainingDays = conditions.heatAcclimation.heatTrainingDays
        metrics.heatAdjustment = HeatAdvice.targetAdjustment(wbgtC: conditions.forecastWBGT, acclimation: conditions.heatAcclimation)
        // Weekly photo analysis, only if turned on, Claude is set up and it's due.
        // Runs on its own so a slow upload doesn't hold up the rest of the refresh.
        if settings.weeklyPhotoAnalysis, !settings.supabaseURL.isEmpty, !settings.supabaseAnonKey.isEmpty,
           progressPhotos.isAnalysisDue, !progressPhotos.isAnalyzing {
            let context = progressContext()
            Task { await progressPhotos.analyze(context: context, settings: settings) }
        }
        await muscles.refresh(sessions: sessions.filter { !$0.isActive }, library: library, health: health, hrvBelowNormal: metrics.trainEasyToday)
        let todayHRV = hrvReadings.first { Calendar.current.isDateInToday($0.date) }
        Reminders.updateWidget(WidgetSnapshot(
            updated: .now,
            hrv: todayHRV?.milliseconds ?? metrics.hrv,
            hrvDate: (todayHRV != nil || metrics.hrv != nil) ? Calendar.current.startOfDay(for: .now) : nil,
            recovery: metrics.recovery?.score,
            strain: metrics.strain?.strain
        ))
    }

    private func analyzeProgressPhotos() async {
        await progressPhotos.analyze(context: progressContext(), settings: settings)
    }

    /// Goal and data the photo analysis relates the pictures to.
    private func progressContext() -> String {
        var lines: [String] = []
        lines.append("Sex: \(settings.sex.rawValue), age \(settings.age).")
        lines.append(settings.goalsSet ? "Goal: \(settings.goals.title)." : "No goal set.")
        if let weight = metrics.bodyMassKg { lines.append("Weight: \(weight.formatted(.number.precision(.fractionLength(1)))) kg.") }
        if let weekly = metrics.weightTrendWeekly { lines.append("Weight trend: \(weekly.formatted(.number.precision(.fractionLength(2)))) kg/week (last 4 weeks).") }
        if let maintenance = metrics.maintenance {
            lines.append("Average intake \(whole(maintenance.averageIntake)) kcal vs measured maintenance \(whole(maintenance.maintenance)) kcal.")
        }
        if let target = metrics.calorieTarget { lines.append("Calorie target \(whole(target)) kcal/day.") }
        if let protein = metrics.proteinTarget { lines.append("Protein target \(whole(protein)) g/day.") }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let recentSessions = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.count
        lines.append("Gym sessions in the last 2 weeks: \(recentSessions).")
        let weekly = muscles.states.values.filter { $0.weeklySets > 0 }
            .sorted { $0.weeklySets > $1.weeklySets }
            .map { "\($0.muscle.name) \($0.weeklySets.formatted(.number.precision(.fractionLength(0...1))))" }
        if !weekly.isEmpty { lines.append("Hard sets per muscle this week: " + weekly.joined(separator: ", ") + ".") }
        if let fat = vitals.stat("fat")?.value { lines.append("Smart-scale body fat: \(fat)%.") }
        return lines.joined(separator: "\n")
    }

    // MARK: - Reminders: one morning, one evening, workouts before planned slots only

    private func scheduleCheckInReminders() {
        let calendar = Calendar.current
        let enabled = settings.checkInRemindersOn
        let morning = settings.morningCheckInMinutes
        let evening = settings.eveningCheckInMinutes
        let checkedIn = checkIns.morning() != nil
        let eveningDone = checkIns.evening() != nil
        // HRV is "in" from Apple Health or a typed reading. If you never type
        // HRV (none in the last week), the reminder doesn't wait for it.
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let typesHRV = hrvReadings.contains { $0.date >= weekAgo }
        let hrvIn = metrics.hrv != nil || hrvReadings.contains { calendar.isDateInToday($0.date) }
        let hrvMissing = checkedIn && !hrvIn && typesHRV
        let weighIn = weighInNudgeDue
        let bedBy = metrics.bedtimeWindow?.windowText
        Task {
            let nudgeDay = await Reminders.scheduleCheckIns(
                enabled: enabled, morningMinutes: morning, eveningMinutes: evening,
                morningDone: checkedIn, eveningDone: eveningDone,
                hrvMissing: hrvMissing, weighInNudge: weighIn, bedByTonight: bedBy
            )
            if let nudgeDay { settings.weighInNudgeDay = nudgeDay }
        }
        scheduleWorkoutReminders()
    }

    /// The weigh-in line goes on a morning reminder at most once a week, and
    /// only while a lose/gain goal has had no weigh-in for 3+ days (`WeighInNudge`).
    private var weighInNudgeDue: Bool {
        let goals = settings.goalsSet ? settings.goals : nil
        guard WeighInNudge.isDue(goals: goals, lastWeighIn: metrics.lastWeighIn) else { return false }
        guard let last = settings.weighInNudgeDay else { return true }
        let today = Calendar.current.startOfDay(for: .now)
        // Still on a reminder that hasn't fired: keep it. Otherwise wait a week.
        if last >= today { return true }
        return (Calendar.current.dateComponents([.day], from: last, to: today).day ?? 0) >= 7
    }

    /// The separate HRV reminder is folded into the morning check-in; this clears old ones.
    private func scheduleHRVReminder() {
        let loggedToday = hrvReadings.contains { Calendar.current.isDateInToday($0.date) }
        let enabled = settings.hrvReminderOn
        let minutes = settings.hrvReminderMinutes
        Task { await Reminders.scheduleHRV(enabled: enabled, minutes: minutes, loggedToday: loggedToday) }
    }

    /// Planned slots over the next week from the weekly plan (this week's and,
    /// once saved, next week's), as dates.
    private func plannedSlots() -> [Reminders.PlannedSlot] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return (0..<8).compactMap { offset -> Reminders.PlannedSlot? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let planned = weeklyPlans.plan(containing: day)?.day(for: calendar.component(.weekday, from: day)),
                  let start = Reminders.fireDate(day: day, minutes: planned.time, calendar: calendar) else { return nil }
            return Reminders.PlannedSlot(start: start, name: planned.focus.shortTitle, ifThen: planned.ifThen)
        }
    }

    private func scheduleWorkoutReminders() {
        let slots = plannedSlots()
        let enabled = settings.workoutRemindersOn && !settings.isRestMode
        let trained = Set(WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentTrainingDays))
        Task { await Reminders.scheduleWorkoutReminders(slots: slots, enabled: enabled, trainedDays: trained) }
    }
}

/// Opens a tapped notification's link once the app is active (see `AppRouter.pendingLink`).
private struct PendingLinkOpener: ViewModifier {
    let router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                if scenePhase == .active { router.openPendingLink() }
            }
            .onChange(of: router.pendingLink) {
                if scenePhase == .active { router.openPendingLink() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { router.openPendingLink() }
            }
            .onChange(of: router.checkIn) { _, kind in
                Logger.diagnostics.notice("checkIn changed to \(kind?.rawValue ?? "nil", privacy: .public)")
            }
    }
}

/// The weekly loop's sheets: Monday review (workoutapp://review) and this
/// week's plan (workoutapp://plan).
private struct WeeklySheets: ViewModifier {
    let router: AppRouter

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .sheet(isPresented: $router.showWeeklyReview) { WeeklyReviewView() }
            .sheet(isPresented: $router.showWeeklyPlan) { WeeklyPlanView() }
    }
}

/// Body measurements (workoutapp://measurements) and the home blood pressure
/// check (workoutapp://bp), opened from reminders, the "+" tab and Biology.
private struct MeasurementSheets: ViewModifier {
    let router: AppRouter

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .sheet(isPresented: $router.showMeasurements) { BodyMeasurementsView() }
            .sheet(isPresented: $router.showBloodPressure) { BloodPressureView() }
    }
}

/// Reacts to settings and data changes (reminders, refreshes), kept out of
/// `RootView.body` so the compiler can type-check it.
private struct SettingsReactions: ViewModifier {
    let settings: UserSettings
    let router: AppRouter
    let plans: [WeeklyPlan]
    let finishedSessionCount: Int
    let hrvValues: [Double]
    let reloadMedications: () -> Void
    let openWorkout: () -> Void
    let refresh: () -> Void
    let scheduleHRV: () -> Void
    let scheduleCheckIns: () -> Void
    let scheduleWorkouts: () -> Void
    let setRestMode: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(RouterReactions(router: router, reloadMedications: reloadMedications, openWorkout: openWorkout))
            .modifier(ReminderReactions(settings: settings, plans: plans, scheduleHRV: scheduleHRV,
                                        scheduleCheckIns: scheduleCheckIns, scheduleWorkouts: scheduleWorkouts))
            .onChange(of: settings.goals) { refresh() }
            .onChange(of: settings.restModeUntil) { setRestMode() }
            .onChange(of: settings.sleepNeedHours) { refresh() }
            .onChange(of: finishedSessionCount) { refresh() }
            .onChange(of: hrvValues) {
                scheduleCheckIns() // a typed HRV can complete the morning check-in
                refresh()
            }
    }
}

private struct RouterReactions: ViewModifier {
    let router: AppRouter
    let reloadMedications: () -> Void
    let openWorkout: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: router.dosesVersion) { reloadMedications() }
            .onChange(of: router.openWorkout) { openWorkout() }
    }
}

private struct ReminderReactions: ViewModifier {
    let settings: UserSettings
    let plans: [WeeklyPlan]
    let scheduleHRV: () -> Void
    let scheduleCheckIns: () -> Void
    let scheduleWorkouts: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.hrvReminderOn) { scheduleHRV() }
            .onChange(of: settings.hrvReminderMinutes) { scheduleHRV() }
            .onChange(of: settings.checkInRemindersOn) { scheduleCheckIns() }
            .onChange(of: settings.morningCheckInMinutes) { scheduleCheckIns() }
            .onChange(of: settings.eveningCheckInMinutes) { scheduleCheckIns() }
            .onChange(of: settings.workoutRemindersOn) { scheduleWorkouts() }
            .onChange(of: plans) {
                // A saved plan is a fresh commitment: paused workout reminders come back.
                Reminders.resumeWorkoutReminders()
                scheduleWorkouts()
            }
    }
}
