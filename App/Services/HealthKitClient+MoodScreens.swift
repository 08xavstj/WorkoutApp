import Foundation
import HealthKit
import AppCore

/// PHQ-9 and GAD-7 results to Apple Health's scored assessments
/// (`HKPHQ9Assessment`, `HKGAD7Assessment`, iOS 18; checked in Apple's
/// HealthKit documentation: `init(date:answers:metadata:)`, answers
/// `.notAtAll`, `.severalDays`, `.moreThanHalfTheDays`, `.nearlyEveryDay`,
/// types `HKScoredAssessmentType(.PHQ9)` / `(.GAD7)`). Write access is asked
/// for the first time a result is saved, not in the app's main Health
/// sheet, so nobody who never takes them sees the request.
nonisolated extension HealthKitClient {
    /// Saves one completed questionnaire. Does nothing in demo mode, without
    /// Health, or when the person declines; the app keeps its own copy anyway.
    @concurrent
    func saveMoodScreen(_ result: MoodQuestionnaires.Result) async throws {
        if DemoHealth.active != nil { return }
        guard isAvailable, result.isComplete else { return }
        switch result.kind {
        case .phq9:
            let type = HKScoredAssessmentType(.PHQ9)
            try await store.requestAuthorization(toShare: [type], read: [])
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            let answers: [HKPHQ9Assessment.Answer] = result.answers.map { answer in
                switch answer {
                case 0: .notAtAll
                case 1: .severalDays
                case 2: .moreThanHalfTheDays
                default: .nearlyEveryDay
                }
            }
            try await store.save(HKPHQ9Assessment(date: result.date, answers: answers))
        case .gad7:
            let type = HKScoredAssessmentType(.GAD7)
            try await store.requestAuthorization(toShare: [type], read: [])
            guard store.authorizationStatus(for: type) == .sharingAuthorized else { return }
            let answers: [HKGAD7Assessment.Answer] = result.answers.map { answer in
                switch answer {
                case 0: .notAtAll
                case 1: .severalDays
                case 2: .moreThanHalfTheDays
                default: .nearlyEveryDay
                }
            }
            try await store.save(HKGAD7Assessment(date: result.date, answers: answers))
        }
    }
}
