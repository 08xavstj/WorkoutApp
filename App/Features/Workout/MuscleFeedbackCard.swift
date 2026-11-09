import SwiftUI
import AppCore

// After a session (the summary right after Finish, and History › summary):
// an optional card for the session's 2-4 main muscles, RP-style: pump,
// soreness from last time, joint pain. One tap each, skippable, kept per
// muscle per session (`MuscleFeedbackStore`). Next week's set targets use them
// (`VolumeProgression`, `MuscleFeedback`): still sore or joint pain holds a
// muscle, twice in a week takes a set off, and "recovered" with a low or OK
// pump allows one set when only the recovery model was holding it. The copy
// says the evidence for this is limited. Joint pain opens the pain log
// (`PainLogView`, `PainGuard`) rather than keeping a second record.

struct MuscleFeedbackCard: View {
    let sessionStart: Date
    /// The session's main muscles (`MuscleFeedback.mainMuscles`).
    let muscles: [Muscle]

    @State private var store = MuscleFeedbackStore.shared
    @State private var painLog = PainLogStore.shared
    @State private var showingPainLog = false

    var body: some View {
        Group {
            if store.isSkipped(sessionStart) {
                skippedRow
            } else {
                questions
            }
        }
        .navigationDestination(isPresented: $showingPainLog) {
            PainLogView(current: PainGuard.active(painLog.reports, today: .now), exclusions: ExerciseExclusions.shared) { changed in
                painLog.log(changed)
            }
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                CardLabel(text: "How did your muscles feel?", color: Theme.liftingText)
                Spacer(minLength: 8)
                Button("Skip") { store.skip(sessionStart) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
            Text("Optional. These only hold a muscle's sets, or allow one more when you've recovered. The evidence for steering sets this way is limited.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(muscles, id: \.self) { muscle in
                MuscleFeedbackRow(sessionStart: sessionStart, muscle: muscle, store: store) {
                    showingPainLog = true
                }
                if muscle != muscles.last {
                    Divider().overlay(Theme.separator)
                }
            }
            EvidenceDisclosure(points: Self.evidence, title: "Where this comes from")
        }
        .card()
    }

    private var skippedRow: some View {
        HStack {
            Text("Muscle check skipped")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 8)
            Button("Answer") { store.unskip(sessionStart) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
        }
        .card()
    }

    // Israetel et al. 2021 (RP practice); Schoenfeld & Contreras, Strength Cond J 2014 (pump) and 2013
    // (soreness); Nosaka et al. 2002; Schoenfeld, Ogborn & Krieger 2017 (weekly sets). Rules: `MuscleFeedback`.
    static let evidence = [
        "The questions follow a coaching practice (Renaissance Periodization), not a tested method.",
        "The pump is a proposed signal for growth, not a shown one (Schoenfeld & Contreras 2014). Soreness tracks muscle damage and new exercises, not growth (Schoenfeld & Contreras 2013; Nosaka et al. 2002).",
        "So your sets still move mainly by performance: sets done, effort and reps (Schoenfeld et al. 2017). Still sore or joint pain holds a muscle; twice in a week takes one set off. These rules are the app's choices.",
    ]
}

/// One muscle: three short rows of choices. Tapping a chosen answer clears it.
private struct MuscleFeedbackRow: View {
    let sessionStart: Date
    let muscle: Muscle
    let store: MuscleFeedbackStore
    let onJointPain: () -> Void

    private var entry: MuscleFeedback.Entry? { store.entry(for: sessionStart, muscle: muscle) }

    /// "yes", "no" or nil (not answered).
    private var jointPainID: String? {
        guard let pain = entry?.jointPain else { return nil }
        return pain ? "yes" : "no"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(muscle.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            FeedbackChoiceRow(title: "Pump", options: Self.pumpOptions, selected: entry?.pump?.rawValue, choose: setPump)
            FeedbackChoiceRow(title: "Sore from last time", options: Self.sorenessOptions, selected: entry?.soreness?.rawValue,
                              choose: setSoreness)
            FeedbackChoiceRow(title: "Joint pain", options: Self.painOptions, selected: jointPainID, choose: setJointPain)
        }
    }

    private static let pumpOptions = MuscleFeedback.Pump.allCases.map { FeedbackOption(id: $0.rawValue, label: $0.title) }
    private static let sorenessOptions = MuscleFeedback.Soreness.allCases.map { FeedbackOption(id: $0.rawValue, label: $0.title) }
    private static let painOptions = [FeedbackOption(id: "no", label: "No"), FeedbackOption(id: "yes", label: "Yes")]

    private func setPump(_ raw: String) {
        let pump = MuscleFeedback.Pump(rawValue: raw)
        let wasSame = entry?.pump == pump
        store.update(sessionStart: sessionStart, muscle: muscle) { entry in
            entry.pump = wasSame ? nil : pump
        }
    }

    private func setSoreness(_ raw: String) {
        let soreness = MuscleFeedback.Soreness(rawValue: raw)
        let wasSame = entry?.soreness == soreness
        store.update(sessionStart: sessionStart, muscle: muscle) { entry in
            entry.soreness = wasSame ? nil : soreness
        }
    }

    private func setJointPain(_ raw: String) {
        let pain = raw == "yes"
        let wasSame = jointPainID == raw
        store.update(sessionStart: sessionStart, muscle: muscle) { entry in
            entry.jointPain = wasSame ? nil : pain
        }
        // The pain log is the one record of pain (`PainGuard`): log the joint there.
        if pain, !wasSame { onJointPain() }
    }
}

private struct FeedbackOption: Identifiable {
    let id: String
    let label: String
}

/// "Pump  [Low] [OK] [Great]": a label and capsule buttons, one selected.
private struct FeedbackChoiceRow: View {
    let title: String
    let options: [FeedbackOption]
    let selected: String?
    let choose: (String) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 4)
                buttons
            }
            VStack(alignment: .leading, spacing: 6) {
                label
                buttons
            }
        }
    }

    private var label: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(Theme.secondaryText)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option.id == selected
                Button {
                    choose(option.id)
                } label: {
                    Text(option.label)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .foregroundStyle(isSelected ? Theme.card : Theme.primaryText)
                        .background(isSelected ? Theme.liftingText : Theme.cardRaised, in: .capsule)
                        // A 44 pt tall tap area around the 32 pt pill (HIG hit targets).
                        .padding(.vertical, 6)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title): \(option.label)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
