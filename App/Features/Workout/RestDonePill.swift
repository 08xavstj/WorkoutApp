import SwiftUI

/// What the rest timer turns into for a few seconds when it runs out with the
/// app open (`RestTimerStore.justFinishedAt`): green "Rest done", the next set,
/// and one tap on the phone. iOS shows no banner or sound then
/// (`AppRouter.willPresent`), and with the Watch recording, the wrist buzzes too.
struct RestDonePill: View {
    var next: String? = nil
    /// Runs once when it appears (Live Activity and Watch catch up).
    let onAppear: () -> Void

    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Rest done", systemImage: "checkmark.circle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.recoveryHighText)
            if let next {
                Text(next)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Theme.recoveryHigh.opacity(0.14), in: RoundedRectangle(cornerRadius: 22))
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.recoveryHigh.opacity(0.5)))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .sensoryFeedback(.warning, trigger: shown) { _, now in now && RestAlertPolicy.appCues }
        .onAppear {
            shown = true
            onAppear()
            AccessibilityNotification.Announcement("Rest done").post()
        }
    }
}
