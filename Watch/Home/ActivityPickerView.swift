import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// "More activities": the last activity on top, the target, then every
/// activity in its group (Cardio, Sports, Snow) as a list the crown scrolls.
/// Sports record with no target (`CardioActivity.takesTarget`). A list, so
/// no double-tap action (HIG Gestures).
struct ActivityPickerView: View {
    @Environment(WatchCardioModel.self) private var cardio
    @Environment(WatchWorkoutModel.self) private var model
    /// The activity started last, offered first.
    @AppStorage(WatchCardioModel.lastActivityKey) private var lastRaw = CardioActivity.outdoorRun.rawValue
    /// `CardioTarget.storage`; stays as chosen from workout to workout.
    @AppStorage(WatchCardioModel.targetKey) private var targetRaw = CardioTarget.off.storage

    private var last: CardioActivity { CardioActivity(rawValue: lastRaw) ?? .outdoorRun }
    private var target: CardioTarget { CardioTarget(storage: targetRaw) }
    private var isStarting: Bool { model.phase == .starting || cardio.phase == .starting }

    var body: some View {
        List {
            Section {
                Button {
                    start(last)
                } label: {
                    Label("Start \(last.title)", systemImage: last.systemImage)
                        .font(.headline)
                        .foregroundStyle(WatchPalette.onTint)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(WatchPalette.recovery))
                .disabled(isStarting)
                .accessibilityIdentifier("watch-cardio-start-last")
                NavigationLink {
                    WatchCardioTargetList(targetRaw: $targetRaw, zones: cardio.preview)
                } label: {
                    HStack {
                        Text("Target")
                        Spacer()
                        Text(targetText)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("watch-cardio-target")
            }
            ForEach(CardioActivity.Category.allCases) { category in
                Section(category.title) {
                    ForEach(CardioActivity.all(in: category).filter { $0 != last }) { activity in
                        Button {
                            start(activity)
                        } label: {
                            Label(activity.title, systemImage: activity.systemImage)
                                .frame(minHeight: 44)
                        }
                        .disabled(isStarting)
                        .accessibilityIdentifier("watch-cardio-\(activity.rawValue)")
                    }
                }
            }
            if let zones = cardio.preview {
                Section {
                    Text(zones.source.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("Activities")
        .task { await cardio.prepare() }
    }

    /// "Off", "Easy 107–133" or "Zone 2"; "Off" for a sport on top.
    private var targetText: String {
        guard target != .off, last.takesTarget else { return "Off" }
        guard target == .easy, let band = cardio.preview.flatMap({ target.band(in: $0.scheme) }) else { return target.title }
        return "Easy \(band.text)"
    }

    private func start(_ activity: CardioActivity) {
        lastRaw = activity.rawValue
        let target = target
        Task { await cardio.start(activity, target: target) }
    }
}

/// No target, Easy, or one of the five zones, each with its bpm range.
struct WatchCardioTargetList: View {
    @Binding var targetRaw: String
    let zones: WatchZoneStore.Choice?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(CardioTarget.all, id: \.self) { option in
                Button {
                    targetRaw = option.storage
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(option.title)
                            if let range = range(for: option) {
                                Text(range)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if option.storage == targetRaw {
                            Image(systemName: "checkmark")
                                .accessibilityLabel("Selected")
                        }
                    }
                }
            }
            Section {
                // Honest about what the taps and the easy band are (`HeartRateZoneScheme.easyBand`).
                Text("With a target, your wrist taps when heart rate has left the range for \(Int(CardioZoneTracker.leaveSeconds)) seconds, and again when it is back. Easy is a pace you can talk at. The range is an estimate: if you can't talk in full sentences, slow down.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Target")
    }

    /// "107–133 bpm" for a target, once the zones are known.
    private func range(for option: CardioTarget) -> String? {
        guard let zones, let band = option.band(in: zones.scheme) else { return nil }
        return "\(band.text) bpm"
    }
}
