import SwiftUI
import AppCore

// "Apply to next block": the report's suggestions as toggles (all on), saved
// as `NextBlockAdjustments` for the block now running (`NextBlockStore`). The
// weekly set targets and the planner use them until that block ends. Only
// the latest finished block's report can be applied, while its next block runs.

/// The report's "Next block" card: toggles and Apply, the applied changes
/// with Undo, or (older blocks) the suggestions as a list.
struct BlockApplyCard: View {
    let report: BlockReport.Report
    let archive: BlockArchive

    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles
    @State private var nextStore = NextBlockStore.shared
    @State private var history = BlockHistoryStore.shared
    /// Suggestions switched off; every one starts on.
    @State private var off: Set<String> = []

    /// The block running now, when this report is the latest finished one.
    private var nextBlock: BlockArchive? {
        guard let current = history.current, let last = history.finished.last,
              Calendar.current.isDate(last.start, inSameDayAs: archive.start), current.start > archive.start else { return nil }
        return current
    }

    private var nextNumber: Int { history.finished.count + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Next block", color: Theme.liftingText)
            content
            Text("Suggestions are the app's reading of the studies named, not a tested protocol.")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(tint: Theme.recoveryHigh)
    }

    @ViewBuilder private var content: some View {
        if report.next.isEmpty {
            Text("Nothing to change: the next block starts as planned.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
        } else if let applied = nextStore.applied, nextStore.isApplied(from: archive.start) {
            AppliedChangesView(adjustments: applied, blockNumber: nextNumber) { undo() }
        } else if let nextBlock {
            ForEach(report.next) { change in
                Toggle(isOn: binding(for: change.id)) {
                    BlockChangeRow(change: change)
                }
                .tint(Theme.lifting)
            }
            Button {
                apply(to: nextBlock)
            } label: {
                Text("Apply to Block \(nextNumber)")
                    .font(.subheadline.weight(.semibold))
                    // Card colour on ink: dark on light in dark mode, white on dark in light mode.
                    .foregroundStyle(Theme.card)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .disabled(off.count == report.next.count)
            Text("Changes last until Block \(nextNumber) ends. You can undo them in Past blocks.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(report.next) { change in
                BlockChangeRow(change: change)
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !off.contains(id) },
            set: { isOn in
                var updated = off
                if isOn { updated.remove(id) } else { updated.insert(id) }
                off = updated
            }
        )
    }

    private func apply(to block: BlockArchive) {
        let chosen = Set(report.next.map(\.id)).subtracting(off)
        let value = NextBlockAdjustments.make(report: report, chosen: chosen, sourceStart: archive.start,
                                              blockStart: block.start, finishedTargets: archive.weeklyTargets)
        nextStore.apply(value)
        // This week's set targets take the new sets now.
        plans.redoVolume()
        plans.refreshVolume(muscles: muscles)
    }

    private func undo() {
        nextStore.undo(thisWeek: WeeklyPlan.weekStart(containing: .now))
        plans.redoVolume()
        plans.refreshVolume(muscles: muscles)
    }
}

/// What a report changed, with Undo: in the report and in Past blocks.
struct AppliedChangesView: View {
    let adjustments: NextBlockAdjustments
    let blockNumber: Int
    let onUndo: () -> Void

    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applied to Block \(blockNumber)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ForEach(adjustments.summaryLines, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.primaryText)
            }
            HStack {
                Text("Ends with Block \(blockNumber).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Spacer(minLength: 8)
                Button("Undo") { confirming = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .confirmationDialog("Undo the changes from the \(adjustments.label)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Undo changes", role: .destructive) { onUndo() }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("This week's set targets are worked out again. Sets already added in earlier weeks come off this week.")
        }
    }
}

/// Past blocks: the report changes the running block uses, with Undo.
struct AppliedBlockRow: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(MuscleModel.self) private var muscles
    @State private var nextStore = NextBlockStore.shared
    @State private var history = BlockHistoryStore.shared

    var body: some View {
        if let applied = nextStore.applied {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(text: "Applied from Block \(applied.sourceNumber) report", color: Theme.liftingText)
                AppliedChangesView(adjustments: applied, blockNumber: history.finished.count + 1) {
                    nextStore.undo(thisWeek: WeeklyPlan.weekStart(containing: .now))
                    plans.redoVolume()
                    plans.refreshVolume(muscles: muscles)
                }
            }
            .card()
        }
    }
}
