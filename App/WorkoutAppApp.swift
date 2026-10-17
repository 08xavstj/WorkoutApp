import SwiftUI
import SwiftData

@main
struct WorkoutAppApp: App {
    @State private var settings = UserSettings()
    @State private var library = ExerciseLibrary()
    @State private var metrics = DailyMetricsModel()
    @State private var coach = CoachModel()
    private let health = HealthKitClient()
    private let container: ModelContainer

    init() {
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
                .environment(coach)
                .environment(\.healthClient, health)
                .preferredColorScheme(.dark)
                .tint(Theme.strain)
        }
        .modelContainer(container)
    }
}

extension EnvironmentValues {
    @Entry var healthClient: HealthKitClient?
}

enum AppTab: Hashable {
    case today, workout, coach, settings
}

struct RootView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(CoachModel.self) private var coach
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "circle.circle", value: AppTab.today) {
                TodayView(askCoach: { question in
                    coach.pendingQuestion = question
                    selection = .coach
                })
            }
            Tab("Workout", systemImage: "dumbbell.fill", value: AppTab.workout) {
                WorkoutHomeView()
            }
            Tab("Coach", systemImage: "sparkles", value: AppTab.coach) {
                CoachView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .sheet(isPresented: Binding(
            get: { !settings.hasOnboarded },
            set: { if !$0 { settings.hasOnboarded = true } }
        )) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
    }
}
