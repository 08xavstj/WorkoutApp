import SwiftUI

enum WatchPage: Hashable {
    case controls, live, exercises
}

/// Start screen → the three workout pages (crown scrolls between them) → end screen.
struct WatchRootView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @State private var page: WatchPage = .live

    var body: some View {
        switch model.phase {
        case .idle, .starting:
            WatchStartView()
        case .running, .paused:
            workoutPages
        case .ended:
            WatchEndView()
        }
    }

    private var workoutPages: some View {
        TabView(selection: $page) {
            WatchControlsView(page: $page)
                .tag(WatchPage.controls)
            WatchLiveView()
                .tag(WatchPage.live)
            WatchExerciseListView(page: $page)
                .tag(WatchPage.exercises)
        }
        .tabViewStyle(.verticalPage)
    }
}

/// Live heart rate and calories on one line.
struct WatchVitalsLine: View {
    @Environment(WatchWorkoutModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .foregroundStyle(WatchTheme.heart)
            Text(model.heartRate.map { "\(Int($0.rounded()))" } ?? "–")
                .monospacedDigit()
            Text("bpm")
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(model.activeKilocalories.map { "\(Int($0.rounded())) kcal" } ?? "– kcal")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
    }
}
