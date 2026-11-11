import SwiftUI
import SwiftData
import UIKit
import AppCore
import UserNotifications
import os

@main
struct WorkoutAppApp: App {
    /// `-demoData YES` in the Simulator: reset and fill the stores before they load (`DemoData`). First on purpose.
    private let demoMode = DemoData.prepare()
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
    @State private var checkIns: CheckInStore
    @State private var muscles = MuscleModel()
    @State private var conditions = ConditionsModel()
    @State private var progressPhotos: ProgressPhotosModel
    @State private var labs: LabsModel
    @State private var weeklyPlans: WeeklyPlanStore
    @State private var measurements: BodyMeasurementsStore
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
            // HealthKit's completion waits for this, so a background wake gets its refresh first.
            health.observeChanges {
                await refresher.healthDidChange()
            }
        }
        _recorder = State(initialValue: LiveWorkoutRecorder(store: health.store))
        _coach = State(initialValue: CoachModel())
        // JSON stores. A launch in the background while the phone is locked may
        // find a file it can't read yet; each store then saves nothing until it
        // has read it, and reads again once the phone is unlocked (`SafeJSONFile`).
        let progressPhotos = ProgressPhotosModel()
        let labs = LabsModel()
        let checkIns = CheckInStore()
        let weeklyPlans = WeeklyPlanStore()
        let measurements = BodyMeasurementsStore()
        _progressPhotos = State(initialValue: progressPhotos)
        _labs = State(initialValue: labs)
        _checkIns = State(initialValue: checkIns)
        _weeklyPlans = State(initialValue: weeklyPlans)
        _measurements = State(initialValue: measurements)
        _ = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                progressPhotos.reloadIfUnavailable()
                labs.reloadIfUnavailable()
                checkIns.reloadIfUnavailable()
                weeklyPlans.reloadIfUnavailable()
                measurements.reloadIfUnavailable()
                NextBlockStore.shared.reloadIfUnavailable()
                MuscleFeedbackStore.shared.reloadIfUnavailable()
            }
        }
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
                for: Schema(versionedSchema: WorkoutSchemaV4.self),
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
        .modelContainer(demoMode ? DemoData.container : container)
        .backgroundTask(.appRefresh(CoachNotificationIDs.refreshTask)) { await CoachNudges.backgroundRefresh() }
    }
}

extension EnvironmentValues {
    @Entry var healthClient: HealthKitClient?
}

/// Lets any screen ask for a data refresh (pull to refresh) without owning the logic.
/// One refresh runs at a time: asking while one runs queues a single extra
/// pass after it (so it sees the newest data) and waits for that.
@Observable
final class AppRefresher {
    @ObservationIgnored var perform: (() async -> Void)?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var again = false

    func refresh() async {
        if let running {
            again = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                again = false
                await perform?()
            } while again
            running = nil
        }
        running = task
        await task.value
    }

    /// New data in Apple Health. In a background wake the refresh runs now,
    /// and HealthKit's completion waits for it; in the foreground, bursts of
    /// updates fold into one refresh shortly after.
    func healthDidChange() async {
        if UIApplication.shared.applicationState == .background {
            await refresh()
        } else {
            refreshSoon()
        }
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
    case today, fitness, coach, health, log
}

