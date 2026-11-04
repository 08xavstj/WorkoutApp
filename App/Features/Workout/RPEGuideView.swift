import SwiftUI
import AppCore

/// Explains RPE: what each number means for a set, how to pick one, and how
/// the whole-workout rating on the finish screen differs.
struct RPEGuideView: View {
    @Environment(\.dismiss) private var dismiss
    /// At accessibility text sizes the rows stack instead of squeezing the
    /// text beside the number (ux-audit.md 4.8, P22).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The number badge and the range column grow with the text.
    @ScaledMetric(relativeTo: .title3) private var badgeWidth: CGFloat = 48
    @ScaledMetric(relativeTo: .title3) private var badgeHeight: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var rangeWidth: CGFloat = 40

    private var stacked: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("RPE (rate of perceived exertion) is how hard a set was, measured by how many more good reps you could have done. RPE 8 means you stopped with 2 reps left.")
                        .font(.subheadline)
                } header: {
                    Text("What it is")
                }

                Section {
                    ForEach(RPEScale.levels) { level in
                        levelRow(level)
                    }
                } header: {
                    Text("Each set")
                }

                Section {
                    tip("Rate right after the set, before you rest.")
                    tip("Ask: \"How many more clean reps could I have done?\" Then pick the matching number.")
                    tip("Most working sets should land at RPE 7-9. Save 10 for the occasional test set.")
                    tip("Use the ½ for in-between sets, e.g. 8.5 when you'd surely get one more and maybe two.")
                    tip("Beginners tend to underrate. If you've never gone to failure, your \"2 left\" is often 4 left.")
                } header: {
                    Text("How to choose")
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
                    Text("Zourdos et al., J Strength Cond Res 2016 (reps-in-reserve RPE scale). Helms et al., Strength Cond J 2016. Foster et al., J Strength Cond Res 2001 (session RPE).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Sources")
                }
            }
            .navigationTitle("RPE guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// One RPE level: number badge, title, reps left and how it feels.
    private func levelRow(_ level: RPEScale.Level) -> some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        let titleLayout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout())
        return layout {
            Text(level.rpe.formatted())
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(minWidth: badgeWidth, minHeight: badgeHeight)
                .background(color(for: level.rpe).gradient, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                titleLayout {
                    Text(level.title).font(.subheadline.weight(.semibold))
                    if !stacked { Spacer() }
                    Text(repsLeftText(level.repsLeft))
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
        case "0": "0 left"
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
