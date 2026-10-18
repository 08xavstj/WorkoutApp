import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Today's doses on the Lock Screen and Dynamic Island, with "Taken" buttons.
struct MedsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedsActivityAttributes.self) { context in
            MedsLockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.white.opacity(0.92))
                .activitySystemActionForegroundColor(WidgetPalette.ink)
                .widgetURL(URL(string: "workoutapp://meds"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Meds", systemImage: "pills.fill")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.pink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.takenCount)/\(context.state.doses.count) taken")
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let next = context.state.remaining.first {
                        DoseRow(item: next, dark: true)
                    } else {
                        Text("All done for today").font(.subheadline)
                    }
                }
            } compactLeading: {
                Image(systemName: "pills.fill").foregroundStyle(WidgetPalette.pink)
            } compactTrailing: {
                Text("\(context.state.remaining.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetPalette.pink)
            } minimal: {
                Image(systemName: "pills.fill").foregroundStyle(WidgetPalette.pink)
            }
            .widgetURL(URL(string: "workoutapp://meds"))
        }
    }
}

struct MedsLockScreenView: View {
    let state: MedsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Medications today", systemImage: "pills.fill")
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.pink)
                Spacer()
                Text("\(state.takenCount) of \(state.doses.count) taken")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetPalette.secondary)
            }
            if state.remaining.isEmpty {
                Label("All taken. Nice.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetPalette.green)
            } else {
                ForEach(state.remaining.prefix(3)) { item in
                    DoseRow(item: item, dark: false)
                }
            }
        }
    }
}

struct DoseRow: View {
    let item: MedsActivityAttributes.Item
    let dark: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(dark ? .white : WidgetPalette.ink)
                    .lineLimit(1)
                Text([item.dose, item.time.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(dark ? .white.opacity(0.7) : WidgetPalette.secondary)
            }
            Spacer(minLength: 6)
            Button(intent: TakeDoseIntent(doseID: item.id)) {
                Label("Taken", systemImage: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(LinearGradient(colors: [WidgetPalette.pink, WidgetPalette.indigo], startPoint: .leading, endPoint: .trailing), in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}
