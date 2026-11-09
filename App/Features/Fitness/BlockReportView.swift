import SwiftUI
import SwiftData
import HealthKit
import AppCore

// The end-of-block report: sessions and weeks kept, volume against the last
// block, how the main lifts moved, records, hard sets per muscle against the
// block's targets, body weight and HRV when Health has them, and what the
// next block changes. Shown once when a new block starts (`BlockReportCover`)
// and from Fitness › Past blocks. The maths and its evidence are in
// `BlockReport` (AppCore); the block's dates and targets are kept by
// `BlockHistoryStore`.

// MARK: - Presenting once at the next block's start

/// Shows the finished block's report once, a moment after the new block
/// starts (`BlockHistoryStore.pendingReport`); closing it marks it seen.
struct BlockReportCover: ViewModifier {
    @State private var store = BlockHistoryStore.shared
    @State private var shown: BlockArchive?

    func body(content: Content) -> some View {
        content
            .sheet(item: $shown, onDismiss: { store.markSeen() }) { archive in
                BlockReportSheet(archive: archive)
            }
            .task(id: store.pendingReport?.start) {
                guard store.pendingReport != nil, shown == nil else { return }
                // Let launch-time sheets (onboarding, a reminder's sheet) go first.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let pending = store.pendingReport else { return }
                shown = pending
            }
    }
}

/// The report in its own navigation stack, with Done.
struct BlockReportSheet: View {
    let archive: BlockArchive
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            BlockReportView(archive: archive)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Report

struct BlockReportView: View {
    let archive: BlockArchive

    @Environment(GymStore.self) private var gym
    @Environment(ExerciseLibrary.self) private var library
    @Environment(BiologyModel.self) private var biology
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Query(sort: \WorkoutSession.startedAt) private var sessions: [WorkoutSession]
    @State private var data: BlockReportData?

    private var unit: WeightUnit { gym.liftingUnit }
    private var number: Int { BlockHistoryStore.shared.number(of: archive) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let data {
                    BlockReportContent(data: data, archive: archive, unit: unit, bodyUnit: settings.weightUnit)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .lockedToScreenWidth()
        }
        .background(alignment: .top) {
            TopGlow(colors: [Theme.Wash.lavender, Theme.Wash.sky, Theme.Wash.mint])
        }
        .background(Theme.background)
        .navigationTitle("Block \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let data {
                    ShareLink(item: shareText(data.report)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: sessions.count) {
            let weights = await loadBodyWeight()
            data = makeData(bodyWeight: weights)
        }
    }

    private func shareText(_ report: BlockReport.Report) -> String {
        let unit = self.unit
        return BlockReport.shareText(report) { PRFormat.weight($0, unit) }
    }

    // MARK: Data

    private func makeData(bodyWeight: [DayValue]) -> BlockReportData {
        let store = BlockHistoryStore.shared
        let logged = LiftRecordInputs.sessions(sessions)
        let traits = LiftRecordInputs.traits(logged, library: library)
        let planner = gym.planner
        var muscles: [String: BlockReport.ExerciseMuscles] = [:]
        var alternatives: [String: [CatalogExercise]] = [:]
        for id in Set(logged.flatMap { $0.exercises.map(\.exerciseID) }) {
            if let info = library.exercise(id: id) {
                muscles[id] = BlockReport.ExerciseMuscles(primary: info.primaryMuscles, secondary: info.secondaryMuscles)
            }
            if let slot = ExerciseCatalog.slot(for: id) {
                alternatives[id] = planner.alternatives(for: slot)
            }
        }
        let hrv = biology.hrvSeries.map { DayValue(date: $0.date, value: $0.value) }
        let input = BlockReport.Input(
            number: store.number(of: archive), start: archive.start, end: archive.end, length: archive.length,
            hadDeload: archive.reachedDeload, style: archive.style, weeks: archive.weeks, sessions: logged,
            previous: store.previous(before: archive)?.interval, muscles: muscles,
            weeklyTargets: archive.weeklyTargets, bodyWeightKg: bodyWeight, hrv: hrv,
            alternatives: alternatives, traits: traits
        )
        return BlockReportData(report: BlockReport.make(input), traits: traits, isComplete: archive.isComplete)
    }

    /// Daily body weight (kg) from Apple Health since the block began; empty
    /// without access or for blocks more than about a year old.
    private func loadBodyWeight() async -> [DayValue] {
        guard let health else { return [] }
        let days = (Calendar.current.dateComponents([.day], from: archive.start, to: .now).day ?? 0) + 1
        guard days > 0, days <= 400 else { return [] }
        let series = (try? await health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: days, cumulative: false)) ?? []
        return series.map { DayValue(date: $0.date, value: $0.value) }
    }
}

struct BlockReportData {
    var report: BlockReport.Report
    var traits: [String: PRHistory.Traits]
    var isComplete: Bool
}

private struct BlockReportContent: View {
    let data: BlockReportData
    let archive: BlockArchive
    let unit: WeightUnit
    let bodyUnit: WeightUnit

