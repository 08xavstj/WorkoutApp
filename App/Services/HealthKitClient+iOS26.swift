import Foundation
import HealthKit
import AppCore

/// Reads of the newer HealthKit types from docs/research/competitors.md §1g:
/// time in daylight (iOS 17), sleep-apnoea events (iOS 18) and the iOS 26
/// Medications API (names checked against Apple's reference; see below). The
/// deployment target is iOS 26, so all of them are always present.
nonisolated extension HealthKitClient {
    /// Minutes outdoors in daylight per day (Apple Watch only; Garmin doesn't
    /// write it). Empty without a watch.
    @concurrent
    func timeInDaylight(days: Int) async throws -> [DatedValue] {
        try await dailySeries(.timeInDaylight, unit: .minute(), days: days, cumulative: true)
    }

    /// Nights (dated by the morning) on which the watch flagged possible sleep
    /// apnoea, in the last `days` days. Apple's notification runs on Series
    /// 9+/Ultra 2 and catches about two thirds of cases, so none flagged
    /// doesn't mean none (StopBangView says the same).
    @concurrent
    func sleepApneaNights(days: Int) async throws -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepApneaEvent), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            // An event in the evening belongs to the night ending the next morning (as sleep does).
            let nights = try await descriptor.result(for: store).map { calendar.startOfDay(for: $0.startDate.addingTimeInterval(6 * 3600)) }
            return Array(Set(nights)).sorted()
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    /// Apple Watch's nightly breathing-disturbance score
    /// (`appleSleepingBreathingDisturbances`, iOS 18), one value per night
    /// dated by the morning it ended, oldest first. Read as plain samples, not
    /// a statistics collection: Apple's reference page gives the type no
    /// description, so its unit and aggregation style (cumulative or discrete)
    /// couldn't be confirmed, and a wrong statistics option or unit raises an
    /// Objective-C exception that would take the whole app down. A sample
    /// whose quantity isn't a count is skipped (and logged) instead.
    @concurrent
    func breathingDisturbances(days: Int) async throws -> [DatedValue] {
        guard isAvailable else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let start = calendar.date(byAdding: .day, value: -days, to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.appleSleepingBreathingDisturbances), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let unit = HKUnit.count()
        var sums: [Date: (total: Double, count: Int)] = [:]
        do {
            for sample in try await descriptor.result(for: store) {
                guard sample.quantity.`is`(compatibleWith: unit) else {
                    Self.log.error("Breathing disturbances sample isn't a count; skipped")
                    continue
                }
                let night = calendar.startOfDay(for: sample.endDate)
                let current = sums[night] ?? (total: 0, count: 0)
                sums[night] = (current.total + sample.quantity.doubleValue(for: unit), current.count + 1)
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
        return sums.keys.sorted().map { night in
            let entry = sums[night] ?? (total: 0, count: 1)
            return DatedValue(date: night, value: entry.total / Double(max(1, entry.count)))
        }
    }
}

/// A medication from the Health app's Medications list (iOS 26 Medications API).
nonisolated struct HealthMedication: Sendable, Equatable, Identifiable {
    /// Apple's concept identifier (`HKHealthConceptIdentifier`, as text), used
    /// to avoid importing twice and to join dose events to their medication.
    var id: String
    var name: String
    var nickname: String?
    var isArchived: Bool

    /// What the user calls it: the nickname when set, else Apple's display name.
    var shownName: String {
        let nick = nickname?.trimmingCharacters(in: .whitespaces) ?? ""
        return nick.isEmpty ? name.trimmingCharacters(in: .whitespaces) : nick
    }
}

/// One dose logged in the Health app (iOS 26 Medications API), joined with
/// the medication it belongs to.
nonisolated struct HealthDoseEvent: Sendable, Equatable {
    /// `HealthMedication.id` of the medication.
    var medicationID: String
    /// `HealthMedication.shownName`.
    var name: String
    /// When the dose was logged (the sample's start).
    var loggedAt: Date
    /// The reminder time it answered, if it was a scheduled dose.
    var scheduledDate: Date?
    /// True for a dose logged as taken, false for one logged as skipped.
    var taken: Bool
}

// MARK: - Medications API (iOS 26)
//
// Names checked against Apple's HealthKit reference (HKUserAnnotatedMedication,
// HKMedicationConcept, HKHealthConceptIdentifier, HKMedicationDoseEvent and its
// LogStatus, HKUserAnnotatedMedicationQueryDescriptor, HKObjectType
// .userAnnotatedMedicationType() / .medicationDoseEventType(); all iOS 26.0+).
// `HKHealthConceptIdentifier` has no string property, so its description is
// the app's text id (stable within a run; the name match covers the rest). The medications
// list uses per-object authorization (Health's own medication picker) and
// dose events are readable for the medications picked; requesting either type
// any other way is a runtime exception. Read-only: the app never writes dose events.
nonisolated extension HealthKitClient {
    /// Asks for per-object read access to the Medications list (the API uses
    /// object-level authorization, not the usual type-level sheet).
    @concurrent
    func requestMedicationsAccess() async throws {
        guard isAvailable else { return }
        // Only the medications list takes per-object authorization; asking for the
        // dose-event type raises an Objective-C exception ("Per-Object authorization
        // to read … MedicationDoseEvent is disallowed"), which Swift can't catch and
        // which aborts the app. Dose events come with the medications you pick.
        try await store.requestPerObjectReadAuthorization(for: HKObjectType.userAnnotatedMedicationType(), predicate: nil)
    }

    /// The user's medications from the Health app, read-only.
    @concurrent
    func importedMedications() async throws -> [HealthMedication] {
        guard isAvailable else { return [] }
        return try await annotatedMedications().map(Self.healthMedication)
    }

    /// Doses logged in the Health app in the last `days` days (taken or
    /// skipped; reminders nobody answered are left out), oldest first.
    @concurrent
    func healthDoseEvents(days: Int) async throws -> [HealthDoseEvent] {
        guard isAvailable else { return [] }
        let entries = try await annotatedMedications()
        guard !entries.isEmpty else { return [] }
        let byConcept = Dictionary(entries.map { ($0.medication.identifier, Self.healthMedication($0)) },
                                   uniquingKeysWith: { first, _ in first })
        let start = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .now
        let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.sample(type: HKObjectType.medicationDoseEventType(), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store).compactMap { sample -> HealthDoseEvent? in
                guard let event = sample as? HKMedicationDoseEvent,
                      let medication = byConcept[event.medicationConceptIdentifier] else { return nil }
                let taken: Bool
                switch event.logStatus {
                case .taken: taken = true
                case .skipped: taken = false
                default: return nil
                }
                return HealthDoseEvent(
                    medicationID: medication.id,
                    name: medication.shownName,
                    loggedAt: event.startDate,
                    scheduledDate: event.scheduledDate,
                    taken: taken
                )
            }
        } catch let error as HKError where error.code == .errorNoData {
            return []
        }
    }

    private func annotatedMedications() async throws -> [HKUserAnnotatedMedication] {
        let descriptor = HKUserAnnotatedMedicationQueryDescriptor(predicate: nil, limit: nil)
        return try await descriptor.result(for: store)
    }

    private static func healthMedication(_ entry: HKUserAnnotatedMedication) -> HealthMedication {
        HealthMedication(
            id: String(describing: entry.medication.identifier),
            name: entry.medication.displayText,
            nickname: entry.nickname,
            isArchived: entry.isArchived
        )
    }
}
