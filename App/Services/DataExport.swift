import AppCore
import Foundation
import SwiftData

/// Builds the export files for Settings › Data › Export (spec B5,
/// docs/research/competitor-features-2026-11.md) into a temporary folder,
/// for the share sheet or Files. The formats are in AppCore (`SetsCSV`,
/// `CardioCSV`, `DailyScoresCSV`, `BackupDocument`, `GPXExport`); nothing
/// is uploaded and the folder is emptied before each export.
enum DataExport {
    enum Kind: String, CaseIterable, Identifiable {
        case sets, cardio, scores, backup

        var id: String { rawValue }

        var title: String {
            switch self {
            case .sets: "Lifting sets (CSV)"
            case .cardio: "Cardio workouts (CSV)"
            case .scores: "Daily scores (CSV)"
            case .backup: "Full backup (JSON)"
            }
        }

        var detail: String {
            switch self {
            case .sets: "One row per set: date, exercise, weight in your unit and kg, reps, RPE and reps left"
            case .cardio: "From Apple Health: date, type, time, distance, average and max heart rate"
            case .scores: "Sleep scores for about the last 100 mornings, and strain and recovery for recent days"
            case .backup: "Your gym log, saved workouts, typed-in HRV and the app's settings and logs"
            }
        }

        var systemImage: String {
            switch self {
            case .sets: "dumbbell"
            case .cardio: "figure.run"
            case .scores: "chart.bar"
            case .backup: "externaldrive"
            }
        }
    }

    enum Failure: LocalizedError {
        case nothingToExport, healthUnavailable

        var errorDescription: String? {
            switch self {
            case .nothingToExport: "There's nothing to export yet."
            case .healthUnavailable: "Apple Health can't be read right now."
            }
        }
    }

