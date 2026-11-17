import AppCore
import SwiftData
import SwiftUI

/// Settings › Notifications › Reminders, under "Workout reminders": the
/// reminder's tone, whether Apple Intelligence may write some of the lines,
/// and "Show me one", which shows a line written from today's data
/// (`WorkoutVoice.preview`). Playful is the default because the owner asked
/// for it; nothing shows it works better than plain
/// (docs/research/funny-nudges-2026-11.md), so Plain is one tap away.
struct WorkoutVoiceSettingsRows: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @Environment(CheckInStore.self) private var checkIns
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles
    @Environment(GymStore.self) private var gym
    @Environment(ExerciseLibrary.self) private var library
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    /// The previews shown so far, newest last, so each tap gives a different line.
    @State private var shown: [WorkoutBanter.Pick] = []
    @State private var preview: WorkoutVoice.Preview?

    var body: some View {
        @Bindable var settings = settings
        Picker("Reminder tone", selection: $settings.workoutReminderTone) {
            ForEach(WorkoutBanter.Tone.allCases) { tone in
                Text(tone.label).tag(tone)
            }
        }
        .accessibilityIdentifier("settings-workout-reminder-tone")
        .onChange(of: settings.workoutReminderTone) {
            shown = []
            preview = nil
        }
        if settings.workoutReminderTone == .playful, WorkoutVoiceModel.isAvailable {
            Toggle(isOn: $settings.workoutReminderFreshLines) {
                Text("Fresh lines from Apple Intelligence")
                Text("Some lines are written on this iPhone. Nothing is sent anywhere.")
            }
            .accessibilityIdentifier("settings-workout-reminder-fresh-lines")
        }
        Button("Show me one", action: showOne)
            .accessibilityIdentifier("settings-workout-reminder-preview")
        if let preview {
            VStack(alignment: .leading, spacing: 4) {
                Text(preview.pick.text)
                Text(preview.note)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("settings-workout-reminder-preview-line")
        }
    }

    /// Writes a line from today's data. Nothing is sent and no line is used up.
    private func showOne() {
        let sources = WorkoutVoice.Sources(settings: settings, metrics: metrics, vitals: vitals, checkIns: checkIns, plans: plans,
                                           muscles: muscles, gym: gym, library: library, sessions: sessions)
        let next = WorkoutVoice.preview(from: sources, shown: shown)
        shown.append(next.pick)
        preview = next
    }
}
