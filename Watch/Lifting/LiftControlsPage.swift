import SwiftUI

/// Pause or resume, finish (asks the session effort), skip to the next
/// exercise and discard, as a 2 × 2 grid of 64 pt glass circles (app's choice
/// of size, two to a row: HIG Layout), and whether the iPhone is in reach.
/// Where that doesn't fit under the toolbar (`FittedPage`), the circles step
/// down to 54 and 46 pt (above the HIG's 44 pt), and at 46 pt the iPhone line
/// goes.
struct LiftControlsPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Binding var page: LiftPage
    @State private var finishing = false
    @State private var discarding = false
    @State private var confirmingBrief = false

    private static func size(_ fit: WatchPageFit) -> CGFloat {
        switch fit {
        case .compact: 54
        case .tight: 46
        case .full, .scrolls: 64
        }
    }

    /// Whether the iPhone hears the sets as they're logged.
    private var statusLine: String {
        if model.isLocal { return "Logged on Watch · sent to iPhone at the end" }
        return model.phoneReachable ? "iPhone connected" : "iPhone out of reach · sets saved on Watch"
    }

    /// "Save this 0:42 workout?"
    private var briefTitle: String {
        "Save this \(workoutElapsedText(model.elapsed(at: .now) ?? 0)) workout?"
    }

    var body: some View {
        FittedPage { fit in
            content(fit)
        }
        .sheet(isPresented: $finishing) {
            WatchSessionEffortSheet()
        }
        // Under a minute: save it at all? (HIG Workouts asks apps to discard or ask.)
        .confirmationDialog(briefTitle, isPresented: $confirmingBrief, titleVisibility: .visible) {
            Button("Save") { finishing = true }
            Button("Discard", role: .destructive) { model.discard() }
        }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.discard() }
        } message: {
            Text("Nothing is saved to Apple Health. Sets already sent stay on your iPhone.")
        }
    }

    private func content(_ fit: WatchPageFit) -> some View {
        let size = Self.size(fit)
        return VStack(spacing: 6) {
            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    if model.phase == .paused {
                        CircleButton(title: "Resume", systemImage: "play.fill", tint: WatchPalette.recovery, size: size) {
                            model.resume()
                            page = .set
                        }
                    } else {
                        CircleButton(title: "Pause", systemImage: "pause.fill", tint: WatchPalette.normal, size: size) {
                            model.pause()
                        }
                    }
                    CircleButton(title: "Finish", systemImage: "flag.checkered", tint: WatchPalette.lifting, size: size) {
                        if model.isBrief { confirmingBrief = true } else { finishing = true }
                    }
                }
                GridRow {
                    // Moves on without deleting: the skipped sets stay open, and
                    // Finish drops any still unticked.
                    CircleButton(title: "Skip", systemImage: "forward.fill", size: size) {
                        model.skipExercise()
                        page = .set
                    }
                    .disabled(model.exerciseAfterShown == nil)
                    .accessibilityHint("Skips to the next exercise")
                    CircleButton(title: "Discard", systemImage: "xmark", tint: .red, size: size, role: .destructive) {
                        discarding = true
                    }
                }
            }
            Spacer(minLength: 0)
            if fit != .tight {
                Label(statusLine, systemImage: model.phoneReachable ? "iphone" : "iphone.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(fit == .full || fit == .scrolls ? 2 : 1)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