struct RootView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(CoachModel.self) private var coach
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(BiologyModel.self) private var biology
    @Environment(AppRouter.self) private var router
    @Environment(MedicationsModel.self) private var medications
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MuscleModel.self) private var muscles
    @Environment(ConditionsModel.self) private var conditions
    @Environment(WeeklyPlanStore.self) private var weeklyPlans
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(LabsModel.self) private var labs
    @Environment(ProgressPhotosModel.self) private var progressPhotos
    @Environment(ExerciseLibrary.self) private var library
    @Environment(GymStore.self) private var gym
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.healthClient) private var health
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]

    var body: some View {
        @Bindable var launcher = launcher
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Today", systemImage: "house", value: AppTab.today) {
                TodayView(askCoach: { question in
                    coach.pendingQuestion = question
                    router.selectedTab = .coach
                })
            }
            Tab("Fitness", systemImage: "waveform.path.ecg", value: AppTab.fitness) {
                FitnessView()
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                CoachView()
            }
            Tab("Health", systemImage: "heart.text.square", value: AppTab.health) {
                HealthView()
            }
            // An ordinary tab, not `role: .search`: that trailing slot is for
            // search (HIG *Tab bars*; docs/research/ux-audit.md, Decisions).
            Tab("Log", systemImage: "plus.circle", value: AppTab.log) {
                LogView()
            }
        }
        // A workout in progress, above the tab bar on every tab (ux-audit 4.1 rule 4).
        .modifier(ActiveWorkoutAccessory(
            session: sessions.first(where: \.isActive),
            resume: { if let active = sessions.first(where: \.isActive) { launcher.activeSession = active } }
        ))
        // Every start resumes a workout in progress instead of a second one (`WorkoutLauncher.running`).
        .onChange(of: sessions.first(where: \.isActive)?.persistentModelID, initial: true) { _, _ in
            launcher.running = sessions.first(where: \.isActive)
        }
        .onOpenURL { url in
            router.open(url)
        }
        .sheet(isPresented: $router.showHRVEntry) {
            HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $router.showMedications) {
            MedicationsView()
        }
        .sheet(isPresented: $router.showProgressPhotos) {
            ProgressPhotosView()
        }
        .sheet(item: $router.checkIn, onDismiss: scheduleCheckInReminders) { kind in
            CheckInView(kind: kind)
        }
        .modifier(WeeklySheets(router: router))
        .modifier(BlockReportCover()) // the finished block's report, once, when the next block starts
        .modifier(MeasurementSheets(router: router))
        .modifier(SettingsSheet(router: router))
        .sheet(item: $launcher.builderRequest) { request in
            WorkoutBuilderView(initialFocus: request.focus, initialMinutes: request.minutes)
        }
        .fullScreenCover(item: $launcher.activeSession, onDismiss: { WorkoutSummaryPresenter.shared.showPending() }) { session in
            ActiveWorkoutView(session: session)
        }
        .modifier(WorkoutSummaryCover()) // the summary after Finish (`WorkoutSummaryPresenter`)
        .sheet(isPresented: Binding(
            get: { !settings.hasOnboarded },
            set: { if !$0 { settings.hasOnboarded = true } }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .task {
            refresher.perform = { await refreshMetrics() }
            CoachNudges.shared.attach(metrics: metrics, plans: weeklyPlans, checkIns: checkIns, settings: settings, gym: gym,
                                      muscles: muscles, context: modelContext, refresher: refresher)
            Reminders.clearLegacyHRVReminders()
            // Scores first, from what Apple Health already shares. Only then, after an
            // update adds new health stats, ask for just those: the permission sheet waits
            // for an answer, and asking before the first refresh left every screen at
            // zero until it was dismissed. A second refresh picks up the new types.
            await refresher.refresh()
            if settings.hasOnboarded && !Self.skipHealthPrompt {
                // A new answer also restarts the Health observers (`HealthKitClient.accessChanged`).
                if await health?.requestAuthorizationIfNeeded() == true {
                    await refresher.refresh()
                }
                // Takes effect only once Health access is granted (safe to repeat).
                health?.enableBackgroundDelivery()
            }
            scheduleCheckInReminders() // after the refresh, so the evening reminder carries tonight's bed-by window
            measurements.scheduleReminders() // monthly waist, 6-monthly grip ("measure|waist", "measure|grip")
            await Reminders.scheduleDoses()
            await Reminders.startMedsActivityIfNeeded()
            // Medications Apple Health knows about (read-only merge; off unless the build enables the API).
            if let health { await medications.importFromHealth(health) }
            // Keep today's numbers current while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if scenePhase == .active { await refresher.refresh() }
            }
        }
        .modifier(PendingLinkOpener(router: router))
        .modifier(WatchSyncBootstrap()) // Apple Watch app (`WatchSync`)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                medications.reload()
                reloadUnreadStores()
                Task {
                    await refresher.refresh()
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
            refresh: { Task { await refresher.refresh() } },
            scheduleCheckIns: scheduleCheckInReminders,
            scheduleWorkouts: scheduleWorkoutReminders,
            setRestMode: { metrics.restMode = settings.isRestMode },
            markBiologyStale: { biology.markStale() }
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

    /// Stores whose file couldn't be read at launch (phone locked) read it now.
    private func reloadUnreadStores() {
        labs.reloadIfUnavailable()
        progressPhotos.reloadIfUnavailable()
        checkIns.reloadIfUnavailable()
        weeklyPlans.reloadIfUnavailable()
        measurements.reloadIfUnavailable()
        NextBlockStore.shared.reloadIfUnavailable()
        MuscleFeedbackStore.shared.reloadIfUnavailable()
    }

    private var finishedSessionCount: Int {
        sessions.filter { !$0.isActive }.count
    }

    /// Typed-in overnight HRV (Garmin RMSSD), keyed by the start of its morning,
    /// one per day (the newest: `hrvReadings` is newest first). Camera readings
    /// are morning values and go separately (`cameraHRV`, `DailyVitals.resolvingHRV`).
    var manualHRV: [Date: Double] { Self.hrvByMorning(hrvReadings, camera: false) }

    var cameraHRV: [Date: Double] { Self.hrvByMorning(hrvReadings, camera: true) }

    static func hrvByMorning(_ readings: [HRVReading], camera: Bool) -> [Date: Double] {
        let calendar = Calendar.current
        var result: [Date: Double] = [:]
        for reading in readings where (reading.source == "Camera") == camera {
            let morning = calendar.startOfDay(for: reading.date)
            if result[morning] == nil { result[morning] = reading.milliseconds }
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
        // The plan's last 8 days and today, so rest days aim low and missed sessions move (`TrainingDayPlanner`).
        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: .now)
            var byDay: [Date: WorkoutFocus] = [:]
            var fixedDays: Set<Date> = [] // weeks with a fixed-day plan (not none, not flexible)
            for offset in -8...0 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if let plan = weeklyPlans.plan(containing: day), !plan.isFlexible { fixedDays.insert(day) }
                guard let planned = weeklyPlans.todayPlan(now: day) else { continue }
                byDay[day] = planned.focus
            }
            metrics.plannedFocusByDay = byDay
            metrics.fixedPlanDays = fixedDays
            metrics.loggedSessionDays = Set(WeeklyPlanStore.trainingDays(sessions: sessions))
            metrics.hasWeeklyPlan = !(weeklyPlans.current?.plannedDays.isEmpty ?? true)
            // Flexible week (WeeklyPlanStore builder): quota progress and the coverage rule's next focus.
            if weeklyPlans.current?.isFlexible == true {
                metrics.flexibleWeek = weeklyPlans.progress(sessions: sessions, extra: metrics.recentTrainingDays)
                metrics.flexibleNextFocus = weeklyPlans.nextSession(sessions: sessions, extra: metrics.recentTrainingDays, muscles: muscles)?.day.focus
            } else {
                metrics.flexibleWeek = nil
                metrics.flexibleNextFocus = nil
            }
        }
        // Personal calories (docs/research/calories.md): training status from the whole lifting log.
        metrics.trainingStatus = TrainingStatus.resolve(reported: settings.liftingExperience, sessionDates: sessions.filter { !$0.isActive }.map(\.startedAt))
        // The direct Oura link first (at most every 30 minutes), so last night's ring
        // sleep and HRV are there for the scores (`OuraLink`, `SleepSourceSetting`).
        await OuraLink.shared.syncIfDue()
        await metrics.refresh(health: health, settings: settings, sessions: recent, manualHRV: manualHRV, morningHRV: cameraHRV)
        // Training block (`TrainingBlock`): the trainer's style from the goals, then this week's
        // state; a week that starts with 7-day HRV below normal holds the ramp instead of adding sets.
        // Only once recovery is known: a refresh that couldn't read Health (locked phone)
        // would otherwise move the block on with "HRV normal" and latch it for the week.
        weeklyPlans.trainingStyle = gym.style
        weeklyPlans.gym = gym.profile
        if metrics.recovery != nil {
            weeklyPlans.refreshBlock(hrvBelowNormal: metrics.trainEasyToday)
        }
        // Changes applied from a block report end with the block they were for (`NextBlockStore`).
        NextBlockStore.shared.observe(blockStart: weeklyPlans.block?.start)
        checkIns.recordSleepScore(metrics.sleep?.score)
        // Mood patterns (builder A): each day's strain, your usual training strain and sleep need.
        checkIns.recordContext(dayStrains: metrics.weekStrain.map { (date: $0.date, strain: $0.strain) },
                               usualTrainingStrain: metrics.usualTrainingStrain, sleepNeedHours: settings.sleepNeedHours)
        // The widget straight after the scores, never waiting on the weather or the muscles.
        updateWidget()
        // A background wake (new Health data while the app is closed) stops here:
        // today's scores, the widget and the watch face. The rest waits for the app.
        guard UIApplication.shared.applicationState != .background else {
            updateWatchFace()
            // Rewrite the coach's morning message with last night's recovery (`CoachNudges`).
            await CoachNudges.shared.refresh()
            return
        }
        // Body age uses waist-to-height instead of BMI while a waist reading is under 90 days old (`BodyMeasurementsStore`).
        vitals.waistToHeightRatio = measurements.freshWaistToHeightRatio(heightCm: metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil))
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent,
                             sleepConsistency: metrics.sleepConsistency, sleepSpreadMinutes: metrics.sleepSpreadMinutes)
        // The nightly HRV series (`BiologyModel`) here too, not only when Health
        // opens, so Today's HRV tile has its history page from the first refresh.
        // It reads 90 nights, so at most every 30 minutes (Health skips it within 10).
        if biology.hrvSeries.isEmpty || biology.lastRefreshed.map({ Date.now.timeIntervalSince($0) > 30 * 60 }) ?? true {
            await biology.refresh(health: health, settings: settings, manualHRV: manualHRV, proteinTarget: metrics.proteinTarget)
        }
        vitals.setHRVSeries(biology.hrvSeries)
        await muscles.refresh(sessions: sessions.filter { !$0.isActive }, library: library, health: health, hrvBelowNormal: metrics.trainEasyToday)
        weeklyPlans.refreshVolume(muscles: muscles)
        // End-of-block report (`BlockHistoryStore`): follows the block and archives it when a new one starts.
        BlockHistoryStore.shared.observe(block: weeklyPlans.block,
                                         records: weeklyPlans.records(sessions: sessions, extra: metrics.recentTrainingDays),
                                         targets: weeklyPlans.volumeTargets(muscles: muscles))
        // The weather last (it can be slow or offline; 10 s at most, `WeatherClient`).
        await conditions.refresh(settings: settings)
        // Hot days (by estimated WBGT) lower the strain target (less once you're heat-acclimatised).
        conditions.heatAcclimation = HeatAdvice.acclimation(hotDays: conditions.hotDays, trainingDays: metrics.recentTrainingDays)
        conditions.heatTrainingDays = conditions.heatAcclimation.heatTrainingDays
        metrics.heatAdjustment = HeatAdvice.targetAdjustment(wbgtC: conditions.forecastWBGT, acclimation: conditions.heatAcclimation)
        updateWatchFace()
        await CoachNudges.shared.refresh()
        // Last, after everything that reads `sessions`: a session whose Watch
        // recording is gone from Apple Health loses the link (nothing is deleted, `WorkoutLinker`).
        await WorkoutLinker.dropDeletedWatchWorkouts(sessions, health: health, context: modelContext)
    }

    /// Today's HRV, recovery and strain for the Home Screen widget. Skipped when
    /// the refresh couldn't read Apple Health (e.g. a background wake while the
    /// phone is locked), so a failed read never blanks a good snapshot. Before
    /// the night is over, recovery is yesterday's, so the widget shows none
    /// rather than yesterday's score as today's.
    private func updateWidget() {
        guard metrics.errorMessage == nil, metrics.lastUpdated != nil else { return }
        let todayHRV = hrvReadings.first { Calendar.current.isDateInToday($0.date) }
        Reminders.updateWidget(WidgetSnapshot(
            updated: .now,
            hrv: todayHRV?.milliseconds ?? metrics.hrv,
            hrvDate: (todayHRV != nil || (metrics.hrv != nil && !metrics.recoveryIsFromYesterday)) ? Calendar.current.startOfDay(for: .now) : nil,
            recovery: metrics.recoveryIsFromYesterday ? nil : metrics.recovery?.score,
            strain: metrics.strain?.strain,
            logsHRV: hrvReadings.contains { $0.date >= (Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now) }
        ))
    }

    /// [Watch complications] Recovery, strain and the next planned session for the watch face (`WatchFaceData`).
    private func updateWatchFace() {
        guard metrics.errorMessage == nil, metrics.lastUpdated != nil else { return }
        let lastWorkoutEnd = sessions.lazy.compactMap(\.endedAt).max()
        WatchSync.shared.updateFace(metrics: metrics, plans: weeklyPlans, lastWorkoutEnd: lastWorkoutEnd)
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
                hrvMissing: hrvMissing, logsHRV: typesHRV, weighInNudge: weighIn, bedByTonight: bedBy,
                morningOn: !CoachNudges.shared.morningOn, eveningOn: !CoachNudges.shared.eveningOn
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

    /// Planned slots over the next week from the weekly plan (this week's and,
    /// once saved, next week's), as dates.
    private func plannedSlots() -> [Reminders.PlannedSlot] {
        // Fixed days: every planned slot; flexible week: only days when the sessions left need them (`WeeklyPlanStore.reminderSlots`).
        weeklyPlans.reminderSlots(trainingDays: WeeklyPlanStore.trainingDays(sessions: sessions, extra: metrics.recentTrainingDays))
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
/// check (workoutapp://bp), opened from reminders, the Log tab and Health.
private struct MeasurementSheets: ViewModifier {
    let router: AppRouter

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .sheet(isPresented: $router.showMeasurements) { BodyMeasurementsView() }
            .sheet(isPresented: $router.showBloodPressure) { BloodPressureView() }
    }
}

/// Settings, opened from the profile button on any tab (`TabToolbar`).
private struct SettingsSheet: ViewModifier {
    let router: AppRouter

    func body(content: Content) -> some View {
        @Bindable var router = router
        content
            .sheet(isPresented: $router.showSettings) { SettingsView() }
    }
}

/// The running workout as the tab bar's bottom accessory: name, elapsed time
/// and Resume, on every tab while a session is active. HIG *Tab bars* / WWDC25
/// session 356: the accessory is for persistent features like Music's
/// mini-player (ux-audit P4, 4.1 rule 4).
private struct ActiveWorkoutAccessory: ViewModifier {
    let session: WorkoutSession?
    let resume: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabViewBottomAccessory(isEnabled: session != nil) {
                    if let session {
                        ActiveWorkoutBar(session: session, resume: resume)
                    }
                }
        } else if let session {
            // iOS 26.0 has no `isEnabled:`; an empty accessory would still show
            // its glass capsule, so the modifier is only applied while active.
            content
                .tabViewBottomAccessory {
                    ActiveWorkoutBar(session: session, resume: resume)
                }
        } else {
            content
        }
    }
}