    /// A clean folder in the temporary directory for this export.
    static func folder() throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes `data` as `name` in a fresh export folder.
    static func write(_ data: Data, name: String) throws -> URL {
        let url = try folder().appending(path: name)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    private static func stamp(_ date: Date = .now) -> String { CSV.day(date) }

    // MARK: Files

    static func setsFile(context: ModelContext, unit: WeightUnit) throws -> URL {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))
        var rows: [SetExportRow] = []
        for session in sessions where !session.isActive {
            for exercise in session.orderedExercises {
                for (number, set) in exercise.orderedSets.enumerated() where set.isCompleted {
                    rows.append(SetExportRow(
                        date: set.completedAt ?? session.startedAt, workout: session.name, exercise: exercise.name,
                        setNumber: number + 1, setType: set.isWarmup ? "warm-up" : set.kind.rawValue,
                        weightKg: set.weightKg, reps: set.reps, rpe: set.rpe
                    ))
                }
            }
        }
        guard !rows.isEmpty else { throw Failure.nothingToExport }
        let text = SetsCSV.document(rows, pounds: unit == .pounds)
        return try write(Data(text.utf8), name: "Tensile-sets-\(stamp()).csv")
    }

    static func cardioFile(health: HealthKitClient?, miles: Bool) async throws -> URL {
        guard let health else { throw Failure.healthUnavailable }
        let rows = try await health.cardioExportRows()
        guard !rows.isEmpty else { throw Failure.nothingToExport }
        return try write(Data(CardioCSV.document(rows, miles: miles).utf8), name: "Tensile-cardio-\(stamp()).csv")
    }

    /// Sleep scores are kept by morning (`SleepScoreLog`); strain and
    /// recovery are worked out from Apple Health each time and not kept, so
    /// only the days the app holds now have them.
    static func scoresFile(metrics: DailyMetricsModel) throws -> URL {
        var rows = SleepScoreLog.allScores().map { DailyScoreRow(date: $0.morning, sleepScore: $0.score) }
        for day in metrics.completedWeekStrain + metrics.weekStrain {
            rows.append(DailyScoreRow(date: day.date, strain: day.strain))
        }
        if let recovery = metrics.recovery, !metrics.recoveryIsFromYesterday {
            rows.append(DailyScoreRow(date: .now, recovery: recovery.score))
        }
        guard !DailyScoresCSV.merge(rows).isEmpty else { throw Failure.nothingToExport }
        return try write(Data(DailyScoresCSV.document(rows).utf8), name: "Tensile-scores-\(stamp()).csv")
    }

    static func backupFile(context: ModelContext) throws -> URL {
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))
        let templates = try context.fetch(FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.createdAt)]))
        let hrv = try context.fetch(FetchDescriptor<HRVReading>(sortBy: [SortDescriptor(\.date)]))
        let document = BackupDocument(
            exportedAt: .now,
            modelSchema: "\(WorkoutSchemaV4.versionIdentifier)",
            sessions: sessions.map(backup),
            templates: templates.map(backup),
            hrvReadings: hrv.map { BackupDocument.HRVReading(date: $0.date, milliseconds: $0.milliseconds, source: $0.source) },
            stores: stores()
        )
        return try write(try document.encoded(), name: "Tensile-backup-\(stamp()).json")
    }

    // MARK: Backup pieces

    private static func backup(_ session: WorkoutSession) -> BackupDocument.Session {
        BackupDocument.Session(
            name: session.name, startedAt: session.startedAt, endedAt: session.endedAt, sessionRPE: session.sessionRPE,
            notes: session.notes, savedToHealth: session.savedToHealth, linkedWorkoutUUID: session.linkedWorkoutUUID,
            linkedWorkoutSource: session.linkedWorkoutSource, watchWorkoutUUID: session.watchWorkoutUUID,
            exercises: session.orderedExercises.map { exercise in
                BackupDocument.Exercise(
                    exerciseID: exercise.exerciseID, name: exercise.name, order: exercise.order,
                    sets: exercise.orderedSets.map { set in
                        BackupDocument.LoggedSet(order: set.order, weightKg: set.weightKg, reps: set.reps, rpe: set.rpe,
                                                 isWarmup: set.isWarmup, completedAt: set.completedAt, kind: set.setKindRaw)
                    }
                )
            }
        )
    }

    private static func backup(_ template: WorkoutTemplate) -> BackupDocument.Template {
        BackupDocument.Template(
            name: template.name, createdAt: template.createdAt, lastUsedAt: template.lastUsedAt,
            exercises: template.orderedExercises.map {
                BackupDocument.TemplateExercise(exerciseID: $0.exerciseID, name: $0.name, order: $0.order, sets: $0.sets,
                                                repsLow: $0.repsLow, repsHigh: $0.repsHigh, targetRPE: $0.targetRPE, weightKg: $0.weightKg)
            }
        )
    }

    /// The app's JSON stores in Application Support, as they are. Progress
    /// photos (encrypted images) and the Oura token (Keychain) are not in it.
    private static func stores() -> [String: JSONValue] {
        let folder = URL.applicationSupportDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        var result: [String: JSONValue] = [:]
        for name in names.sorted() where BackupDocument.isBackedUpStore(name) {
            if let data = try? Data(contentsOf: folder.appending(path: name)), let value = JSONValue.parse(data) {
                result[name] = value
            }
        }
        return result
    }

    // MARK: Routes

    /// A GPX file of one workout's route, trimmed by `privacy` unless it was made untrimmed.
    static func gpxFile(route: CardioRoute, privacy: RoutePrivacy.Result, name: String, type: String?, date: Date) throws -> URL {
        let segments = GPXExport.segments(route: route, privacy: privacy)
        guard segments.contains(where: { !$0.isEmpty }) else { throw Failure.nothingToExport }
        let text = GPXExport.document(name: name, type: type, segments: segments)
        return try write(Data(text.utf8), name: GPXExport.fileName(name, date: date, ext: "gpx"))
    }
}
