import SwiftUI
import AppCore

/// Explains RPE: what each number means for a set, how to pick one, and how
/// the whole-workout rating on the finish screen differs.
struct RPEGuideView: View {
    @Environment(\.dismiss) private var dismiss

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
                        HStack(alignment: .top, spacing: 12) {
                            Text(level.rpe.formatted())
                                .font(.title3.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 40)
                                .background(color(for: level.rpe).gradient, in: .rect(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(level.title).font(.subheadline.weight(.semibold))
                                    Spacer()
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
                    sessionRow("1-2", RPEScale.sessionLabel(2), "Barely felt it; like a walk.")
                    sessionRow("3-4", RPEScale.sessionLabel(4), "Comfortable; could chat the whole time.")
                    sessionRow("5-6", RPEScale.sessionLabel(6), "Working, but plenty left.")
                    sessionRow("7-8", RPEScale.sessionLabel(8), "Tough session; you'd be glad to finish.")
                    sessionRow("9", RPEScale.sessionLabel(9), "Close to your hardest workout.")
                    sessionRow("10", RPEScale.sessionLabel(10), "As hard as you can train.")
                } header: {
                    Text("Whole workout (finish screen)")
                } footer: {
                    Text("When you finish, you rate the whole session 1-10. That rating times the minutes you trained is how lifting counts toward strain, because heart rate undercounts gym work.")
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

    private func repsLeftText(_ reps: String) -> String {
        switch reps {
        case "0": "0 left"
        case "1": "1 rep left"
        default: "\(reps) reps left"
        }
    }

    private func color(for rpe: Double) -> Color {
        switch rpe {
        case 9.5...: Theme.recoveryLow
        case 8...: Theme.lifting
        case 7...: Theme.recoveryModerate
        default: Theme.recoveryHigh
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle")
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
    }

    private func sessionRow(_ range: String, _ label: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(range)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
