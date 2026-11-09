import Foundation
import AppCore

/// One training block as it ran: dates, planned and done sessions per week,
/// and the weekly set targets the planner gave each muscle. Kept after the
/// block ends, because `WeeklyPlanStore` keeps only the current block, 12 weeks
/// of plans and two weeks of targets. The report itself is worked out again
/// from the logged sessions each time it opens (`BlockReport`).
nonisolated struct BlockArchive: Codable, Sendable, Equatable, Identifiable {
    /// Monday the block began.
    var start: Date
    /// The Monday after its last week run (exclusive).
    var end: Date
    var style: TrainingStyle
    /// Planned weeks, deload included.
    var length: Int
    /// Weeks it ran, held weeks included.
    var weeksRun: Int
    var reachedDeload: Bool
    var weeks: [WeekRecord]
    var targets: [WeekTargetsSnapshot]

    var id: Date { start }
    var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }
    /// Ran to its planned end (or its deload), rather than restarting early.
    var isComplete: Bool { reachedDeload || weeksRun >= length }
    /// Muscle → weekly sets, one entry per working week that had targets (no deload).
    var weeklyTargets: [[Muscle: Int]] {
        targets.filter { !$0.isDeload }.map { snapshot in
            var result: [Muscle: Int] = [:]
            for (raw, sets) in snapshot.sets {
                if let muscle = Muscle(rawValue: raw) { result[muscle] = sets }
            }
            return result
        }
    }
}

/// A week's per-muscle set targets (`VolumeProgression.WeekTargets`), with
/// muscles stored by raw value so the JSON stays a plain object.
nonisolated struct WeekTargetsSnapshot: Codable, Sendable, Equatable {
    var weekStart: Date
    var isDeload: Bool
    var sets: [String: Int]
}

/// Finished training blocks, saved as JSON in Application Support. The app
/// calls `observe` after each refresh; when the block it was following has
/// been replaced by a new one, the old one is archived and, if it ran to its
/// end, its report is queued to show once (`pendingReport`).
@Observable
final class BlockHistoryStore {
    static let shared = BlockHistoryStore()

    private struct Saved: Codable {
        var finished: [BlockArchive] = []
        var current: BlockArchive? = nil
        /// Start of the finished block whose report hasn't been seen yet.
        var unseen: Date? = nil
    }

    /// A block shorter than this (restarted after a week) isn't kept (app choice).
    static let minimumWeeks = 2

    private var saved = Saved()

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "blockhistory.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    /// Finished blocks, oldest first.
    var finished: [BlockArchive] { saved.finished.sorted { $0.start < $1.start } }

    /// The block in progress, as far as it has run.
    var current: BlockArchive? { saved.current }

    /// 1-based, counting finished blocks in order; the current block is next.
    func number(of archive: BlockArchive) -> Int {
        let list = finished
        return (list.firstIndex { $0.start == archive.start } ?? list.count) + 1
    }

    /// The finished block just before this one.
    func previous(before archive: BlockArchive) -> BlockArchive? {
        finished.last { $0.start < archive.start }
    }

    /// The report to show once at the start of the next block.
    var pendingReport: BlockArchive? {
        guard let unseen = saved.unseen else { return nil }
        return saved.finished.first { $0.start == unseen }
    }

    func markSeen() {
        guard saved.unseen != nil else { return }
        saved.unseen = nil
        write()
    }

    /// Follows the current block (`WeeklyPlanStore.block` after `refreshBlock`).
    /// `records` are the plan's weeks (`WeeklyPlanStore.records`), `targets`
    /// this week's per-muscle targets (`WeeklyPlanStore.volumeTargets`).
    /// Call from a task, never from a view body: it may write.
    func observe(block: TrainingBlock?, records: [WeekRecord], targets: VolumeProgression.WeekTargets?,
                 calendar: Calendar = .current) {
        guard let block else { return }
        var changed = false
        if let following = saved.current, !calendar.isDate(following.start, inSameDayAs: block.start) {
            archive(following, nextStart: block.start, records: records, calendar: calendar)
            saved.current = nil
            changed = true
        }
        let updated = updatedCurrent(block: block, records: records, targets: targets, calendar: calendar)
        if updated != saved.current {
            saved.current = updated
            changed = true
        }
        if changed { write() }
    }

    private func archive(_ block: BlockArchive, nextStart: Date, records: [WeekRecord], calendar: Calendar) {
        var ended = block
        let weekEnd = calendar.date(byAdding: .day, value: 7 * max(1, block.weeksRun), to: block.start) ?? block.start
        ended.end = min(nextStart, weekEnd)
        ended.weeks = Self.merged(block.weeks, records, from: ended.start, to: ended.end)
        guard ended.weeksRun >= Self.minimumWeeks, ended.start < nextStart else { return }
        saved.finished.removeAll { calendar.isDate($0.start, inSameDayAs: ended.start) }
        saved.finished.append(ended)
        if ended.isComplete { saved.unseen = ended.start }
    }

    private func updatedCurrent(block: TrainingBlock, records: [WeekRecord], targets: VolumeProgression.WeekTargets?,
                                calendar: Calendar) -> BlockArchive {
        var current = saved.current ?? BlockArchive(
            start: block.start, end: block.start, style: block.style, length: block.length,
            weeksRun: 1, reachedDeload: false, weeks: [], targets: []
        )
        current.style = block.style
        current.length = block.length
        current.weeksRun = max(current.weeksRun, block.week.week + block.heldWeeks)
        current.reachedDeload = current.reachedDeload || block.week.isDeload
        current.end = calendar.date(byAdding: .day, value: 7 * current.weeksRun, to: current.start) ?? current.start
        current.weeks = Self.merged(current.weeks, records, from: current.start, to: current.end)
        if let targets, block.covers(weekStart: targets.weekStart, calendar: calendar) {
            var sets: [String: Int] = [:]
            for target in targets.targets { sets[target.muscle.rawValue] = target.sets }
            let snapshot = WeekTargetsSnapshot(weekStart: targets.weekStart, isDeload: block.week.isDeload, sets: sets)
            current.targets.removeAll { calendar.isDate($0.weekStart, inSameDayAs: targets.weekStart) }
            current.targets.append(snapshot)
            current.targets.sort { $0.weekStart < $1.weekStart }
        }
        return current
    }

    /// Saved weeks with the newest counts for each week inside `start..<end`.
    private static func merged(_ old: [WeekRecord], _ new: [WeekRecord], from start: Date, to end: Date) -> [WeekRecord] {
        var byWeek: [Date: WeekRecord] = [:]
        for record in old + new where record.weekStart >= start && record.weekStart < end {
            byWeek[record.weekStart] = record
        }
        return byWeek.values.sorted { $0.weekStart < $1.weekStart }
    }

    private func write() {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
