import AppIntents
import AppCore
import Foundation

/// "Log Apple scores" in the Shortcuts app: saves Apple's Readiness, Sleep
/// score or Health Age in Tensile, so a shortcut or an automation can pass the
/// numbers in. Every number is optional; the day is today unless one is given.
///
/// Apple offers no action that hands these numbers over (see
/// docs/research/apple-scores-2026-11.md), so a shortcut still has to get them
/// from somewhere: "Ask for Input", or the text of a screenshot. This action is
/// only the way in.
///
/// Main-actor isolated like the app's other intents (`AdjustRestIntent`):
/// `@Parameter` properties can't be `nonisolated`. Runs in the app's process
/// without opening the app.
struct LogAppleScoresIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Apple scores"
    static let description = IntentDescription(
        "Saves Apple's Readiness, Sleep score or Health Age in Tensile, beside Tensile's own scores. Leave out the ones you don't have."
    )

    /// 0–10, as the Readiness app shows it.
    @Parameter(title: "Readiness", description: "Apple's Readiness score, 0 to 10.")
    var readiness: Int?

    /// 0–100.
    @Parameter(title: "Sleep score", description: "Apple's Sleep score, 0 to 100.")
    var sleepScore: Int?

    /// Years, 10–120.
    @Parameter(title: "Health Age", description: "Apple's Health Age in years.")
    var healthAge: Int?

    @Parameter(title: "Day", description: "The day the numbers are for. Today when left empty.")
    var day: Date?

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var values: [AppleScoreKind: Int] = [:]
        if let readiness { values[.readiness] = readiness }
        if let sleepScore { values[.sleepScore] = sleepScore }
        if let healthAge { values[.healthAge] = healthAge }
        guard !values.isEmpty else { throw LogAppleScoresError.nothingGiven }
        for kind in AppleScoreKind.allCases {
            if let value = values[kind], !kind.accepts(value) { throw LogAppleScoresError.outOfRange(kind) }
        }
        let store = AppleScoresStore.shared
        let target = day ?? store.now
        guard target <= store.now.addingTimeInterval(3600) else { throw LogAppleScoresError.dayInTheFuture }
        let saved = store.save(values, on: target, source: .shortcut)
        guard saved.count == values.count else { throw LogAppleScoresError.notSaved }
        let summary = saved.map { kind in "\(kind.title) \(values[kind] ?? 0)" }.joined(separator: ", ")
        return .result(dialog: "Saved \(summary).")
    }
}

/// What the Shortcuts app shows when the action can't save.
nonisolated enum LogAppleScoresError: Error, CustomLocalizedStringResourceConvertible {
    case nothingGiven
    case outOfRange(AppleScoreKind)
    case dayInTheFuture
    case notSaved

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .nothingGiven:
            return "Give at least one number: Readiness, Sleep score or Health Age."
        case .outOfRange(.readiness):
            return "Readiness is a whole number from 0 to 10."
        case .outOfRange(.sleepScore):
            return "The Sleep score is a whole number from 0 to 100."
        case .outOfRange(.healthAge):
            return "Health Age is a whole number of years from 10 to 120."
        case .dayInTheFuture:
            return "The day can't be in the future."
        case .notSaved:
            return "Tensile couldn't save just now. Unlock your iPhone and run the shortcut again."
        }
    }
}
