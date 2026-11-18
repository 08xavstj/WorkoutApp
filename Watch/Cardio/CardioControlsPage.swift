import SwiftUI

/// Pause or resume, End (saves to Apple Health), Lap, Water Lock and Discard,
/// as 64 pt glass circles two to a row (HIG Layout). The page scrolls when
/// there are five; it has no double-tap action.
struct CardioControlsPage: View {
    @Environment(WatchCardioModel.self) private var cardio
    @Binding var page: CardioPage
    @State private var ending = false
    @State private var discarding = false

    private static let size: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        if cardio.phase == .paused {
                            CircleButton(title: "Resume", systemImage: "play.fill", tint: WatchPalette.recovery, size: Self.size) {
                                cardio.resume()
                                page = .metrics
                            }
                        } else {
                            CircleButton(title: "Pause", systemImage: "pause.fill", tint: WatchPalette.normal, size: Self.size) {
                                cardio.pause()
                            }
                        }
                        CircleButton(title: "End", systemImage: "flag.checkered", tint: WatchPalette.lifting, size: Self.size,
                                     identifier: "watch-cardio-end") {
                            ending = true
                        }
                    }
                    GridRow {
                        if cardio.hasLaps {
                            CircleButton(title: cardio.activity.movement == .stationary ? "Period" : "Lap",
                                         systemImage: "flag.fill", tint: WatchPalette.strain, size: Self.size) {
                                cardio.markLap()
                                page = .metrics
                            }
                            .disabled(cardio.phase != .running || cardio.isAutoPaused)
                        }
                        if cardio.offersWaterLock {
                            CircleButton(title: "Lock", systemImage: "drop.fill", tint: WatchPalette.easy, size: Self.size) {
                                cardio.enableWaterLock()
                            }
                            .accessibilityHint("Water Lock. Turn the Digital Crown to unlock.")
                        }
                    }
                    GridRow {
                        CircleButton(title: "Discard", systemImage: "xmark", tint: .red, size: Self.size, role: .destructive) {
                            discarding = true
                        }
                    }
                }
                Text("\(cardio.activity.title) · saved to Apple Health when you end it")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if cardio.autoPauseSeen {
                    Text("Auto-pause: on in the Watch's Settings › Workout.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .confirmationDialog("End this workout?", isPresented: $ending, titleVisibility: .visible) {
            Button("End and save") {
                Task { await cardio.end() }
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $discarding, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { cardio.discard() }
        }
    }
}
