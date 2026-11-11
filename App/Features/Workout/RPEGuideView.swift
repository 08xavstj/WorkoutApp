import SwiftUI
import AppCore

/// Explains effort in plain words first: "reps in the tank" (reps left, the
/// RIR-based RPE scale), a worked example, why the app asks, the reps-left ↔
/// RPE table, and how the whole-workout rating on the finish screen differs.
struct RPEGuideView: View {
    /// The plan's reps in reserve, so the top explains the number on screen
    /// ("3 reps in the tank"); nil explains the usual 2.
    var reserve: Double? = nil

    @Environment(\.dismiss) private var dismiss
    /// At accessibility text sizes the rows stack instead of squeezing the
    /// text beside the number (ux-audit.md 4.8, P22).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The number badge and the range column grow with the text.
    @ScaledMetric(relativeTo: .title3) private var badgeWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .title3) private var badgeHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var rangeWidth: CGFloat = 40

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }
    private var shownReserve: Double { reserve ?? 2 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ReserveText.explainerBody(shownReserve))
                        .font(.subheadline)
                    Label(ReserveText.example(reps: 8, reserve: 2), systemImage: "lightbulb")
                        .font(.subheadline)
                        .symbolRenderingMode(.hierarchical)
                } header: {
                    Text(ReserveText.explainerTitle(shownReserve))
                }

                Section {
                    // Helms et al., Strength Cond J 2016; Zourdos et al., J Strength Cond Res 2016;
                    // Halperin et al., Sports Med 2022 (misjudged by about one rep, mostly too few).
                    Text("Stopping a few reps short lets you do more good sets with less fatigue, and the reps you had left tell the app whether the weight was right. Guessing gets better with practice. Early on, most people think they have fewer reps left than they really do.")
                        .font(.subheadline)
                } header: {
                    Text("Why")
                }

                Section {
                    tip("Rate right after the set, before you rest.")
                    tip("Ask: \"How many more clean reps could I have done?\" Tap that number.")
                    tip("Most working sets should stop with 1-3 reps left. Going all the way (0 left) is for the occasional test set.")
                    tip("Use ½ for in-between sets, e.g. sure of 2 more and maybe 3.")
                    tip("New to lifting? If you've never gone to failure, your \"2 left\" is often 4 left.")
                } header: {
                    Text("How to choose")
                }

                Section {
                    ForEach(RPEScale.levels) { level in
                        levelRow(level)
                    }
                } header: {
                    Text("Reps left and RPE")
                } footer: {
                    Text("RPE (rate of perceived exertion) is the same thing as a number: RPE = 10 minus reps left. The app stores it that way.")
                }

                Section {
                    sessionRow("1", RPEScale.sessionLabel(1), "Barely felt it, like a gentle walk.")
                    sessionRow("2", RPEScale.sessionLabel(2), "A light technique or recovery session.")
                    sessionRow("3", RPEScale.sessionLabel(3), "Working, but comfortable the whole way.")
                    sessionRow("4", RPEScale.sessionLabel(4), "You noticed the effort, with lots left.")
                    sessionRow("5-6", RPEScale.sessionLabel(6), "A solid session; most sets were a real effort.")
                    sessionRow("7-9", RPEScale.sessionLabel(8), "Tough throughout; you were glad to finish.")
                    sessionRow("10", RPEScale.sessionLabel(10), "The hardest session you could do.")
                } header: {
                    Text("Whole workout (finish screen)")
                } footer: {
                    Text("Rate the whole session, not your last set: how hard was it overall? Most normal lifting sessions land around 4-7. That rating times the minutes you trained is how lifting counts toward strain, because heart rate undercounts gym work.")
                }

                Section {
                    Text("Helms et al., Strength Cond J 2016 (reps-in-reserve RPE scale). Zourdos et al., J Strength Cond Res 2016 (accuracy improves with training experience). Halperin et al., Sports Med 2022 (how far off guesses are). Foster et al., J Strength Cond Res 2001 (session RPE).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sources")
                }
            }
            // Opaque at the medium detent (a part-height sheet is see-through glass by default).
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Reps in the tank")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    /// One level: reps-left badge, title and how it feels, RPE as the small label.
    private func levelRow(_ level: RPEScale.Level) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let titleLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout())
        return layout {
            Text(level.repsLeft)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: badgeWidth, minHeight: badgeHeight)
                .background(color(for: level.rpe).gradient, in: .rect(cornerRadius: 10))
                .accessibilityLabel(repsLeftText(level.repsLeft))
            VStack(alignment: .leading, spacing: 2) {
                titleLayout {
                    Text(level.title).font(.subheadline.weight(.semibold))
                    if !stacked { Spacer() }
                    Text("RPE \(level.rpe.formatted())")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(level.feel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func repsLeftText(_ reps: String) -> String {
        switch reps {
        case "0": "0 reps left"
        case "1": "1 rep left"
        default: "\(reps) reps left"
        }
    }

    private func color(for rpe: Double) -> Color {
        switch rpe {
        case 9.5...: Theme.recoveryLowText
        case 8...: Theme.liftingText
        case 7...: Theme.recoveryModerateText
        default: Theme.recoveryHighText
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
    }

    private func sessionRow(_ range: String, _ label: String, _ detail: String) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(range)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(minWidth: rangeWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Once, at the top of a workout: each set has a rep goal, and the "reps
/// left" tap after a set moves the next set's goal (`RepGoal`). Shown again
/// once after the switch from reps-in-reserve targets (new `seenKey`).
struct RepsLeftIntroCard: View {
    nonisolated static let seenKey = "workout.repGoalIntroSeen"

    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hit the rep goal", systemImage: "target")
                .font(.headline)
                .foregroundStyle(Theme.liftingText)
            Text("Each set shows the reps to aim for. After a set, tap how many more you could have done: the next set's goal goes up if it was easy and down if it was hard.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDone) {
                Text("Got it")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.lifting, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .card()
    }
}
