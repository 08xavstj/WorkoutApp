import SwiftUI
import UIKit
import UserNotifications
import AppCore

/// Settings › Coach check-ins: the messages the coach sends first
/// (`CoachNudges`). Off until turned on; the first switch explains, then
/// asks iOS for notification permission. Without permission the messages
/// still appear in the Coach tab.
struct CoachCheckInsSettingsSection: View {
    @State private var nudges = CoachNudges.shared
    @State private var explainingPermission = false
    @State private var kindToTurnOn: CoachCheckIns.Kind?
    @State private var notificationsDenied = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            CoachKindToggle(kind: .morning, detail: "Today's plan and one tip, after you wake", nudges: nudges, turnOn: turnOn)
            CoachKindToggle(kind: .postWorkout, detail: "What you did and what helps next", nudges: nudges, turnOn: turnOn)
            CoachKindToggle(kind: .evening, detail: "Bed-by time and tomorrow's session", nudges: nudges, turnOn: turnOn)
            if nudges.anyOn {
                CoachQuietHoursRows(nudges: nudges)
                if notificationsDenied {
                    CoachNotificationsOffRow()
                }
            }
        } header: {
            Text("Coach check-ins")
        } footer: {
            Text("Up to three short messages a day, none when there's nothing new, and fewer if you don't open them. They're worked out on this iPhone from your own data; nothing is sent anywhere. The timing and limits are app choices.")
        }
        .alert("Let the coach message you?", isPresented: $explainingPermission) {
            Button("Continue") {
                Task { await finishTurningOn() }
            }
            Button("Not now", role: .cancel) {
                kindToTurnOn = nil
            }
        } message: {
            Text("Short check-ins in the morning, after workouts and in the evening. iOS will ask to allow notifications next.")
        }
        .task(id: scenePhase) {
            // Checked again on coming back from iOS Settings.
            guard scenePhase == .active else { return }
            notificationsDenied = await Self.isDenied()
        }
    }

    nonisolated private static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Turns `kind` on, explaining first when iOS hasn't asked about notifications yet.
    private func turnOn(_ kind: CoachCheckIns.Kind) {
        Task {
            if await CoachNudges.permissionNotYetAsked() {
                kindToTurnOn = kind
                explainingPermission = true
            } else {
                set(kind, true)
            }
        }
    }

    private func finishTurningOn() async {
        await nudges.requestPermission()
        notificationsDenied = await Self.isDenied()
        // On even when notifications are refused: the Coach tab still gets the messages.
        if let kind = kindToTurnOn { set(kind, true) }
        kindToTurnOn = nil
    }

    private func set(_ kind: CoachCheckIns.Kind, _ on: Bool) {
        switch kind {
        case .morning: nudges.morningOn = on
        case .postWorkout: nudges.postWorkoutOn = on
        case .evening: nudges.eveningOn = on
        }
    }
}

private struct CoachKindToggle: View {
    let kind: CoachCheckIns.Kind
    let detail: String
    let nudges: CoachNudges
    let turnOn: (CoachCheckIns.Kind) -> Void

    var body: some View {
        // Read here, not only inside the binding, so the row redraws when it changes.
        let isOn = nudges.isOn(kind)
        Toggle(isOn: binding(isOn)) {
            Text(kind.label)
            Text(detail)
        }
    }

    private func binding(_ isOn: Bool) -> Binding<Bool> {
        Binding(
            get: { isOn },
            set: { on in
                if on {
                    turnOn(kind)
                } else {
                    switch kind {
                    case .morning: nudges.morningOn = false
                    case .postWorkout: nudges.postWorkoutOn = false
                    case .evening: nudges.eveningOn = false
                    }
                }
            }
        )
    }
}

private struct CoachQuietHoursRows: View {
    @Bindable var nudges: CoachNudges

    var body: some View {
        Toggle(isOn: $nudges.quietHoursOn) {
            Text("Quiet hours")
            Text("Morning waits, evening comes earlier, workout notes stay in the app")
        }
        if nudges.quietHoursOn {
            DatePicker("From", selection: minutes(\.quietStartMinutes), displayedComponents: .hourAndMinute)
            DatePicker("Until", selection: minutes(\.quietEndMinutes), displayedComponents: .hourAndMinute)
        }
        Toggle(isOn: $nudges.friendlyWording) {
            Text("Friendlier wording")
            Text(OnDeviceCoach.availabilityMessage == nil
                 ? "Apple Intelligence rewords each message on this iPhone"
                 : "Needs Apple Intelligence; the app's own words are used until then")
        }
    }

    private func minutes(_ keyPath: ReferenceWritableKeyPath<CoachNudges, Int>) -> Binding<Date> {
        Binding(
            get: { Reminders.fireDate(day: .now, minutes: nudges[keyPath: keyPath]) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                nudges[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// Notifications are off in iOS Settings: say so, with a way there.
private struct CoachNotificationsOffRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Notifications are off", systemImage: "bell.slash")
                .font(.subheadline.weight(.semibold))
            Text("Check-ins will show in the Coach tab only.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Button("Turn on in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
            .frame(minHeight: 44, alignment: .leading)
        }
    }
}
