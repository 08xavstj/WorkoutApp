import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The gym session on the Lock Screen and in the Dynamic Island, with the rest
/// timer counting down (no app updates needed while it counts).
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutActivityContent(attributes: context.attributes, state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            // Stale means the rest has ended (staleDate = rest end): show the workout again.
            let resting = !context.isStale && (context.state.restEndsAt.map { $0 > .now } ?? false)
            let restRange = context.state.restRange
            let elapsedWidth: CGFloat = Date.now.timeIntervalSince(context.attributes.startedAt) >= 3600 ? 64 : 48
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(resting ? "Rest" : "Workout", systemImage: resting ? "timer" : "dumbbell.fill")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let restRange, resting {
                        Text(timerInterval: restRange, countsDown: true)
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
                if let restRange, resting {
                    Text(timerInterval: restRange, countsDown: true)
                        .monospacedDigit()
                        .frame(width: 44)
                        .foregroundStyle(WidgetPalette.orange)
                } else {
                    Text(context.attributes.startedAt, style: .timer)
                        .monospacedDigit()
                        .frame(width: elapsedWidth)
                        .foregroundStyle(.white)
                }
            } minimal: {
                if let restRange, resting {
                    Text(timerInterval: restRange, countsDown: true)
                        .monospacedDigit()
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.orange)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(WidgetPalette.orange)
                }
            }
            .widgetURL(URL(string: "workoutapp://workout"))
        }
        // Apple Watch Smart Stack (watchOS 11+): the `.small` family below.
        .supplementalActivityFamilies([.small])
    }
}

/// Picks the layout by where the activity is shown: the iPhone Lock Screen
/// (`.medium`) or the Apple Watch Smart Stack (`.small`, opted into with
/// `supplementalActivityFamilies`; docs/research/watch-features.md §2.7).
private struct WorkoutActivityContent: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            WorkoutWatchView(attributes: attributes, state: state, isStale: isStale)
                .padding(12)
        default:
            WorkoutLockScreenView(attributes: attributes, state: state, isStale: isStale)
                .padding(16)
                .activityBackgroundTint(Color.white.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.ink)
        }
    }
}

/// The wrist layout: exercise, "Set x of y" and the rest countdown. No
/// buttons: the Smart Stack card is glanceable, and the Watch app has the
/// rest controls.
private struct WorkoutWatchView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    private var resting: Bool {
        !isStale && (state.restEndsAt.map { $0 > .now } ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Label(resting ? "Rest" : attributes.workoutName, systemImage: resting ? "timer" : "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.orange)
                    .lineLimit(1)
                Spacer(minLength: 4)
                timer
            }
            Text(resting ? "Next: \(state.exercise)" : state.exercise)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
            Text(state.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Rest countdown while resting, else time in the session (both self-updating).
    @ViewBuilder
    private var timer: some View {
        if let restRange = state.restRange, resting {
            Text(timerInterval: restRange, countsDown: true)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(WidgetPalette.orange)
        } else {
            Text(attributes.startedAt, style: .timer)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutLockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let resting = !isStale && (state.restEndsAt.map { $0 > .now } ?? false)
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
            if let restRange = state.restRange, resting {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                        Text(timerInterval: restRange, countsDown: true)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(WidgetPalette.ink)
                    }
                    Spacer()
                    RestButtons(dark: false)
                }
                ProgressView(timerInterval: restRange, countsDown: true) {
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
