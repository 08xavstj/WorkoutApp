import SwiftUI

/// Pause or resume, finish (asks the session effort), skip to the next
/// exercise and discard, as a 2 × 2 grid of 64 pt glass circles (app's choice
/// of size, two to a row: HIG Layout), and whether the iPhone is in reach.
struct LiftControlsPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Binding var page: LiftPage
    @State private var finishing = false
    @State private var discarding = false

    private static let size: CGFloat = 64

    var body: some View {
        VStack(spacing: 6) {
            Grid(horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    if model.phase == .paused {
                        CircleButton(title: "Resume", systemImage: "play.fill", tint: WatchPalette.recovery, size: Self.size) {
                            model.resume()
                            page = .set
                        }
                    } else {
                        CircleButton(title: "Pause", systemImage: "pause.fill", tint: WatchPalette.normal, size: Self.size) {
                            model.pause()
                        }
                    }
                    CircleButton(title: "Finish", systemImage: "flag.checkered", tint: WatchPalette.lifting, size: Self.size) {
                        finishing = true
                    }
                }
                GridRow {
                    // Moves on without deleting: the skipped sets stay open, and
                    // Finish drops any still unticked.
                    CircleButton(title: "Skip", systemImage: "forward.fill", size: Self.size) {
                        model.skipExercise()
                        page = .set
                    }
                    .disabled(model.exerciseAfterShown == nil)
                    .accessibilityHint("Skips to the next exercise")
                    CircleButton(title: "Discard", systemImage: "xmark", tint: .red, size: Self.size, role: .destructive) {
                        discarding = true
                    }
                }
            }
            Spacer(minLength: 0)
            Label(model.phoneReachable ? "iPhone connected" : "iPhone out of reach · sets saved on Watch",
                  systemImage: model.phoneReachable ? "iphone" : "iphone.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .sheet(isPresented: $finishing) {
            WatchSessionEffortSheet()
        }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { model.discard() }
        } message: {
            Text("Nothing is saved to Apple Health. Sets already sent stay on your iPhone.")
        }
    }
}
