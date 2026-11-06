import SwiftUI
import AppCore

/// Fitness › Progress › Muscles: the body map (rest status or this week's
/// sets), hard sets per muscle against this block week's targets or the 10-20
/// range, and a line on each target change (`VolumeProgression`),
/// with their research notes (Schoenfeld et al., J Sports Sci 2017; Pelland et
/// al., Sports Med 2026; ux-audit.md 4.3, 4.6).
struct MusclesDetailView: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles

    var body: some View {
        FitnessDetailPage(title: "Muscles") {
            MuscleMapCard()
            // The bars carry each muscle's target; this card only says what moved and why.
            WeeklySetsCard()
            VolumeTargetsCard()
        }
        // Saves this week's targets once the muscle data has loaded (they then hold for the week).
        .task(id: muscles.hasRefreshed) {
            plans.refreshVolume(muscles: muscles)
        }
    }
}

/// One line for each muscle whose target moved or held (`VolumeProgression`);
/// the bands themselves are shaded on the bars of `WeeklySetsCard`.
/// The copy says the rule runs on performance and recovery, not pump or
/// soreness, and that volume "landmarks" are coaching heuristics.
struct VolumeTargetsCard: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles

    var body: some View {
        let targets = plans.volumeTargets(muscles: muscles)
        VStack(alignment: .leading, spacing: 10) {
            // Each muscle's band is shaded on its bar in "Hard sets since Monday" above,
            // and the block week is in that card's header (QA round 4: no list of
            // identical "8-10 sets" rows).
            CardLabel(text: "How set targets move", color: Theme.lifting)
            if let targets, !targets.targets.isEmpty {
                VolumeTargetNotes(targets: targets.notable)
                Text("Up one set a session only when last week went to plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                DisclosureGroup("How targets work") {
                    Text(Self.explanation)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
                .tint(Theme.secondaryText)
            } else {
                Text("Save a weekly plan and each muscle gets a set target for every week of the training block, moved by how the week before went.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // Schoenfeld, Ogborn & Krieger 2017 (10-20 band); Pelland et al. 2024 preprint (Sports Med 2026),
    // secondary figures; Halperin 2022 (RIR misjudged by ~1 rep); Israetel / RP volume landmarks as practice.
    static let explanation = "A target goes up by one set per session only when last week's sets for that muscle were all done at the effort target, your reps held, and the muscle had recovered; otherwise it holds. Pump and soreness aren't used: neither tracks growth reliably. The 10-20 range comes from research (Schoenfeld 2017; Pelland 2024, preprint); the size of each step and \"landmarks\" like MEV and MRV are coaching rules of thumb, not measured values. A hard set is a working set at RPE 7 or harder (or with no RPE logged); easier sets count 0.6, helper muscles half, and a drop or rest-pause set as the sets it replaces, up to 3. Those weights are the app's choices."
}

/// One line per muscle whose target moved or held.
private struct VolumeTargetNotes: View {
    let targets: [VolumeProgression.Target]

    var body: some View {
        if !targets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(targets) { target in
                    Text(target.note)
                        .font(.caption)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
