import SwiftUI

/// First launch: explain the three scores and ask for Apple Health access.
struct OnboardingView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        // Scrolls at large text sizes; the buttons stay pinned at the bottom.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your training, recovery and sleep in one place")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 40)
                VStack(alignment: .leading, spacing: 16) {
                    row("flame.fill", Theme.strain, "Strain", "How hard your body worked today, 0-100%. Gym sessions count, not just cardio.")
                    row("bolt.heart.fill", Theme.recoveryHigh, "Recovery", "How ready you are, from your heart rate variability (HRV), resting heart rate and sleep.")
                    row("moon.zzz.fill", Theme.sleep, "Sleep", "Time asleep against what you need, plus quality.")
                    row("sparkles", Theme.lifting, "Coach", "Ask what to do today. It knows your numbers and your workouts.")
                }
            }
            .padding(24)
            .lockedToScreenWidth()
        }
        .safeAreaInset(edge: .bottom) {
            buttons
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(Theme.background)
        }
        .background(Theme.background)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button {
                Task { await allowHealth() }
            } label: {
                Text("Connect Apple Health")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            Text("On the next screen, tap **Turn On All** at the top, then **Allow**. iOS keeps Allow greyed out until you turn something on.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            Button("Not now") { finish() }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func allowHealth() async {
        isRequesting = true
        defer { isRequesting = false }
        if let health {
            try? await health.requestAuthorization()
            let profile = health.profileCharacteristics()
            if let age = profile.age { settings.age = age }
            if let sex = profile.sex { settings.sex = sex }
        }
        finish()
    }

    private func finish() {
        settings.hasOnboarded = true
        dismiss()
    }
}
