import SwiftUI

/// First launch: explain the three scores and ask for Apple Health access.
struct OnboardingView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("Your training, recovery and sleep in one place")
                .font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 16) {
                row("flame.fill", Theme.strain, "Strain", "How hard your body worked today, 0-21. Gym sessions count, not just cardio.")
                row("bolt.heart.fill", Theme.recoveryHigh, "Recovery", "How ready you are, from your HRV, resting heart rate and sleep.")
                row("moon.zzz.fill", Theme.sleep, "Sleep", "Time asleep against what you need, plus quality.")
                row("sparkles", Theme.lifting, "Coach", "Ask what to do today. It knows your numbers and your workouts.")
            }
            Spacer()
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
            Button("Not now") { finish() }
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .background(Theme.background)
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
