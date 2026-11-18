import SwiftUI

/// Before a lifting session starts, on one page that doesn't scroll: the
/// session's name, how many exercises and sets, whether the iPhone is in
/// reach, and Start (double tap presses it: HIG Gestures allows a primary
/// action on a page that doesn't scroll).
struct SessionPreviewView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WatchSession
    /// A plan sent ahead (runs on the Watch alone) rather than the phone's live session.
    var isPlan = false
    /// Planned length, when the plan says.
    var minutes: Int?

    private var isStarting: Bool { model.phase == .starting || cardio.phase == .starting }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isPlan ? "Planned" : "On your iPhone")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchPalette.lifting)
            Text(session.name)
                .font(.title3.weight(.bold))
                .lineLimit(2)
            Text(facts)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Label(phoneLine, systemImage: model.phoneReachable ? "iphone" : "iphone.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isStarting {
                ProgressView("Starting…")
            } else {
                PrimaryWideButton(title: "Start", systemImage: "play.fill", tint: WatchPalette.recovery,
                                  primaryAction: !dynamicTypeSize.isAccessibilitySize,
                                  accessibilityLabel: "Start \(session.name)") {
                    start()
                }
            }
        }
        .navigationTitle("Lift")
    }

    /// "6 exercises · 18 sets · 55 min".
    private var facts: String {
        var parts = ["\(session.exercises.count) \(session.exercises.count == 1 ? "exercise" : "exercises")",
                     "\(session.totalSets) sets"]
        if session.completedSets > 0 { parts[1] = "\(session.completedSets) of \(session.totalSets) sets" }
        if let minutes { parts.append("\(minutes) min") }
        return parts.joined(separator: " · ")
    }

    private var phoneLine: String {
        if isPlan { return model.phoneReachable ? "Sets go to your iPhone as you log them" : "Sets are kept on your Watch" }
        return model.phoneReachable ? "iPhone connected" : "iPhone out of reach · sets wait on Watch"
    }

    private func start() {
        let id = session.id
        Task { await model.start(sessionID: id) }
    }
}
