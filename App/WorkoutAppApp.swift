import SwiftUI
import SwiftData
import AppCore

@main
struct WorkoutAppApp: App {
    @State private var settings = UserSettings()
    @State private var library = ExerciseLibrary()
    @State private var metrics = DailyMetricsModel()
    @State private var biology = BiologyModel()
    @State private var vitals = VitalsModel()
    @State private var coach = CoachModel()
    @State private var gym = GymStore()
    @State private var launcher = WorkoutLauncher()
    @State private var refresher = AppRefresher()
    @State private var recorder: LiveWorkoutRecorder
    private let health: HealthKitClient
    private let container: ModelContainer

    init() {
        let health = HealthKitClient()
        self.health = health
        _recorder = State(initialValue: LiveWorkoutRecorder(store: health.store))
        do {
            container = try ModelContainer(
                for: Schema(versionedSchema: WorkoutSchema.self),
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
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.healthClient) private var health
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var selection: AppTab = .today

    var body: some View {
        @Bindable var launcher = launcher
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
            if settings.hasOnboarded {
                await health?.requestAuthorizationIfNeeded()
            }
            // Refresh when Garmin Connect (or anything else) writes new data to Health.
            let refresher = refresher
            health?.observeChanges {
                Task { @MainActor in
                    refresher.refreshSoon()
                }
            }
            await refreshMetrics()
            // Keep today's numbers current while the app is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                if scenePhase == .active { await refreshMetrics() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshMetrics() } }
        }
        .onChange(of: finishedSessionCount) {
            Task { await refreshMetrics() }
        }
        .onChange(of: hrvReadings.map(\.milliseconds)) {
            Task { await refreshMetrics() }
        }
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
        await metrics.refresh(health: health, settings: settings, sessions: recent, manualHRV: manualHRV)
        await vitals.refresh(health: health, settings: settings, profile: metrics.heartRateProfile, sessions: recent)
    }
}
