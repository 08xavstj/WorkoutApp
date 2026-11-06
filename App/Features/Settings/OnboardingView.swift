import SwiftUI

/// First launch: explain the three scores and ask for Apple Health access,
/// then offer the optional setup steps (goals, city, gym equipment) before
/// the app opens. `-hasOnboarded YES` (UI tests) skips all of it.
struct OnboardingView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.dismiss) private var dismiss
    @State private var isRequesting = false
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            welcome
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $showingSetup) {
                    OnboardingSetupPage(finish: { finish() })
                }
        }
    }

    private var welcome: some View {
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
            Button("Not now") { showingSetup = true }
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
            // The launch refresh ran before access was granted, and the launch task only
            // turns on background delivery for people already onboarded: do both now, so
            // Today fills in without reopening the app. Observers started at launch
            // without access are started again (refreshSoon folds duplicates into one refresh).
            health.enableBackgroundDelivery()
            let refresher = refresher
            health.observeChanges {
                Task { @MainActor in refresher.refreshSoon() }
            }
            Task { await refresher.refresh() }
        }
        showingSetup = true
    }

    private func finish() {
        settings.hasOnboarded = true
        dismiss()
    }
}

/// The optional second page: goals, city and gym equipment, the same items
/// as Today's "Finish setting up" card, which ticks them off from the same
/// settings. Each pushes its page and every one can be skipped (HIG
/// Onboarding: postpone nonessential setup; ux-audit.md P9, wave 3A).
private struct OnboardingSetupPage: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    let finish: () -> Void

    private var anyDone: Bool {
        settings.goalsSet || settings.hasLocation || gym.isConfigured
    }

    var body: some View {
        List {
            Section {
                setupRows
            } footer: {
                Text("All optional. Anything you skip stays on Today's setup card and in Settings.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Make it yours")
        // Health was already asked; going back would only ask again.
        .navigationBarBackButtonHidden()
        .safeAreaInset(edge: .bottom) {
            Button(action: finish) {
                Text(anyDone ? "Continue" : "Skip for now")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Theme.background)
        }
    }

    @ViewBuilder
    private var setupRows: some View {
        NavigationLink {
            GoalsView(pushed: true)
        } label: {
            OnboardingSetupRow(title: "Set your goals", detail: "Sets your calories, protein and workouts.",
                               systemImage: "target", isDone: settings.goalsSet)
        }
        NavigationLink {
            LocationPicker(pushed: true)
        } label: {
            OnboardingSetupRow(title: "Add your city", detail: "Weather, air quality and daylight for smarter coaching.",
                               systemImage: "location", isDone: settings.hasLocation)
        }
        NavigationLink {
            MyGymView(pushed: true)
        } label: {
            OnboardingSetupRow(title: "Add your gym equipment", detail: "Workouts only use what your gym has.",
                               systemImage: "dumbbell", isDone: gym.isConfigured)
        }
    }
}

/// One setup step: a neutral icon that turns into a check when done, as on
/// Today's checklist (`SetupChecklistCard`).
private struct OnboardingSetupRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isDone: Bool
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : systemImage)
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(isDone ? "Done" : detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDone ? "\(title), done" : "\(title), not set up")
        .accessibilityHint(detail)
    }
}
