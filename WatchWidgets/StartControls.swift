import AppIntents
import SwiftUI
import WidgetKit

// Controls for Control Center and the Smart Stack (watchOS 26, built with
// WidgetKit; WWDC25 "What's new in watchOS 26"). Each runs an intent from
// Shared/WatchIntents.swift that opens the Watch app, which does the work.

/// Opens Tensile on today's session (the iPhone's, or the plan it sent ahead), or Quick lift.
struct StartLiftingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StartLifting") {
            ControlWidgetButton(action: StartLiftingIntent()) {
                Label("Start lifting", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Start lifting")
        .description("Opens Tensile on today's session, or Quick lift.")
    }
}

/// Starts the cardio activity you did last, with its target.
struct StartLastCardioControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StartLastCardio") {
            ControlWidgetButton(action: StartLastCardioIntent()) {
                Label("Start cardio", systemImage: "figure.run")
            }
        }
        .displayName("Start last cardio")
        .description("Starts the cardio activity you did last in Tensile.")
    }
}
