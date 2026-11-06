import SwiftUI
import AppCore

/// Fitness › Progress › Muscles: the body map (rest status or this week's
/// sets), this block week's set target per muscle with a line on each change
/// (`VolumeProgression`), and hard sets per muscle against the 10-20 range,
/// with their research notes (Schoenfeld et al., J Sports Sci 2017; Pelland et
/// al., Sports Med 2026; ux-audit.md 4.3, 4.6).
struct MusclesDetailView: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles

    var body: some View {
        FitnessDetailPage(title: "Muscles") {
            MuscleMapCard()
            VolumeTargetsCard()
            WeeklySetsCard()
        }
        // Saves this week's targets once the muscle data has loaded (they then hold for the week).
        .task(id: muscles.hasRefreshed) {
            plans.refreshVolume(muscles: muscles)
        }
    }
}

/// This week's target band per muscle (sets done are the bars in
/// `WeeklySetsCard` below, not repeated) and one line for each muscle whose target moved or held (`VolumeProgression`).
/// The copy says the rule runs on performance and recovery, not pump or
/// soreness, and that volume "landmarks" are coaching heuristics.
struct VolumeTargetsCard: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles

    var body: some View {
        let targets = plans.volumeTargets(muscles: muscles)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardLabel(text: "Set targets this week", color: Theme.lifting)
                Spacer()
                if let week = plans.blockWeek {
                    Text(week.isDeload ? "Deload week" : "Block week \(week.week) of \(week.length)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.liftingText)
                }
            }
            if let targets, !targets.targets.isEmpty {
                // Sets done so far are the bars in "Hard sets since Monday" below, not repeated here.
                ForEach(targets.targets) { target in
                    VolumeTargetRow(target: target)
                }
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

/// "Chest · 12-14 sets", with an arrow when the target moved.
private struct VolumeTargetRow: View {
    let target: VolumeProgression.Target

    var body: some View {
        HStack(spacing: 10) {
            Text(target.muscle.name)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text(target.bandText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            changeIcon
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(target.muscle.name): target \(target.bandText) this week")
    }

    private var changeIcon: some View {
        let symbol: String
        let color: Color
        switch target.change {
        case .added:
            symbol = "arrow.up"
            color = Theme.recoveryHighText
        case .deload:
            symbol = "arrow.down"
            color = Theme.oxygenText
        default:
            symbol = target.change.isHeld ? "equal" : "minus"
            color = Theme.secondaryText
        }
        return Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}

/// One line per muscle whose target moved or held.
private struct VolumeTargetNotes: View {
    let targets: [VolumeProgression.Target]

    var body: some View {
        if !targets.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Divider().overlay(Theme.separator)
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
