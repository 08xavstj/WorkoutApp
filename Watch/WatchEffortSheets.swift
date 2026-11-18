import SwiftUI
import WatchKit

/// At Finish: the whole session's effort, 1-10 (Foster's session RPE, the
/// labels of `RPEScale.sessionLabel`), as 48 pt chips two to a row (text
/// buttons: at most two a row, HIG Layout), and a 44 pt "End without rating".
/// A sheet that scrolls, so no double-tap action here (HIG Gestures).
struct WatchSessionEffortSheet: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var chips: [WatchChip] {
        WatchRPEChoice.session.map { choice in
            WatchChip(id: choice.value, label: "\(choice.value)", detail: choice.label,
                      spoken: "Effort \(choice.value), \(choice.label)")
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("How was the whole session?")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                ChipGrid(chips: chips, perRow: 2, height: 48, tint: WatchPalette.lifting) { value in
                    end(value)
                }
                Button {
                    end(nil)
                } label: {
                    Text("End without rating")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func end(_ rpe: Int?) {
        dismiss()
        Task { await model.finish(sessionRPE: rpe) }
    }
}
