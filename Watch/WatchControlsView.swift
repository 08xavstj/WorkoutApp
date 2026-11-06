import SwiftUI

/// Pause/resume, skip to the next exercise, finish (asks the session effort) and discard.
struct WatchControlsView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Binding var page: WatchPage
    @State private var finishing = false
    @State private var discarding = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if model.phase == .paused {
                    Button {
                        model.resume()
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.recovery)
                } else {
                    Button {
                        model.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.strain)
                }
                if model.exerciseAfterShown != nil {
                    // Moves on without deleting: the skipped sets stay open, and
                    // Finish drops any still unticked.
                    Button {
                        model.skipExercise()
                        page = .live
                    } label: {
                        Label("Skip exercise", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.gray)
                }
                Button {
                    finishing = true
                } label: {
                    Label("Finish", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.lifting)
                Button(role: .destructive) {
                    discarding = true
                } label: {
                    Label("Discard", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                Text(model.phoneReachable ? "iPhone connected" : "iPhone out of reach · your sets are kept")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.borderedProminent)
        }
        .sheet(isPresented: $finishing) {
            WatchSessionEffortSheet()
        }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.discard() }
        }
    }
}
