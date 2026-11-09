import SwiftUI
import UIKit
import UserNotifications

/// Whether the user has turned this app's notifications off in iOS Settings.
nonisolated enum NotificationAccess {
    static func isDenied() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }
}

/// "Notifications are off" with a button to the app's notification settings.
/// Shown where reminders are set up (Medications, Settings › Reminders), since
/// iOS never asks twice and nothing else would say why reminders don't come.
struct NotificationsOffBanner: View {
    /// What won't arrive, e.g. "Dose reminders won't arrive."
    let detail: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .font(.title3)
                .foregroundStyle(Theme.recoveryModerateText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notifications are off")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Turn on in Settings", action: openSettings)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44, alignment: .leading)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}

extension View {
    /// Keeps `isDenied` up to date: checked on appear and whenever the app
    /// comes back to the foreground (e.g. from iOS Settings).
    func trackingNotificationsDenied(_ isDenied: Binding<Bool>) -> some View {
        modifier(NotificationsDeniedTracker(isDenied: isDenied))
    }
}

private struct NotificationsDeniedTracker: ViewModifier {
    @Binding var isDenied: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.task(id: scenePhase) {
            guard scenePhase == .active else { return }
            isDenied = await NotificationAccess.isDenied()
        }
    }
}
