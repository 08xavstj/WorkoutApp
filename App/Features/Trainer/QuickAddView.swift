import SwiftUI
import SwiftData

/// The "+" tab: start or log something.
struct QuickAddView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(GymStore.self) private var gym
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var showingHRV = false
    @State private var showingGym = false
    @State private var showingMeds = false
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let active = sessions.first(where: \.isActive) {
                        ResumeWorkoutBanner(session: active) { launcher.activeSession = active }
                    }
                    action("Build a workout", "The trainer plans it from your gym and recovery", "sparkles", Theme.lifting) {
                        launcher.openBuilder()
                    }
                    action("Empty workout", "Add exercises as you go", "dumbbell.fill", Theme.strain) {
                        launcher.startEmpty(in: modelContext)
                    }
                    action("Log overnight HRV", "From your watch's app", "waveform.path.ecg", Theme.recoveryHigh) {
                        showingHRV = true
                    }
                    action("Progress photos", "Front and side, compared weekly by Claude", "camera.fill", Theme.lifting) {
                        router.showProgressPhotos = true
                    }
                    action("Medications", "Doses, reminders and how they affect training", "pills.fill", Theme.heart) {
                        showingMeds = true
                    }
                    action("My Gym", gym.isConfigured ? gym.profile.name : "Set up your equipment and weights", "slider.horizontal.3", Theme.sleep) {
                        showingGym = true
                    }
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        row("Workout history", "Every session you've logged", "calendar", Theme.nutrition)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(Theme.background)
            .navigationTitle("Add")
            .sheet(isPresented: $showingMeds) { MedicationsView() }
            .sheet(isPresented: $showingHRV) {
                HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingGym) { MyGymView() }
        }
    }

    private func action(_ title: String, _ detail: String, _ icon: String, _ color: Color, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            row(title, detail, icon, color)
        }
        .buttonStyle(.plain)
    }

    private func row(_ title: String, _ detail: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemName: icon, color: color, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}