private struct ActiveWorkoutBar: View {
    let session: WorkoutSession
    let resume: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: resume) {
            HStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Theme.lifting)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    if placement != .inline {
                        Text(session.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(workoutElapsedText(context.date.timeIntervalSince(session.startedAt)))
                            .font(placement == .inline ? Font.subheadline.weight(.semibold) : Font.caption)
                            .monospacedDigit()
                            .foregroundStyle(placement == .inline ? Theme.primaryText : Theme.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                Text("Resume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.liftingText)
            }
            .foregroundStyle(Theme.primaryText)
            .padding(.horizontal)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(session.name) in progress")
        .accessibilityHint("Resumes your workout.")
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
    let scheduleCheckIns: () -> Void
    let scheduleWorkouts: () -> Void
    let setRestMode: () -> Void
    /// Sex, age and units change the norms and stored display values: re-read Biology at once.
    let markBiologyStale: () -> Void
    /// Whose sleep comes first (`SleepSourceSetting`): sleep, HRV and recovery change with it.
    @AppStorage(SleepSourceSetting.key) private var sleepSource: SleepSourcePreference = .standard
    @State private var oura = OuraLink.shared

    func body(content: Content) -> some View {
        content
            .modifier(RouterReactions(router: router, reloadMedications: reloadMedications, openWorkout: openWorkout))
            .modifier(ReminderReactions(settings: settings, plans: plans,
                                        scheduleCheckIns: scheduleCheckIns, scheduleWorkouts: scheduleWorkouts))
            .onChange(of: settings.goals) { refresh() }
            .onChange(of: settings.restModeUntil) { setRestMode() }
            .onChange(of: settings.sleepNeedHours) { refresh() }
            .onChange(of: settings.sex) { markBiologyStale(); refresh() }
            .onChange(of: settings.age) { markBiologyStale(); refresh() }
            .onChange(of: settings.weightUnit) { markBiologyStale(); refresh() }
            .onChange(of: finishedSessionCount) { refresh() }
            .onChange(of: sleepSource) { markBiologyStale(); refresh() }
            .onChange(of: oura.syncedAt) { markBiologyStale(); refresh() }
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
    let scheduleCheckIns: () -> Void
    let scheduleWorkouts: () -> Void

    func body(content: Content) -> some View {
        content
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

