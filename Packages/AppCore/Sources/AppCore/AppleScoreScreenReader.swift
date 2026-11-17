import Foundation

/// Finds Apple's Readiness, Sleep score and Health Age in the text recognised
/// from a screenshot of the Health, Vitals, Sleep or Readiness screens.
///
/// Apple publishes no description of these screens, so nothing here depends on
/// one layout. A number only becomes a candidate when it sits next to a label
/// for it: on the same line ("Readiness 7"), or as a line of its own directly
/// below or above the label. Every candidate says which label it was next to,
/// and the app shows that to the owner to confirm or correct before anything
/// is saved. A number that could belong to two labels, or two different
/// numbers for one label, is never picked silently (`Result.best`).
///
/// Assumed about the wording (all of it unverified against a real screen):
/// - the labels contain "Readiness", "Sleep Score" and "Health Age" in English
///   (any case); a bare "Sleep" title only counts with a sleep level word
///   beside the number, and then only as a low-confidence candidate;
/// - a score is written as a whole number, optionally as "7/10", "7 of 10",
///   "82/100" or "34 years", optionally with Apple's level word beside it
///   ("Ready", "High");
/// - the level words are the ones in Apple's support pages
///   (`AppleReadinessLevel`, `AppleSleepScoreLevel`), plus "Excellent", which
///   early reports of the Sleep score used.
public enum AppleScoreScreenReader {
    /// A recognised line's place in the image, as fractions of its size, with
    /// the origin at the top left (Vision's own origin is the bottom left).
    public struct Box: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midX: Double { x + width / 2 }
        var midY: Double { y + height / 2 }
    }

    /// One line of recognised text. Without boxes the lines are taken to be
    /// in reading order.
    public struct Line: Sendable, Equatable {
        public var text: String
        public var box: Box?

        public init(_ text: String, box: Box? = nil) {
            self.text = text
            self.box = box
        }
    }

    /// Where the number was, relative to its label.
    public enum Placement: String, Sendable, Equatable {
        case sameLine
        case below
        case above

        /// For the confirmation screen: "next to", "below", "above".
        public var words: String {
            switch self {
            case .sameLine: "next to"
            case .below: "below"
            case .above: "above"
            }
        }
    }

    public enum Confidence: Int, Sendable, Comparable {
        /// Shown as an option, never filled in.
        case low
        /// One clear number beside a clear label.
        case high

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Why a candidate is only low confidence.
    public enum Doubt: String, Sendable, Equatable {
        /// The level word beside it doesn't fit the number ("Ready" beside 9).
        case levelMismatch
        /// The label was only "Sleep", not "Sleep Score".
        case weakLabel
        /// Numbers both above and below the label, and nothing to tell which is its own.
        case twoNumbers
        /// Much smaller print than its label (an axis label, a footnote).
        case smallPrint
        /// The number also sits right under another label, which it more likely belongs to.
        case sharedNumber

        /// One short sentence for the confirmation screen.
        public var words: String {
            switch self {
            case .sharedNumber: "It may belong to the label above it."
            case .levelMismatch: "The word beside it doesn't fit this number."
            case .weakLabel: "The label only said Sleep."
            case .twoNumbers: "There was a number on both sides of the label."
            case .smallPrint: "It was in much smaller print than the label."
            }
        }
    }

    public struct Candidate: Sendable, Equatable, Identifiable {
        public var kind: AppleScoreKind
        public var value: Int
        /// The label as it was read, e.g. "Sleep Score".
        public var label: String
        /// The text the number came from, as it was read, e.g. "82" or "7/10".
        public var valueText: String
        public var placement: Placement
        public var confidence: Confidence
        /// Apple's level word seen beside the number, if any.
        public var level: String?
        public var doubts: [Doubt]

        public var id: String { "\(kind.rawValue)-\(value)" }

        /// "82, below “Sleep Score”" for the confirmation screen.
        public var summary: String {
            "\(value), \(placement.words) \u{201C}\(label)\u{201D}"
        }
    }

    public enum DayHint: String, Sendable, Equatable {
        case today
        case yesterday
    }

    public struct Result: Sendable, Equatable {
        /// Every candidate, surest first within each kind. One per kind and value.
        public var candidates: [Candidate]
        /// "Today" or "Yesterday" written on the screen, when exactly one of them is.
        public var dayHint: DayHint?
        /// Lines of text that were looked at.
        public var lineCount: Int

        public func candidates(for kind: AppleScoreKind) -> [Candidate] {
            candidates.filter { $0.kind == kind }
        }

        /// The one value to fill in for `kind`: only when every
        /// high-confidence candidate agrees on it. Otherwise nil, and the
        /// owner chooses.
        public func best(_ kind: AppleScoreKind) -> Candidate? {
            let sure = candidates(for: kind).filter { $0.confidence == .high }
            guard let first = sure.first, sure.allSatisfy({ $0.value == first.value }) else { return nil }
            return first
        }

        public var isEmpty: Bool { candidates.isEmpty }
    }

    // MARK: Reading

    public static func read(_ lines: [Line]) -> Result {
        let prepared = prepare(lines)
        var found: [Candidate] = []
        var open: [Search] = []
        // Numbers on a label's own line or row are settled at once; the rest
        // wait until the whole screen has been looked at.
        for index in prepared.indices {
            for kind in AppleScoreKind.allCases {
                guard let label = label(kind, in: prepared[index]) else { continue }
                let search = lookAround(kind, label: label, at: index, in: prepared)
                if let settled = search.settled {
                    found.append(settled)
                } else {
                    open.append(search)
                }
            }
        }
        // Which side of their labels this screen puts its numbers on: decided
        // by the labels that have a number on one side only.
        let onlyBelow = open.contains { $0.below != nil && $0.above == nil }
        let onlyAbove = open.contains { $0.above != nil && $0.below == nil }
        for position in open.indices {
            if onlyBelow, !onlyAbove { open[position].above = nil }
            if onlyAbove, !onlyBelow { open[position].below = nil }
        }
        // Still undecided: a number right under one label and right above the
        // next. Headings usually come first, so it stays with the label above
        // it; the label below keeps it only as a doubtful option, and not at
        // all when that label has a number of its own.
        for position in open.indices {
            guard let above = open[position].above else { continue }
            let takenFromAbove = open.indices.contains { $0 != position && open[$0].below?.index == above.index }
            guard takenFromAbove else { continue }
            if open[position].below != nil {
                open[position].above = nil
            } else {
                open[position].above?.isShared = true
            }
        }
        for search in open {
            found.append(contentsOf: candidates(from: search, in: prepared))
        }
        return Result(candidates: tidy(found), dayHint: dayHint(prepared), lineCount: prepared.count)
    }

    // MARK: Lines

    struct Prepared {
        var raw: String
        var tokens: [String]
        var box: Box?
    }

    /// Trims, tokenises and, when every line has a box, puts the lines in
    /// reading order (rows top to bottom, left to right within a row).
    static func prepare(_ lines: [Line]) -> [Prepared] {
        var prepared = lines.compactMap { line -> Prepared? in
            let raw = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            return Prepared(raw: raw, tokens: tokens(raw), box: line.box)
        }
        guard prepared.allSatisfy({ $0.box != nil }) else { return prepared }
        // Rows: lines whose middles are within half a line of the row's first line.
        prepared.sort { ($0.box?.midY ?? 0) < ($1.box?.midY ?? 0) }
        var rows: [[Prepared]] = []
        for line in prepared {
            if let first = rows.last?.first?.box, let box = line.box, sameRow(first, box) {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { row in row.sorted { ($0.box?.x ?? 0) < ($1.box?.x ?? 0) } }
    }

    static func sameRow(_ a: Box, _ b: Box) -> Bool {
        abs(a.midY - b.midY) < max(a.height, b.height) / 2
    }

    /// Characters stripped from the ends of a token ("Readiness:", "(Ready)").
    private static let edgePunctuation = CharacterSet(charactersIn: ":,;·•|()[]—–\u{201C}\u{201D}\"")

    /// Lowercased words and numbers. Punctuation inside a token is kept
    /// ("85%", "9:41", "7.5", "7/10"), so those never pass as a plain number.
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: edgePunctuation) }
            .filter { !$0.isEmpty && $0 != "-" }
    }

    // MARK: Labels

    private static func phrase(_ kind: AppleScoreKind) -> [String] {
        switch kind {
        case .readiness: ["readiness"]
        case .sleepScore: ["sleep", "score"]
        case .healthAge: ["health", "age"]
        }
    }

    /// Words allowed around a label on its own line ("Your Readiness", "Today's Sleep Score").
    private static let labelFillers: Set<String> = [
        "your", "my", "the", "apple", "apple's", "today", "today's", "todays", "current", "latest",
        "last", "night", "night's", "nights", "tonight's", "score", "is", "was", "of",
    ]

    /// A line longer than this that isn't "label + number" is a sentence about
    /// the score, not its label.
    private static let longestLabel = 5

    struct Label {
        var text: String
        var isWeak: Bool
        /// A value on the label's own line ("Readiness 7").
        var inline: Value?
    }

    static func label(_ kind: AppleScoreKind, in line: Prepared) -> Label? {
        let words = phrase(kind)
        guard let start = firstIndex(of: words, in: line.tokens) else {
            // "Sleep" alone as a title: a weak label for the Sleep score.
            if kind == .sleepScore, line.tokens == ["sleep"] { return Label(text: line.raw, isWeak: true, inline: nil) }
            return nil
        }
        let before = Array(line.tokens[..<start]).filter { !labelFillers.contains($0) }
        let after = Array(line.tokens[(start + words.count)...]).filter { !labelFillers.contains($0) }
        if before.isEmpty, after.isEmpty { return Label(text: line.raw, isWeak: false, inline: nil) }
        // A number on one side only, and nothing but filler on the other.
        if before.isEmpty, let value = value(kind, tokens: after) {
            return Label(text: labelText(kind), isWeak: false, inline: value)
        }
        if after.isEmpty, let value = value(kind, tokens: before) {
            return Label(text: labelText(kind), isWeak: false, inline: value)
        }
        // Other words: a short heading still counts ("Readiness Details"), a
        // sentence doesn't, and neither does a line with some other number in it.
        guard line.tokens.count <= longestLabel, !line.tokens.contains(where: hasDigit) else { return nil }
        return Label(text: line.raw, isWeak: false, inline: nil)
    }

    /// The label as Apple writes it, for a line that also holds the number.
    private static func labelText(_ kind: AppleScoreKind) -> String {
        switch kind {
        case .readiness: "Readiness"
        case .sleepScore: "Sleep Score"
        case .healthAge: "Health Age"
        }
    }

    private static func firstIndex(of words: [String], in tokens: [String]) -> Int? {
        guard !words.isEmpty, tokens.count >= words.count else { return nil }
        return (0...(tokens.count - words.count)).first { Array(tokens[$0..<($0 + words.count)]) == words }
    }

    private static func isAnyLabel(_ line: Prepared) -> Bool {
        AppleScoreKind.allCases.contains { label($0, in: line) != nil }
    }

    // MARK: Values

    struct Value: Equatable {
        var number: Int
        var level: String?
    }

    private static func levelPhrases(_ kind: AppleScoreKind) -> [[String]] {
        switch kind {
        case .readiness: [["pace", "yourself"], ["go", "for", "it"], ["recover"], ["ready"]]
        case .sleepScore: [["very", "low"], ["very", "high"], ["excellent"], ["okay"], ["low"], ["high"], ["ok"]]
        case .healthAge: []
        }
    }

    /// The level phrase `tokens` is exactly, if any.
    private static func levelOnly(_ kind: AppleScoreKind, tokens: [String]) -> String? {
        levelPhrases(kind).first { $0 == tokens }.map { $0.joined(separator: " ") }
    }

    /// Whether Apple's published bands put `number` at `level`. True for words
    /// with no published band ("excellent").
    private static func levelFits(_ kind: AppleScoreKind, level: String, number: Int) -> Bool {
        let spoken = level == "okay" ? "ok" : level
        switch kind {
        case .readiness:
            guard let match = AppleReadinessLevel.allCases.first(where: { $0.label.lowercased() == spoken }) else { return true }
            return match.range.contains(number)
        case .sleepScore:
            guard let match = AppleSleepScoreLevel.allCases.first(where: { $0.label.lowercased() == spoken }) else { return true }
            return match.range.contains(number)
        case .healthAge:
            return true
        }
    }

    private static func hasDigit(_ token: String) -> Bool {
        token.contains { $0.isASCII && $0.isNumber }
    }

    /// A plain whole number of one to three digits, no leading zero ("07" is
    /// part of a time or date).
    private static func wholeNumber(_ token: String) -> Int? {
        guard (1...3).contains(token.count), token.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        if token.count > 1, token.hasPrefix("0") { return nil }
        return Int(token)
    }

    /// The top of the scale as Apple might write it after the number ("/10", "of 100").
    private static func scaleTop(_ kind: AppleScoreKind) -> Int? {
        switch kind {
        case .readiness: 10
        case .sleepScore: 100
        case .healthAge: nil
        }
    }

    private static let yearWords: Set<String> = ["years", "year", "yrs", "yr"]

    /// Reads `tokens` as nothing but a score for `kind`: a whole number in
    /// range, optionally over its scale ("7/10", "7 of 10"), with a unit for
    /// Health Age ("34 years"), and optionally Apple's level word before or
    /// after. Anything left over (a unit, a second number, a percent sign, a
    /// time) means it is something else, and the answer is nil.
    static func value(_ kind: AppleScoreKind, tokens: [String]) -> Value? {
        var rest = tokens.filter { $0 != "score" && $0 != "today" }
        var level: String?
        for phrase in levelPhrases(kind) {
            if rest.count > phrase.count, Array(rest.suffix(phrase.count)) == phrase {
                rest.removeLast(phrase.count)
                level = phrase.joined(separator: " ")
                break
            }
            if rest.count > phrase.count, Array(rest.prefix(phrase.count)) == phrase {
                rest.removeFirst(phrase.count)
                level = phrase.joined(separator: " ")
                break
            }
        }
        guard let first = rest.first else { return nil }
        var number: Int?
        var tail = Array(rest.dropFirst())
        if let plain = wholeNumber(first) {
            number = plain
        } else if let top = scaleTop(kind) {
            // "7/10" as one token.
            let pieces = first.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if pieces.count == 2, let plain = wholeNumber(pieces[0]), wholeNumber(pieces[1]) == top { number = plain }
        }
        guard let number, kind.accepts(number) else { return nil }
        if let top = scaleTop(kind) {
            let topText = String(top)
            if tail == ["/", topText] || tail == ["of", topText] || tail == ["out", "of", topText] { tail = [] }
        } else if let unit = tail.first, yearWords.contains(unit) {
            // "34 years", "34 years old".
            tail.removeFirst()
            if tail == ["old"] { tail = [] }
        }
        guard tail.isEmpty else { return nil }
        return Value(number: number, level: level)
    }

    // MARK: Lines between a label and its number

    private static let neutralWords: Set<String> = [
        "today", "yesterday", "last", "night", "tonight", "this", "morning", "updated", "now", "at", "am", "pm", "as", "of", "on",
        "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        "january", "february", "march", "april", "june", "july", "august", "september", "october", "november", "december",
        "score", "your",
    ]

    /// A date, a time or "Today": may sit between a label and its number.
    /// Any other words are taken as another measure's label, and the search stops there.
    private static func isNeutral(_ line: Prepared) -> Bool {
        line.tokens.allSatisfy { token in
            neutralWords.contains(token) || token.allSatisfy { !$0.isLetter }
        }
    }

    /// Units and words that, right after a bare number, make it something else
    /// ("62" then "BPM"; "3" then "years younger").
    private static let unitWords: Set<String> = [
        "bpm", "ms", "hr", "hrs", "min", "mins", "sec", "secs", "kcal", "cal", "%", "steps", "km", "mi", "brpm",
        "db", "kg", "lb", "lbs", "°c", "°f", "°", "ml/kg/min", "mmhg", "breaths/min", "younger", "older",
    ]

    private static func startsWithUnit(_ line: Prepared) -> Bool {
        guard let first = line.tokens.first else { return false }
        return unitWords.contains(first) || line.tokens.contains("younger") || line.tokens.contains("older")
    }

    // MARK: Neighbours

    /// How far below a label its number may sit, as a fraction of the image
    /// height (a title at the top with a ring under it), and how far above.
    private static let reachBelow = 0.3
    private static let reachAbove = 0.15
    /// Lines looked at below and above a label.
    private static let linesBelow = 3
    private static let linesAbove = 2

    private static func overlapsColumn(_ a: Box, _ b: Box) -> Bool {
        min(a.maxX, b.maxX) - max(a.x, b.x) > 0 || abs(a.midX - b.midX) <= 0.15
    }

    /// Lines after the label in its own column, nearest first.
    private static func below(_ index: Int, in lines: [Prepared]) -> [Int] {
        guard let box = lines[index].box else {
            return Array(lines.indices.dropFirst(index + 1).prefix(linesBelow))
        }
        let near = lines.indices.filter { other in
            guard other != index, let candidate = lines[other].box, !sameRow(box, candidate) else { return false }
            return candidate.midY > box.midY && candidate.y - box.maxY <= reachBelow && overlapsColumn(box, candidate)
        }
        return Array(near.sorted { (lines[$0].box?.midY ?? 0) < (lines[$1].box?.midY ?? 0) }.prefix(linesBelow))
    }

    private static func above(_ index: Int, in lines: [Prepared]) -> [Int] {
        guard let box = lines[index].box else {
            return Array(lines.indices.prefix(index).reversed().prefix(linesAbove))
        }
        let near = lines.indices.filter { other in
            guard other != index, let candidate = lines[other].box, !sameRow(box, candidate) else { return false }
            return candidate.midY < box.midY && box.y - candidate.maxY <= reachAbove && overlapsColumn(box, candidate)
        }
        return Array(near.sorted { (lines[$0].box?.midY ?? 0) > (lines[$1].box?.midY ?? 0) }.prefix(linesAbove))
    }

    /// Other lines on the label's row (a list row: "Readiness" on the left, "7" on the right).
    private static func sameRowLines(_ index: Int, in lines: [Prepared]) -> [Int] {
        guard let box = lines[index].box else { return [] }
        return lines.indices.filter { other in
            guard other != index, let candidate = lines[other].box else { return false }
            return sameRow(box, candidate)
        }
    }

    /// The lines that follow `index` closely enough to be its unit or its
    /// level word: the next one on its row and the one right under it.
    private static func followers(of index: Int, in lines: [Prepared]) -> [Prepared] {
        guard let box = lines[index].box else {
            return index + 1 < lines.count ? [lines[index + 1]] : []
        }
        let right = lines.indices
            .filter { other in
                guard other != index, let candidate = lines[other].box else { return false }
                return sameRow(box, candidate) && candidate.x >= box.midX
            }
            .min { (lines[$0].box?.x ?? 0) < (lines[$1].box?.x ?? 0) }
        let under = lines.indices
            .filter { other in
                guard other != index, let candidate = lines[other].box, !sameRow(box, candidate) else { return false }
                return candidate.midY > box.midY && candidate.y - box.maxY <= box.height && overlapsColumn(box, candidate)
            }
            .min { (lines[$0].box?.y ?? 0) < (lines[$1].box?.y ?? 0) }
        return [right, under].compactMap { found in found.map { lines[$0] } }
    }

    private static func isFollowedByUnit(_ index: Int, in lines: [Prepared]) -> Bool {
        followers(of: index, in: lines).contains(where: startsWithUnit)
    }

    // MARK: Candidates

    struct Hit {
        var index: Int
        var value: Value
        var placement: Placement
        /// Also the number right under another label.
        var isShared = false
    }

    /// What was found around one label, before the screen's layout is known.
    struct Search {
        var kind: AppleScoreKind
        var label: Label
        var index: Int
        /// A number on the label's own line or row: nothing more to decide.
        var settled: Candidate?
        var below: Hit?
        var above: Hit?
    }

    /// Walks `order` (nearest first) for the label's number: skips dates and
    /// level words, stops at another label or any other wording.
    private static func scan(_ order: [Int], kind: AppleScoreKind, placement: Placement, in lines: [Prepared]) -> Hit? {
        var level: String?
        for index in order {
            let line = lines[index]
            if let found = value(kind, tokens: line.tokens) {
                if isFollowedByUnit(index, in: lines) { return nil }
                let after = followers(of: index, in: lines).compactMap { levelOnly(kind, tokens: $0.tokens) }.first
                return Hit(index: index, value: Value(number: found.number, level: found.level ?? level ?? after), placement: placement)
            }
            if let word = levelOnly(kind, tokens: line.tokens) {
                level = word
                continue
            }
            if isAnyLabel(line) || !isNeutral(line) { return nil }
        }
        return nil
    }

    private static func candidate(_ kind: AppleScoreKind, label: Label, value: Value, text: String, placement: Placement,
                                  doubts: [Doubt]) -> Candidate {
        var doubts = doubts
        if label.isWeak { doubts.append(.weakLabel) }
        if let level = value.level, !levelFits(kind, level: level, number: value.number) { doubts.append(.levelMismatch) }
        return Candidate(kind: kind, value: value.number, label: label.text, valueText: text, placement: placement,
                         confidence: doubts.isEmpty ? .high : .low, level: value.level, doubts: doubts)
    }

    private static func lookAround(_ kind: AppleScoreKind, label: Label, at index: Int, in lines: [Prepared]) -> Search {
        var search = Search(kind: kind, label: label, index: index)
        if let inline = label.inline {
            search.settled = candidate(kind, label: label, value: inline, text: lines[index].raw, placement: .sameLine, doubts: [])
            return search
        }
        // A number on the label's row (a bare "Sleep" title also needs a level word).
        for other in sameRowLines(index, in: lines) {
            guard let found = value(kind, tokens: lines[other].tokens), !isFollowedByUnit(other, in: lines) else { continue }
            if label.isWeak, found.level == nil { continue }
            search.settled = candidate(kind, label: label, value: found, text: lines[other].raw, placement: .sameLine, doubts: [])
            return search
        }
        search.below = scan(below(index, in: lines), kind: kind, placement: .below, in: lines)
        search.above = scan(above(index, in: lines), kind: kind, placement: .above, in: lines)
        // A bare "Sleep" title needs a sleep level word beside the number.
        if label.isWeak {
            if search.below?.value.level == nil { search.below = nil }
            if search.above?.value.level == nil { search.above = nil }
        }
        return search
    }

    private static func candidates(from search: Search, in lines: [Prepared]) -> [Candidate] {
        var hits = [search.below, search.above].compactMap { $0 }
        if hits.count == 2 { hits = settle(hits, label: search.index, kind: search.kind, in: lines) }
        let ambiguous = hits.count == 2
        return hits.map { hit in
            var doubts: [Doubt] = ambiguous ? [.twoNumbers] : []
            if hit.isShared { doubts.append(.sharedNumber) }
            if let labelBox = lines[search.index].box, let valueBox = lines[hit.index].box, valueBox.height < labelBox.height * 0.5 {
                doubts.append(.smallPrint)
            }
            return candidate(search.kind, label: search.label, value: hit.value, text: lines[hit.index].raw,
                             placement: hit.placement, doubts: doubts)
        }
    }

    /// A number above and another below the label: keeps one only when there
    /// is a reason. A fitting level word beside just one of them, or one of
    /// them clearly closer on the page; otherwise both stay, as doubts.
    private static func settle(_ hits: [Hit], label: Int, kind: AppleScoreKind, in lines: [Prepared]) -> [Hit] {
        if hits[0].value.number == hits[1].value.number { return [hits[0]] }
        let fitting = hits.filter { hit in
            hit.value.level.map { levelFits(kind, level: $0, number: hit.value.number) } == true
        }
        if fitting.count == 1 { return fitting }
        if let labelBox = lines[label].box {
            let gaps = hits.map { hit -> Double in
                guard let box = lines[hit.index].box else { return 1 }
                return hit.placement == .below ? max(0, box.y - labelBox.maxY) : max(0, labelBox.y - box.maxY)
            }
            if gaps[0] <= gaps[1] * 0.6 { return [hits[0]] }
            if gaps[1] <= gaps[0] * 0.6 { return [hits[1]] }
        }
        return hits
    }

    /// One candidate per kind and value (the surest), surest first within a kind.
    private static func tidy(_ found: [Candidate]) -> [Candidate] {
        var kept: [Candidate] = []
        for confidence in [Confidence.high, .low] {
            for candidate in found where candidate.confidence == confidence {
                if kept.contains(where: { $0.kind == candidate.kind && $0.value == candidate.value }) { continue }
                kept.append(candidate)
            }
        }
        // `kept` is already surest first; group it by kind, keeping that order.
        return AppleScoreKind.allCases.flatMap { kind in kept.filter { $0.kind == kind } }
    }

    private static func dayHint(_ lines: [Prepared]) -> DayHint? {
        let today = lines.contains { $0.tokens.first == "today" }
        let yesterday = lines.contains { $0.tokens.first == "yesterday" }
        if today == yesterday { return nil }
        return today ? .today : .yesterday
    }
}
