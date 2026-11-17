import Foundation

/// "How did it feel?": one optional answer per workout about how the session
/// felt while it was being done (write-up in
/// docs/research/mind-and-prevention-2026-11.md).
///
/// What the evidence says, and what this can and cannot tell:
/// - How people feel *during* moderate exercise predicts later activity; how
///   they feel *afterwards* does not (Rhodes & Kates, Ann Behav Med
///   2015;49:715, 24 studies). So the question asks about the session while
///   it was happening, not about now.
/// - The usual tool in that literature is the Feeling Scale (Hardy & Rejeski,
///   J Sport Exerc Psychol 1989;11:304): one item, 11 points from +5 to −5,
///   asked during exercise. Its anchors as usually printed are very good (+5),
///   good (+3), fairly good (+1), neutral (0), fairly bad (−1), bad (−3) and
///   very bad (−5) (from memory; the paper was not re-read, and its terms of
///   use were not confirmed). It is feasible in resistance training, with no
///   agreed timing (Bastos et al., PLoS One 2023;18:e0294529, 27 studies).
/// - What this app adapted: five plain words instead of eleven points, its
///   own question, and one answer recalled just after the session instead of
///   several during it. That makes it a recall, not the Feeling Scale: it is
///   not validated, and the values −5...5 are kept only so the five words sit
///   on the same good-bad line. Feelings rebound once a set ends (Cavarretta,
///   Hall & Bixby, Front Sports Act Living 2019;1:5), and a remembered session
///   leans on how it ended (Zenko, Ekkekakis & Ariely, J Sport Exerc Psychol
///   2016;38:149), so a recall probably reads kinder than the sets felt.
/// - It is a single person's trend. It does not predict anything by itself:
///   the review above found a link in groups, mostly for aerobic exercise at
///   moderate intensity, not a rule for one lifter.
///
/// Per-set effort is already rated (`SetFeedback`, reps left and RPE), so
/// this is about pleasure, not effort, and is never asked per set.
public enum SessionFeel: Int, Codable, Sendable, CaseIterable, Identifiable {
    case veryBad = -5
    case bad = -3
    case neutral = 0
    case good = 3
    case veryGood = 5

    public var id: Int { rawValue }

    /// The app's own question (not the Feeling Scale's instructions).
    public static let question = "How did the session feel while you were lifting?"
    /// One line under the question.
    public static let hint = "Optional. Not how hard it was: how good or bad it felt."

    public var title: String {
        switch self {
        case .veryBad: "Very bad"
        case .bad: "Bad"
        case .neutral: "Neutral"
        case .good: "Good"
        case .veryGood: "Very good"
        }
    }

    /// 1 (very bad) ... 5 (very good), for a five-button row.
    public var step: Int {
        switch self {
        case .veryBad: 1
        case .bad: 2
        case .neutral: 3
        case .good: 4
        case .veryGood: 5
        }
    }

    public init?(step: Int) {
        guard let match = Self.allCases.first(where: { $0.step == step }) else { return nil }
        self = match
    }

    public var isBad: Bool { rawValue < 0 }
    public var isGood: Bool { rawValue > 0 }
}

/// One session's answer, keyed by the session's start.
public struct SessionFeelEntry: Codable, Sendable, Equatable, Identifiable {
    public var sessionStart: Date
    public var feel: SessionFeel

    public var id: Date { sessionStart }

    public init(sessionStart: Date, feel: SessionFeel) {
        self.sessionStart = sessionStart
        self.feel = feel
    }
}

/// The trend over recent sessions and the one rule built on it.
public enum SessionFeelTrend {
    /// "For weeks": the last four weeks (app's choice).
    public static let windowDays = 28
    /// Rated sessions needed before anything is said (app's choice: fewer is noise).
    public static let minimumRated = 4
    /// The rated sessions must span at least this long, so one bad week
    /// doesn't count as "weeks" (app's choice).
    public static let minimumSpanDays = 14
    /// "Felt bad": at least this share rated bad or very bad, and the average below neutral (app's choice).
    public static let badShare = 0.5
    /// Ratings shown on the chart.
    public static let chartCount = 20

    public struct Summary: Sendable, Equatable {
        public var rated: Int
        public var good: Int
        public var bad: Int
        /// Mean of the −5...5 values.
        public var average: Double
        /// Days from the first to the last rated session.
        public var spanDays: Int
        /// Sessions have felt bad on balance across at least two weeks.
        public var feltBad: Bool

        /// "Felt good in 5 of your last 7 rated sessions."
        public var text: String {
            if feltBad { return "Felt bad in \(bad) of your last \(rated) rated sessions." }
            if good * 2 >= rated { return "Felt good in \(good) of your last \(rated) rated sessions." }
            return "Mixed: good in \(good) and bad in \(bad) of your last \(rated) rated sessions."
        }
    }

    /// The summary of the ratings between `start` and `end`; nil with fewer
    /// than `minimumRated`.
    public static func summary(_ entries: [SessionFeelEntry], from start: Date, to end: Date) -> Summary? {
        let inside = entries.filter { $0.sessionStart >= start && $0.sessionStart <= end }.sorted { $0.sessionStart < $1.sessionStart }
        guard inside.count >= minimumRated, let first = inside.first, let last = inside.last else { return nil }
        let bad = inside.filter(\.feel.isBad).count
        let good = inside.filter(\.feel.isGood).count
        let average = Double(inside.map(\.feel.rawValue).reduce(0, +)) / Double(inside.count)
        let span = Int((last.sessionStart.timeIntervalSince(first.sessionStart) / 86_400).rounded(.down))
        let feltBad = span >= minimumSpanDays && Double(bad) >= Double(inside.count) * badShare && average < 0
        return Summary(rated: inside.count, good: good, bad: bad, average: average, spanDays: span, feltBad: feltBad)
    }