    var body: some View {
        let report = data.report
        BlockHeroCard(report: report, unit: unit, isComplete: data.isComplete)
        if !report.lifts.isEmpty {
            BlockLiftsCard(lifts: report.lifts, traits: data.traits, unit: unit)
        }
        if !report.muscles.isEmpty {
            BlockMusclesCard(lines: report.muscles)
        }
        if !report.records.isEmpty {
            BlockRecordsCard(records: report.records, traits: data.traits, unit: unit)
        }
        if report.bodyWeight != nil || report.hrv != nil {
            BlockTrendsCard(bodyWeight: report.bodyWeight, hrv: report.hrv, bodyUnit: bodyUnit)
        }
        // Toggles and "Apply to next block" for the latest block (`BlockApplyCard`).
        BlockApplyCard(report: report, archive: archive)
        BlockEvidence()
    }
}

// MARK: - Cards

private struct BlockHeroCard: View {
    let report: BlockReport.Report
    let unit: WeightUnit
    let isComplete: Bool

    private var dates: String {
        let last = report.end.addingTimeInterval(-86_400)
        let first = report.start.formatted(.dateTime.day().month(.abbreviated))
        return "\(first) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardLabel(text: "Block \(report.number) · \(dates)", color: Theme.liftingText)
            keptLine
            HStack(alignment: .top, spacing: 12) {
                StatView(label: "Sessions", value: "\(report.sessionsDone) of \(report.sessionsPlanned)")
                StatView(label: "Lifted", value: PRFormat.volume(report.volumeKg, unit), detail: volumeDetail)
                StatView(label: "Records", value: "\(report.records.count)")
            }
            if !isComplete {
                Text("This block was restarted before its planned end.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.lifting)
    }

    @ViewBuilder private var keptLine: some View {
        if report.weeksPlanned > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(report.weeksKept) of \(report.weeksPlanned)")
                    .heroNumberFont()
                    .foregroundStyle(Theme.primaryText)
                Text("weeks kept")
                    .font(Theme.Typography.heroUnit)
                    .foregroundStyle(Theme.secondaryText)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("\(report.weeksRun) weeks · no weekly plan saved")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
        }
    }

    private var volumeDetail: String? {
        guard let change = report.volumeChange else { return nil }
        let percent = Int((change * 100).rounded())
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent)% a week vs last block"
    }
}

private struct BlockLiftsCard: View {
    let lifts: [BlockReport.LiftChange]
    let traits: [String: PRHistory.Traits]
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "Main lifts", color: Theme.liftingText)
            Text("Best estimated 1RM, first two weeks against the last two before the deload.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lifts) { lift in
                NavigationLink {
                    LiftProgressView(exerciseID: lift.exerciseID, name: lift.name)
                } label: {
                    BlockLiftRow(lift: lift, perHand: traits[lift.exerciseID]?.isPerHand ?? false, unit: unit)
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

private struct BlockLiftRow: View {
    let lift: BlockReport.LiftChange
    let perHand: Bool
    let unit: WeightUnit

    private var values: String {
        if lift.isBodyweight { return "\(Int(lift.start)) → \(Int(lift.end)) reps" }
        let start = unit.format(lift.start)
        let end = PRFormat.weight(lift.end, unit, perHand: perHand)
        return "\(start) → \(end)"
    }

    private var chipText: String {
        if lift.isStalled && lift.change > -BlockReport.stallFraction { return "No clear change" }
        let percent = (lift.change * 100).formatted(.number.precision(.fractionLength(0...1)))
        let sign = lift.change > 0 ? "+" : ""
        return "\(sign)\(percent)%"
    }

    private var chipColor: Color {
        if lift.change >= BlockReport.stallFraction { return Theme.recoveryHigh }
        return lift.change > -BlockReport.stallFraction ? Theme.secondaryText : Theme.recoveryModerate
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(lift.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(values)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Sparkline(values: lift.points.map { DatedValue(date: $0.date, value: $0.value) }, color: Theme.lifting, showsArea: false)
                .frame(width: 72, height: 30)
            Chip(text: chipText, color: chipColor)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows this lift's progress")
    }
}

private struct BlockMusclesCard: View {
    let lines: [BlockReport.MuscleLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Hard sets per muscle", color: Theme.liftingText)
            Text("Average a week, deload left out, against the block's target.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            ForEach(lines) { line in
                BlockMuscleRow(line: line)
            }
        }
        .card()
    }
}

private struct BlockMuscleRow: View {
    let line: BlockReport.MuscleLine

    private var color: Color {
        switch line.status {
        case .under: Theme.recoveryModerate
        case .inRange: Theme.recoveryHigh
        case .over: Theme.oxygen
        }
    }

    private var statusText: String {
        switch line.status {
        case .under: "Under"
        case .inRange: "On target"
        case .over: "Over"
        }
    }

    var body: some View {
        let top = Double(max(line.target.upperBound, 1))
        let average = line.averageSets.formatted(.number.precision(.fractionLength(0...1)))
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.muscle.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text("\(average) of \(line.target.lowerBound)–\(line.target.upperBound) · \(statusText)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textColor(for: color))
            }
            ProgressView(value: min(line.averageSets, top), total: top)
                .tint(color)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BlockRecordsCard: View {
    let records: [BlockReport.BlockRecord]
    let traits: [String: PRHistory.Traits]
    let unit: WeightUnit
    /// Records listed before "and N more" (app choice, to keep the page short).
    private static let shown = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Personal records", color: Theme.liftingText)
            ForEach(Array(records.prefix(Self.shown))) { record in
                recordRow(record)
            }
            if records.count > Self.shown {
                Text("and \(records.count - Self.shown) more")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func recordRow(_ record: BlockReport.BlockRecord) -> some View {
        let trait = traits[record.exerciseID] ?? PRHistory.Traits()
        let text = PRFormat.record(record.record, unit: unit, traits: trait)
        return VStack(alignment: .leading, spacing: 1) {
            Text(record.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            Text("\(text) · \(record.date.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BlockTrendsCard: View {
    let bodyWeight: BlockReport.Trend?
    let hrv: BlockReport.Trend?
    let bodyUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "Body", color: Theme.liftingText)
            HStack(alignment: .top, spacing: 12) {
                if let bodyWeight {
                    StatView(label: "Body weight", value: weightText(bodyWeight), detail: "first week → last week")
                }
                if let hrv {
                    StatView(label: "HRV", value: hrvText(hrv), detail: "7-night averages")
                }
            }
        }
        .card()
    }

    private func weightText(_ trend: BlockReport.Trend) -> String {
        "\(bodyUnit.format(trend.start)) → \(bodyUnit.format(trend.end)) \(bodyUnit.rawValue)"
    }

    private func hrvText(_ trend: BlockReport.Trend) -> String {
        "\(Int(trend.start.rounded())) → \(Int(trend.end.rounded())) ms"
    }
}

/// One suggestion: icon, what changes and why (also the label of its toggle in `BlockApplyCard`).
struct BlockChangeRow: View {
    let change: BlockReport.NextChange

    private var icon: String {
        switch change.kind {
        case .addSets: "plus.circle.fill"
        case .swapExercise: "arrow.triangle.2.circlepath"
        case .repRange: "number.circle.fill"
        case .volumeUp: "arrow.up.right.circle.fill"
        case .holdVolume: "equal.circle.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.liftingText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(change.text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(change.why)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BlockEvidence: View {
    var body: some View {
        EvidenceDisclosure(points: [
            "A week counts as kept at 3 of every 4 planned sessions, as on the consistency score.",
            "Lift change compares the best estimated 1RM of the first two weeks with the last two working weeks. The estimate is about ±3 kg, so under 1% reads as no clear change.",
            "Hard sets per muscle: 10-20 a week builds the most muscle for most people (Schoenfeld et al. 2017), with smaller gains past 20 (Pelland et al. 2026).",
            "Changing the stimulus between blocks is standard periodisation (ACSM position stand, Ratamess et al. 2009). Heavier sets favour 1RM strength (Schoenfeld et al. 2017); adding reps works about as well as adding weight (Plotkin et al. 2022); some exercise variation helps (Kassiano et al. 2022).",
        ])
        .card()
    }
}

// MARK: - Past blocks

/// Every finished block, newest first, each opening its report.
struct PastBlocksView: View {
    @State private var store = BlockHistoryStore.shared

    var body: some View {
        let finished = Array(store.finished.reversed())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let current = store.current {
                    CurrentBlockRow(archive: current, number: store.finished.count + 1)
                }
                // Changes applied from the last report, with Undo (`NextBlockStore`).
                AppliedBlockRow()
                if finished.isEmpty {
                    ContentUnavailableView(
                        "No finished blocks yet",
                        systemImage: "square.stack.3d.up",
                        description: Text("When this training block ends, its report shows up here.")
                    )
                } else {
                    PastBlocksList(blocks: finished, store: store)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle("Past blocks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PastBlocksList: View {
    let blocks: [BlockArchive]
    let store: BlockHistoryStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(blocks) { block in
                NavigationLink {
                    BlockReportView(archive: block)
                } label: {
                    RecordsLinkRow(title: "Block \(store.number(of: block))", detail: PastBlockText.detail(block),
                                   systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.plain)
                if block.id != blocks.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
        }
        .card()
    }
}

private struct CurrentBlockRow: View {
    let archive: BlockArchive
    let number: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardLabel(text: "In progress", color: Theme.liftingText)
            Text("Block \(number) · week \(archive.weeksRun) of \(archive.length)")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text("Started \(archive.start.formatted(.dateTime.day().month(.abbreviated))). Its report comes when it ends.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

private enum PastBlockText {
    /// "6 Jan – 9 Feb · 4 of 5 weeks kept", "ended early" when restarted.
    static func detail(_ block: BlockArchive) -> String {
        let last = block.end.addingTimeInterval(-86_400)
        let first = block.start.formatted(.dateTime.day().month(.abbreviated))
        let dates = "\(first) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        let planned = block.weeks.filter { $0.planned > 0 }
        let kept = planned.filter { Consistency.weekKept(planned: $0.planned, done: $0.done) }.count
        var parts = [dates]
        if !planned.isEmpty { parts.append("\(kept) of \(planned.count) weeks kept") }
        if !block.isComplete { parts.append("ended early") }
        return parts.joined(separator: " · ")
    }
}
