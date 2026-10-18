import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The gym session on the Lock Screen and in the Dynamic Island, with the rest
/// timer counting down (no app updates needed while it counts).
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.white.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        } dynamicIsland: { context in
            let resting = context.state.restEndsAt.map { $0 > .now } ?? false
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(resting ? "Rest" : "Workout", systemImage: resting ? "timer" : "dumbbell.fill")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let ends = context.state.restEndsAt, resting {
                        Text(timerInterval: Date.now...ends, countsDown: true)
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                    } else {
                        Text(context.attributes.startedAt, style: .timer)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(context.state.exercise).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        Text(context.state.detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                        if resting {
                            RestButtons(dark: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: resting ? "timer" : "dumbbell.fill")
                    .foregroundStyle(WidgetPalette.orange)
            } compactTrailing: {
                if let ends = context.state.restEndsAt, resting {
                    Text(timerInterval: Date.now...ends, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(WidgetPalette.orange)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(width: 52)
                        .foregroundStyle(.white)
                }
            } minimal: {
                if let ends = context.state.restEndsAt, resting {
                    Text(timerInterval: Date.now...ends, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.orange)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(WidgetPalette.orange)
                }
            }
            .widgetURL(URL(string: "workoutapp://workout"))
        }
    }
}

private struct WorkoutLockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        let resting = state.restEndsAt.map { $0 > .now } ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(attributes.workoutName, systemImage: "dumbbell.fill")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.orange)
                    .lineLimit(1)
                Spacer()
                Text(attributes.startedAt, style: .timer)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(WidgetPalette.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            if let ends = state.restEndsAt, resting {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                        Text(timerInterval: Date.now...ends, countsDown: true)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetPalette.ink)
                    }
                    Spacer()
                    RestButtons(dark: false)
                }
                ProgressView(timerInterval: ends.addingTimeInterval(-state.restLength)...ends, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(WidgetPalette.orange)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(resting ? "Next: \(state.exercise)" : state.exercise)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetPalette.ink)
                    .lineLimit(1)
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct RestButtons: View {
    let dark: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AdjustRestIntent(seconds: 15)) {
                Text("+15s")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((dark ? Color.white : WidgetPalette.orange).opacity(0.18), in: .capsule)
                    .foregroundStyle(dark ? .white : WidgetPalette.orange)
            }
            .buttonStyle(.plain)
            Button(intent: AdjustRestIntent(seconds: 0)) {
                Text("Skip")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(WidgetPalette.orange, in: .capsule)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }
}