    /// The last `windowDays` days up to `now`.
    public static func recent(_ entries: [SessionFeelEntry], now: Date) -> Summary? {
        summary(entries, from: now.addingTimeInterval(-Double(windowDays) * 86_400), to: now)
    }

    /// Sessions have felt bad for weeks (`Summary.feltBad` over the last four weeks).
    public static func feltBadForWeeks(_ entries: [SessionFeelEntry], now: Date) -> Bool {
        recent(entries, now: now)?.feltBad ?? false
    }

    /// The newest `chartCount` ratings, oldest first, as −5...5 values.
    public static func points(_ entries: [SessionFeelEntry]) -> [DayValue] {
        entries.sorted { $0.sessionStart < $1.sessionStart }.suffix(chartCount)
            .map { DayValue(date: $0.sessionStart, value: Double($0.feel.rawValue)) }
    }

    /// What can be tried when sessions have felt bad for weeks. Each line
    /// names its study; all of it is offered, none applied.
    /// - Ending on lighter work: sessions that got lighter towards the end
    ///   were felt and remembered as more pleasant than the same work in
    ///   rising order (Hutchinson et al., J Sport Exerc Psychol 2020;42:143,
    ///   40 adults, single sessions).
    /// - Intensity: pleasure falls as intensity rises past the point where
    ///   breathing gets hard, and holds up better when the intensity is
    ///   self-chosen (Ekkekakis, Parfitt & Petruzzello, Sports Med
    ///   2011;41:641; mostly aerobic exercise).
    /// - Variety: varying exercises gave the same gains and better motivation
    ///   in 21 trained men over eight weeks (Baz-Valle et al., PLoS One 2019;
    ///   carried from docs/research/healthy-living-2026-11.md).
    public static let options: [String] = [
        "Finish on your lighter lifts: sessions that eased off towards the end were remembered as more pleasant (Hutchinson 2020, 40 adults).",
        "Pick the short version or leave a rep more in reserve for a week or two: harder effort feels worse, and choosing the effort yourself helps (Ekkekakis 2011, mostly cardio studies).",
        "Change one accessory lift at the next block: variety kept gains and helped motivation in trained lifters (Baz-Valle 2019, 21 men).",
    ]

    /// One line for the on-device coach, in training-log words; nil with too few ratings.
    public static func coachLine(_ entries: [SessionFeelEntry], now: Date) -> String? {
        guard let summary = recent(entries, now: now) else { return nil }
        let last = entries.sorted { $0.sessionStart < $1.sessionStart }.suffix(5).map { $0.feel.title.lowercased() }
        let tail = summary.feltBad
            ? " Sessions have felt bad for weeks: suggest the short version, finishing on lighter lifts, or a change of one accessory lift."
            : ""
        return "How recent sessions felt while training (user's own rating, oldest first): \(last.joined(separator: ", ")).\(tail)"
    }
}

// MARK: - End-of-block report

extension BlockReport {
    /// The first lifts on the report (the most-trained main lifts,
    /// `PRHistory.rank`) are never offered for a variety swap (app's choice).
    static let keptMainLifts = 3

    /// Adds how the block's sessions felt to the report and, when they felt
    /// bad on balance (`SessionFeelTrend.Summary.feltBad`), changes what the
    /// next block is offered. Both changes are the app's choices, offered
    /// like every other next-block change (`NextChange.isAppChoice`):
    /// - no "one more set a week" on top of sessions that felt bad (no trial
    ///   tests this; harder work feels worse, Ekkekakis et al., Sports Med 2011);
    /// - one swap of a lift that is not a main lift, for variety (same gains
    ///   and better motivation with varied selection in 21 trained men:
    ///   Baz-Valle et al., PLoS One 2019; frequent rotation is not advised,
    ///   Kassiano et al., J Strength Cond Res 2022, so one lift only).
    static func applyFeel(_ report: inout Report, entries: [SessionFeelEntry], alternatives: [String: [CatalogExercise]]?) {
        let inBlock = entries.filter { $0.sessionStart >= report.start && $0.sessionStart < report.end }
        guard let summary = SessionFeelTrend.summary(inBlock, from: report.start, to: report.end) else { return }
        report.feel = summary
        guard summary.feltBad else { return }
        let seen = "Sessions felt bad in \(summary.bad) of \(summary.rated) rated this block."

        let volumeUp = report.next.firstIndex { change in
            if case .volumeUp = change.kind { return true }
            return false
        }
        if let volumeUp {
            report.next[volumeUp] = NextChange(
                kind: .holdVolume, text: "Same volume next block",
                why: "\(seen) The app doesn't add sets on top of that. This is the app's choice; no trial tests it."
            )
        }

        var changed = Set<String>()
        for change in report.next {
            switch change.kind {
            case .swapExercise(let fromID, _, _): changed.insert(fromID)
            case .repRange(let exerciseID, _): changed.insert(exerciseID)
            default: break
            }
        }
        for lift in report.lifts.dropFirst(keptMainLifts).reversed() where !changed.contains(lift.exerciseID) {
            let options = alternatives?[lift.exerciseID]
                ?? ExerciseCatalog.slot(for: lift.exerciseID).flatMap { ExerciseCatalog.options[$0] }
                ?? []
            guard let swap = options.first(where: { $0.id != lift.exerciseID }) else { continue }
            report.next.append(NextChange(
                kind: .swapExercise(fromID: lift.exerciseID, toID: swap.id, toName: swap.name),
                text: "Swap \(lift.name) for \(swap.name) for a change",
                why: "\(seen) Varying exercises kept gains and helped motivation in trained lifters (Baz-Valle 2019, 21 men). One lift, not all."
            ))
            break
        }
    }
}
