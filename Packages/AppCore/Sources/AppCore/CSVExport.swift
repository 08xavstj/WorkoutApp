import Foundation

// CSV files for Settings › Data › Export (spec B5 in
// docs/research/competitor-features-2026-11.md): one row per logged set, one
// per cardio workout, one per day of scores. UTF-8, comma-separated, ISO 8601
// dates, decimals with a point whatever the phone's language, weights in
// kilograms with the user's unit alongside (CLAUDE.md: stored in kg).
// Fields are quoted as RFC 4180 says (commas, quotes, line breaks).
// Each file starts with a UTF-8 byte order mark: without it Excel opens a
// CSV in the system's legacy code page and garbles non-ASCII names
// ("Zürich" becomes "ZÃ¼rich"; Microsoft Support, "Opening CSV UTF-8 files
// correctly in Excel"). Numbers, Google Sheets and pandas skip the mark.

public nonisolated enum CSV {
    /// One field: quoted when it holds a comma, quote or line break, with
    /// quotes doubled (RFC 4180 §2.6-2.7). Text that a spreadsheet would run
    /// as a formula (starting with =, +, -, @, tab or return) gets a leading
    /// apostrophe (OWASP, "CSV Injection"). Numbers go through `number`, so
    /// a negative number is never touched.
    public static func field(_ text: String) -> String {
        var value = text
        if let first = value.unicodeScalars.first, ["=", "+", "-", "@", "\t", "\r"].contains(Character(first)) {
            value = "'" + value
        }
        // `isNewline`, not "\n" or "\r": Swift reads "\r\n" as one Character.
        let needsQuotes = value.contains { $0 == "," || $0 == "\"" || $0.isNewline }
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// A number with up to `decimals` places and no trailing zeros, "." as
    /// the separator: "82.5", "100", "-3.25". Empty for nil or not finite.
    public static func number(_ value: Double?, decimals: Int = 2) -> String {
        guard let value, value.isFinite else { return "" }
        let scale = pow(10, Double(max(0, decimals)))
        let rounded = (value * scale).rounded() / scale
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.\(max(0, decimals))f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    public static func number(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    /// "2026-11-18T07:30:00+01:00": date, time and the offset from UTC.
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// "2026-11-18" in `timeZone`.
    public static func day(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// U+FEFF, which UTF-8 writes as EF BB BF (see the note at the top).
    public static let byteOrderMark = "\u{FEFF}"

    /// The byte order mark, then header and rows joined with CRLF
    /// (RFC 4180 §2.1), ending in a line break.
    public static func document(header: [String], rows: [[String]]) -> String {
        byteOrderMark + ([header.map(field)] + rows).map { $0.joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - Logged sets

public nonisolated struct SetExportRow: Sendable, Equatable {
    public var date: Date
    public var workout: String
    public var exercise: String
    /// 1 for the exercise's first set in the session, warm-ups included.
    public var setNumber: Int
    /// "straight", "drop", "warm-up"...
    public var setType: String
    public var weightKg: Double
    public var reps: Int
    public var rpe: Double?

    public init(date: Date, workout: String, exercise: String, setNumber: Int, setType: String,
                weightKg: Double, reps: Int, rpe: Double?) {
        self.date = date
        self.workout = workout
        self.exercise = exercise
        self.setNumber = setNumber
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
    }

    /// Reps in reserve from RPE on the RIR-based scale: RIR = 10 − RPE
    /// (Zourdos et al., J Strength Cond Res 2016; Helms et al., Strength Cond J 2016).
    public var rir: Double? {
        rpe.map { max(0, 10 - $0) }
    }
}

public nonisolated enum SetsCSV {
    public static let poundsPerKilogram = 2.20462

    /// `pounds`: the user's unit is pounds (`WeightUnit`). The kg column is
    /// always there; a pounds column comes before it only for pounds users.
    public static func document(_ rows: [SetExportRow], pounds: Bool, timeZone: TimeZone = .current) -> String {
        let header = ["date", "workout", "exercise", "set", "set_type"] + (pounds ? ["weight_lb"] : [])
            + ["weight_kg", "reps", "rpe", "rir"]
        let lines = rows.map { row -> [String] in
            let shown = pounds ? [CSV.number(row.weightKg * poundsPerKilogram, decimals: 2)] : []
            return [CSV.timestamp(row.date, timeZone: timeZone), CSV.field(row.workout), CSV.field(row.exercise),
                    CSV.number(row.setNumber), CSV.field(row.setType)]
                + shown
                + [CSV.number(row.weightKg, decimals: 3), CSV.number(row.reps),
                   CSV.number(row.rpe, decimals: 1), CSV.number(row.rir, decimals: 1)]
        }
        return CSV.document(header: header, rows: lines)
    }
}

// MARK: - Cardio workouts

public nonisolated struct CardioExportRow: Sendable, Equatable {
    public var start: Date
    public var type: String
    public var source: String?
    public var durationSeconds: TimeInterval
    public var distanceMeters: Double?
    public var averageBpm: Double?
    public var maximumBpm: Double?
    public var elevationGainMeters: Double?

    public init(start: Date, type: String, source: String? = nil, durationSeconds: TimeInterval, distanceMeters: Double? = nil,
                averageBpm: Double? = nil, maximumBpm: Double? = nil, elevationGainMeters: Double? = nil) {
        self.start = start
        self.type = type
        self.source = source
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.averageBpm = averageBpm
        self.maximumBpm = maximumBpm
        self.elevationGainMeters = elevationGainMeters
    }
}

public nonisolated enum CardioCSV {
    /// Exact distances: this file is the user's own record, not a share
    /// card, so nothing is rounded (route privacy rounds shared images).
    public static func document(_ rows: [CardioExportRow], miles: Bool, timeZone: TimeZone = .current) -> String {
        // A miles column before the km one only for miles users.
        let header = ["date", "type", "source", "duration_min"] + (miles ? ["distance_mi"] : [])
            + ["distance_km", "avg_hr_bpm", "max_hr_bpm", "elevation_gain_m"]
        let lines = rows.map { row -> [String] in
            let km = row.distanceMeters.map { $0 / 1000 }
            let shown = miles ? [CSV.number(row.distanceMeters.map { $0 / CardioSummary.metersPerMile }, decimals: 3)] : []
            return [CSV.timestamp(row.start, timeZone: timeZone), CSV.field(row.type), CSV.field(row.source ?? ""),
                    CSV.number(row.durationSeconds / 60, decimals: 1)]
                + shown
                + [CSV.number(km, decimals: 3), CSV.number(row.averageBpm, decimals: 0), CSV.number(row.maximumBpm, decimals: 0),
                   CSV.number(row.elevationGainMeters, decimals: 0)]
        }
        return CSV.document(header: header, rows: lines)
    }
}

// MARK: - Daily scores

public nonisolated struct DailyScoreRow: Sendable, Equatable {
    public var date: Date
    public var sleepScore: Int?
    /// Day strain, 0-100%.
    public var strain: Double?
    public var recovery: Int?

    public init(date: Date, sleepScore: Int? = nil, strain: Double? = nil, recovery: Int? = nil) {
        self.date = date
        self.sleepScore = sleepScore
        self.strain = strain
        self.recovery = recovery
    }
}

public nonisolated enum DailyScoresCSV {
    /// Rows merged by calendar day (later values fill gaps), oldest first;
    /// days with no value are left out.
    public static func merge(_ rows: [DailyScoreRow], calendar: Calendar = .current) -> [DailyScoreRow] {
        var byDay: [Date: DailyScoreRow] = [:]
        for row in rows {
            let day = calendar.startOfDay(for: row.date)
            var merged = byDay[day] ?? DailyScoreRow(date: day)
            merged.sleepScore = row.sleepScore ?? merged.sleepScore
            merged.strain = row.strain ?? merged.strain
            merged.recovery = row.recovery ?? merged.recovery
            byDay[day] = merged
        }
        return byDay.values
            .filter { $0.sleepScore != nil || $0.strain != nil || $0.recovery != nil }
            .sorted { $0.date < $1.date }
    }

    public static func document(_ rows: [DailyScoreRow], calendar: Calendar = .current) -> String {
        let header = ["date", "sleep_score", "recovery", "strain_percent"]
        let lines = merge(rows, calendar: calendar).map { row in
            [CSV.day(row.date, timeZone: calendar.timeZone), CSV.number(row.sleepScore), CSV.number(row.recovery),
             CSV.number(row.strain, decimals: 0)]
        }
        return CSV.document(header: header, rows: lines)
    }
}
