import Foundation

/// The full JSON backup (spec B5d, docs/research/competitor-features-2026-11.md):
/// the gym log and saved workouts from SwiftData, plus each JSON store the
/// app keeps in Application Support, with a schema version so a later
/// restore can read it. Weights in kilograms, as stored. Built on the phone
/// and handed to the share sheet or Files; nothing is uploaded.
public nonisolated struct BackupDocument: Codable, Sendable, Equatable {
    /// Bumped when the layout changes.
    public static let currentFormat = 1

    public var format: Int
    public var app: String
    public var exportedAt: Date
    /// The SwiftData schema the sessions came from ("1.3.0").
    public var modelSchema: String
    public var sessions: [Session]
    public var templates: [Template]
    public var hrvReadings: [HRVReading]
    /// File name → its JSON, as stored.
    public var stores: [String: JSONValue]

    public init(exportedAt: Date, modelSchema: String, sessions: [Session], templates: [Template],
                hrvReadings: [HRVReading], stores: [String: JSONValue]) {
        format = Self.currentFormat
        app = "Tensile"
        self.exportedAt = exportedAt
        self.modelSchema = modelSchema
        self.sessions = sessions
        self.templates = templates
        self.hrvReadings = hrvReadings
        self.stores = stores
    }

    public struct Session: Codable, Sendable, Equatable {
        public var name: String
        public var startedAt: Date
        public var endedAt: Date?
        public var sessionRPE: Int?
        public var notes: String
        public var savedToHealth: Bool
        public var linkedWorkoutUUID: UUID?
        public var linkedWorkoutSource: String?
        public var watchWorkoutUUID: UUID?
        public var exercises: [Exercise]

        public init(name: String, startedAt: Date, endedAt: Date?, sessionRPE: Int?, notes: String, savedToHealth: Bool,
                    linkedWorkoutUUID: UUID?, linkedWorkoutSource: String?, watchWorkoutUUID: UUID?, exercises: [Exercise]) {
            self.name = name
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.sessionRPE = sessionRPE
            self.notes = notes
            self.savedToHealth = savedToHealth
            self.linkedWorkoutUUID = linkedWorkoutUUID
            self.linkedWorkoutSource = linkedWorkoutSource
            self.watchWorkoutUUID = watchWorkoutUUID
            self.exercises = exercises
        }
    }

    public struct Exercise: Codable, Sendable, Equatable {
        public var exerciseID: String
        public var name: String
        public var order: Int
        public var sets: [LoggedSet]

        public init(exerciseID: String, name: String, order: Int, sets: [LoggedSet]) {
            self.exerciseID = exerciseID
            self.name = name
            self.order = order
            self.sets = sets
        }
    }

    public struct LoggedSet: Codable, Sendable, Equatable {
        public var order: Int
        public var weightKg: Double
        public var reps: Int
        public var rpe: Double?
        public var isWarmup: Bool
        public var completedAt: Date?
        /// `SetKind` raw value; nil for a straight set.
        public var kind: String?

        public init(order: Int, weightKg: Double, reps: Int, rpe: Double?, isWarmup: Bool, completedAt: Date?, kind: String?) {
            self.order = order
            self.weightKg = weightKg
            self.reps = reps
            self.rpe = rpe
            self.isWarmup = isWarmup
            self.completedAt = completedAt
            self.kind = kind
        }
    }

    public struct Template: Codable, Sendable, Equatable {
        public var name: String
        public var createdAt: Date
        public var lastUsedAt: Date?
        public var exercises: [TemplateExercise]

        public init(name: String, createdAt: Date, lastUsedAt: Date?, exercises: [TemplateExercise]) {
            self.name = name
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
            self.exercises = exercises
        }
    }

    public struct TemplateExercise: Codable, Sendable, Equatable {
        public var exerciseID: String
        public var name: String
        public var order: Int
        public var sets: Int
        public var repsLow: Int
        public var repsHigh: Int
        public var targetRPE: Double?
        public var weightKg: Double?

        public init(exerciseID: String, name: String, order: Int, sets: Int, repsLow: Int, repsHigh: Int,
                    targetRPE: Double?, weightKg: Double?) {
            self.exerciseID = exerciseID
            self.name = name
            self.order = order
            self.sets = sets
            self.repsLow = repsLow
            self.repsHigh = repsHigh
            self.targetRPE = targetRPE
            self.weightKg = weightKg
        }
    }

    public struct HRVReading: Codable, Sendable, Equatable {
        public var date: Date
        public var milliseconds: Double
        public var source: String

        public init(date: Date, milliseconds: Double, source: String) {
            self.date = date
            self.milliseconds = milliseconds
            self.source = source
        }
    }

    /// Pretty-printed, sorted keys, ISO 8601 dates.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> BackupDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupDocument.self, from: data)
    }

    /// Store files worth backing up: the app's own JSON, not the `.bak`
    /// copies or files set aside as corrupt (`SafeJSONFile`).
    public static func isBackedUpStore(_ fileName: String) -> Bool {
        fileName.hasSuffix(".json") && !fileName.hasPrefix(".")
    }
}

/// Any JSON value, so a store file goes into the backup as it is.
public nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    /// The file's JSON, or nil when it doesn't parse.
    public static func parse(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
