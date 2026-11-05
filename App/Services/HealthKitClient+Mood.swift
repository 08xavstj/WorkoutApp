import Foundation
import HealthKit
import AppCore

/// State of Mind reads (iOS 18 type): moods logged in Health, the Mindfulness
/// app, Journal or any other app, as plain `MoodSample`s
/// (docs/research/watch-features.md 4.1). Writes are in `HealthKitClient+Writes`.
nonisolated extension HealthKitClient {
    /// Every State of Mind entry between two dates, oldest first. Entries this
    /// app wrote are flagged `fromThisApp` (they mirror its own check-ins, so
    /// `MoodHistory.merge` drops them in favour of the check-in itself).
    @concurrent
    func stateOfMind(from start: Date, to end: Date) async throws -> [MoodSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.stateOfMind(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let ownBundle = Bundle.main.bundleIdentifier
        let samples: [HKStateOfMind]
        do {
            samples = try await descriptor.result(for: store)
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
        return samples.map { sample in
            MoodSample(
                date: sample.startDate,
                valence: sample.valence,
                kind: sample.kind == .dailyMood ? .daily : .momentary,
                labels: sample.labels.map { Self.name(of: $0) },
                associations: sample.associations.map { Self.name(of: $0) },
                fromThisApp: sample.sourceRevision.source.bundleIdentifier == ownBundle
            )
        }
    }

    // MARK: Names

    /// Apple's `HKStateOfMind.Label` cases by their Swift names, so labels
    /// travel through the app as strings (`MoodFeeling` raw values use the same names).
    static let stateOfMindLabels: [String: HKStateOfMind.Label] = [
        "amazed": .amazed, "amused": .amused, "angry": .angry, "annoyed": .annoyed, "anxious": .anxious,
        "ashamed": .ashamed, "brave": .brave, "calm": .calm, "confident": .confident, "content": .content,
        "disappointed": .disappointed, "discouraged": .discouraged, "disgusted": .disgusted, "drained": .drained,
        "embarrassed": .embarrassed, "excited": .excited, "frustrated": .frustrated, "grateful": .grateful,
        "guilty": .guilty, "happy": .happy, "hopeful": .hopeful, "hopeless": .hopeless, "indifferent": .indifferent,
        "irritated": .irritated, "jealous": .jealous, "joyful": .joyful, "lonely": .lonely, "overwhelmed": .overwhelmed,
        "passionate": .passionate, "peaceful": .peaceful, "proud": .proud, "relieved": .relieved, "sad": .sad,
        "satisfied": .satisfied, "scared": .scared, "stressed": .stressed, "surprised": .surprised, "worried": .worried,
    ]

    /// Apple's `HKStateOfMind.Association` cases by their Swift names
    /// (`MoodAssociation` raw values use the same names).
    static let stateOfMindAssociations: [String: HKStateOfMind.Association] = [
        "community": .community, "currentEvents": .currentEvents, "dating": .dating, "education": .education,
        "family": .family, "fitness": .fitness, "friends": .friends, "health": .health, "hobbies": .hobbies,
        "identity": .identity, "money": .money, "partner": .partner, "selfCare": .selfCare,
        "spirituality": .spirituality, "tasks": .tasks, "travel": .travel, "weather": .weather, "work": .work,
    ]

    static func stateOfMindLabel(named name: String) -> HKStateOfMind.Label? {
        stateOfMindLabels[name]
    }

    static func stateOfMindAssociation(named name: String) -> HKStateOfMind.Association? {
        stateOfMindAssociations[name]
    }

    /// The Swift name of a label; unknown future cases fall back to their number.
    static func name(of label: HKStateOfMind.Label) -> String {
        stateOfMindLabels.first { $0.value == label }?.key ?? "label\(label.rawValue)"
    }

    static func name(of association: HKStateOfMind.Association) -> String {
        stateOfMindAssociations.first { $0.value == association }?.key ?? "association\(association.rawValue)"
    }
}
