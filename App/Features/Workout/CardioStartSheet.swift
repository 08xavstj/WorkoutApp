import AppCore
import SwiftUI

/// Pick a cardio activity or sport and start recording it on the Apple
/// Watch: one tap opens Tensile on the wrist already recording, the way
/// "Start on Apple Watch" does for a gym session (`WatchSync.startCardioOnWatch`).
///
/// Recent picks come first, then cardio, sports and snow. The Watch saves the
/// workout to Apple Health under its own type (Squash, Soccer...), and the
/// phone counts it in strain and zone minutes from there like any watch
/// workout. Sports record with no heart-rate target: in stop-and-go play
/// heart rate follows the game (`CardioActivity.takesTarget`).
struct CardioStartSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let watch = WatchSync.shared
    /// Up to three recent activities, newest first, as comma-separated raw values.
    @AppStorage("phoneCardioRecent") private var recentRaw = ""
    @State private var starting: CardioActivity?
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 34

    static let recentLimit = 3

    private var recent: [CardioActivity] {
        recentRaw.split(separator: ",").compactMap { CardioActivity(rawValue: String($0)) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let problem = watch.startProblem {
                    Section {
                        Label(problem, systemImage: "exclamationmark.applewatch")
                            .foregroundStyle(Theme.heart)
                    }
                }
                if !recent.isEmpty {
                    Section("Recent") {
                        ForEach(recent) { row(for: $0) }
                    }
                }
                ForEach(CardioActivity.Category.allCases) { category in
                    Section {
                        ForEach(CardioActivity.all(in: category).filter { !recent.contains($0) }) { row(for: $0) }
                    } header: {
                        Text(category.title)
                    } footer: {
                        if category == .sport {
                            Text("Sports record heart rate and calories with no target: in stop-and-go play your heart rate follows the game.")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Start on Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { watch.startProblem = nil }
        }
    }

    private func row(for activity: CardioActivity) -> some View {
        Button {
            Task { await start(activity) }
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: activity.systemImage, color: Theme.strain, size: badgeSize)
                Text(activity.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                if starting == activity {
                    ProgressView()
                } else {
                    Image(systemName: "applewatch")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .disabled(starting != nil)
        .accessibilityHint("Starts recording on your Apple Watch.")
        .accessibilityIdentifier("cardio-start-\(activity.rawValue)")
    }

    private func start(_ activity: CardioActivity) async {
        starting = activity
        let started = await watch.startCardioOnWatch(activity)
        starting = nil
        guard started else { return }
        remember(activity)
        dismiss()
    }

    private func remember(_ activity: CardioActivity) {
        let list = [activity] + recent.filter { $0 != activity }
        recentRaw = list.prefix(Self.recentLimit).map(\.rawValue).joined(separator: ",")
    }
}
