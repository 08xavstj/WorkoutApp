import Foundation
import AppCore

/// The user's medications, today's doses and what they mean for training.
/// Stored in the App Group (see `MedicationStore`) so the Live Activity's
/// "Taken" button can update it too.
@Observable
final class MedicationsModel {
    private(set) var medications: [Medication] = MedicationStore.medications()
    private(set) var taken: [String: Date] = MedicationStore.takenLog()

    func reload() {
        medications = MedicationStore.medications()
        taken = MedicationStore.takenLog()
    }

    var todayDoses: [Dose] { MedicationStore.doses(on: .now) }

    /// Taken in this app, or logged as taken in the Health app (`healthTakenAt`).
    func isTaken(_ dose: Dose) -> Bool { taken[dose.id] != nil || healthTakenAt(dose) != nil }

    func save(_ medication: Medication) {
        var all = MedicationStore.medications()
        if let index = all.firstIndex(where: { $0.id == medication.id }) {
            all[index] = medication
        } else {
            all.append(medication)
        }
        MedicationStore.save(all)
        changed()
    }

    func delete(_ medication: Medication) {
        MedicationStore.save(MedicationStore.medications().filter { $0.id != medication.id })
        changed()
    }

    func toggle(_ dose: Dose) {
        if isTaken(dose) {
            MedicationStore.unmark(dose.id)
        } else {
            MedicationStore.markTaken(dose.id)
        }
        changed()
    }

    private func changed() {
        reload()
        Task {
            await Reminders.scheduleDoses()
            await Reminders.startMedsActivityIfNeeded()
        }
    }

    // MARK: Creatine

    /// The creatine entry, if the user takes it.
    var creatine: Medication? {
        medications.first { MedicationKnowledge.match($0.name)?.id == "creatine" }
    }

    var creatineReminderOn: Bool {
        creatine.map { $0.isActive && !$0.times.isEmpty } ?? false
    }

    /// Reminder time in minutes after midnight (default 8:00).
    var creatineMinutes: Int { creatine?.times.first ?? 8 * 60 }

    /// Turns the daily creatine reminder on or off, adding a 5 g creatine entry
    /// the first time. Off only clears the reminder time, so the entry (and what
    /// it means for weight and training) stays.
    func setCreatineReminder(on: Bool, minutes: Int? = nil) {
        guard on || creatine != nil else { return }
        var entry = creatine ?? Medication(name: "Creatine", dose: "5 g")
        if on { entry.isActive = true }
        entry.times = on ? [minutes ?? creatineMinutes] : []
        save(entry)
    }

    // MARK: Apple Health Medications (iOS 26 API; HealthKitClient+iOS26)

    /// Marker kept in `notes` so an imported entry isn't imported twice.
    static let healthImportNote = "From Apple Health"

    /// Adds medications from the Health app's list that aren't here yet
    /// (matched by name, case-insensitive, or by Apple's id in the notes).
    /// Read-only merge: nothing the user typed is changed or removed, and
    /// imported entries carry no reminder times so Apple's reminders aren't
    /// doubled (competitors.md item 7); doses logged in Health still count as
    /// taken here (`healthTakenAt`). Archived ones are skipped. Returns how
    /// many were added.
    @discardableResult
    func merge(healthMedications: [HealthMedication]) -> Int {
        var all = MedicationStore.medications()
        let names = Set(all.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        var added = 0
        for imported in healthMedications where !imported.isArchived {
            let name = imported.shownName
            guard !name.isEmpty else { continue }
            let marker = "\(Self.healthImportNote) (\(imported.id))"
            if names.contains(name.lowercased()) || all.contains(where: { $0.notes.contains(marker) }) { continue }
            all.append(Medication(name: name, notes: marker))
            added += 1
        }
        guard added > 0 else { return 0 }
        MedicationStore.save(all)
        changed()
        return added
    }

    /// Reads the Health app's medications and merges them in, then loads the
    /// doses logged there (`healthDoses`). Asks for the per-object Medications
    /// access once (the list has its own picker, not the usual Health sheet);
    /// `reconnectHealth` asks again.
    func importFromHealth(_ health: HealthKitClient) async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.healthAccessAskedKey) {
            do {
                try await health.requestMedicationsAccess()
                defaults.set(true, forKey: Self.healthAccessAskedKey)
            } catch {
                return
            }
        }
        if let imported = try? await health.importedMedications(), !imported.isEmpty {
            merge(healthMedications: imported)
        }
        healthDoses = (try? await health.healthDoseEvents(days: Self.healthDoseDays)) ?? []
    }

    /// Shows the Medications picker again (e.g. from Settings) and reloads.
    func reconnectHealth(_ health: HealthKitClient) async {
        UserDefaults.standard.set(false, forKey: Self.healthAccessAskedKey)
        await importFromHealth(health)
    }

    // MARK: Adherence from the Health app's log (read-only)

    /// Doses logged in the Health app in the last `healthDoseDays` days, when
    /// the user allowed reading them. The app's own reminders and "Taken"
    /// buttons keep working; a dose logged in Health just counts as taken
    /// here too, so nothing is logged twice.
    private(set) var healthDoses: [HealthDoseEvent] = []
    private static let healthAccessAskedKey = "medsHealthAccessAsked"
    /// Matches `MedicationStore.markTaken`'s 60-day log.
    private static let healthDoseDays = 60
    /// A Health dose answers a scheduled dose when its reminder (or log) time
    /// is within this of the dose's time; app choice, wide enough for a late dose.
    private static let healthMatchWindow: TimeInterval = 4 * 3600

    /// When the Health app logged this dose as taken, if it did: the same
    /// medication on the same day, nearest the dose's time (any time of day
    /// when the medication has a single daily dose).
    func healthTakenAt(_ dose: Dose) -> Date? {
        guard !healthDoses.isEmpty,
              let medication = medications.first(where: { $0.id == dose.medicationID }) else { return nil }
        let calendar = Calendar.current
        let sameDay = healthDoses.filter {
            $0.taken && Self.matches(medication, $0) && calendar.isDate($0.scheduledDate ?? $0.loggedAt, inSameDayAs: dose.day)
        }
        if medication.times.count <= 1 { return sameDay.first?.loggedAt }
        let doseTime = dose.time
        func distance(_ event: HealthDoseEvent) -> TimeInterval {
            abs((event.scheduledDate ?? event.loggedAt).timeIntervalSince(doseTime))
        }
        let nearest = sameDay.filter { distance($0) <= Self.healthMatchWindow }.min { distance($0) < distance($1) }
        return nearest?.loggedAt
    }

    /// Same medication: the Health id kept in the notes marker, or the same name.
    static func matches(_ medication: Medication, _ event: HealthDoseEvent) -> Bool {
        if medication.notes.contains("(\(event.medicationID))") { return true }
        return medication.name.lowercased().trimmingCharacters(in: .whitespaces)
            == event.name.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: What the medications mean

    struct Match: Identifiable {
        var medication: Medication
        var drug: MedicationKnowledge.DrugClass
        var id: UUID { medication.id }
    }

    var matches: [Match] {
        medications.filter(\.isActive).compactMap { med in
            MedicationKnowledge.match(med.name).map { Match(medication: med, drug: $0) }
        }
    }

    func has(_ adjustment: MedicationKnowledge.Adjustment) -> Bool {
        matches.contains { $0.drug.adjustments.contains(adjustment) }
    }

    /// The protein floor (g/kg) a medication sets, if any. The goal sets the
    /// target (GoalPlanner); this only raises it.
    var proteinGramsPerKg: Double? {
        matches.compactMap(\.drug.proteinGramsPerKg).max()
    }

    /// Short notes for Home: what to keep in mind today.
    var notes: [String] {
        var result: [String] = []
        for match in matches {
            let days = Calendar.current.dateComponents([.day], from: match.medication.startDate, to: .now).day ?? 99
            let adjustments = match.drug.adjustments
            if days < 21, !adjustments.isDisjoint(with: [.bluntsHeartRate, .raisesHeartRate]) {
                result.append("Started \(match.medication.name) recently: your heart-rate baseline takes 2-4 weeks to settle, so read recovery loosely.")
            }
            if adjustments.contains(.bluntsHeartRate) {
                result.append("\(match.medication.name) lowers your heart rate: judge cardio by feel (RPE), not zones.")
            }
            if adjustments.contains(.tendonCaution) {
                result.append("\(match.medication.name): avoid jumps, sprints and sudden jumps in load (tendon risk).")
            }
            if match.drug.id == "creatine", days < 28 {
                result.append("Started creatine recently: expect 0.5-2 kg of water weight in the first weeks. It's not fat, so judge progress by your waist and photos for now.")
            }
            if adjustments.contains(.raiseProtein) {
                result.append("\(match.medication.name): protein target at least 2.0 g/kg to protect muscle.")
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    /// One line per medication for the AI coach.
    var coachSummary: [String] {
        medications.filter(\.isActive).map { med in
            var line = med.name + (med.dose.isEmpty ? "" : " \(med.dose)")
            if let drug = MedicationKnowledge.match(med.name) {
                line += " (\(drug.name)): " + drug.effects.map(\.text).joined(separator: " ")
            }
            return line
        }
    }
}

/// Excerpts from the official FDA drug label (openFDA, public and free).
nonisolated struct DrugLabel: Sendable, Equatable {
    var title: String
    var boxedWarning: String?
    var warnings: String?
    var adverseReactions: String?
}

nonisolated enum DrugLabelClient {
    /// Looks the medication up by its first word (generic or brand name).
    @concurrent
    static func fetch(_ name: String) async throws -> DrugLabel? {
        guard let word = name.lowercased().components(separatedBy: CharacterSet.letters.inverted).first(where: { $0.count > 2 }) else { return nil }
        var components = URLComponents(string: "https://api.fda.gov/drug/label.json")
        components?.queryItems = [
            URLQueryItem(name: "search", value: "openfda.generic_name:\"\(word)\" OR openfda.brand_name:\"\(word)\""),
            URLQueryItem(name: "limit", value: "1"),
        ]
        guard let url = components?.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first else { return nil }
        func text(_ keys: String...) -> String? {
            for key in keys {
                if let value = (result[key] as? [String])?.first, !value.isEmpty {
                    return excerpt(value)
                }
            }
            return nil
        }
        let openfda = result["openfda"] as? [String: Any]
        let title = (openfda?["generic_name"] as? [String])?.first?.capitalized ?? name
        return DrugLabel(
            title: title,
            boxedWarning: text("boxed_warning"),
            warnings: text("warnings_and_cautions", "warnings"),
            adverseReactions: text("adverse_reactions")
        )
    }

    /// Label sections are long; keep the first ~600 characters, cut at a sentence.
    static func excerpt(_ value: String) -> String {
        let cleaned = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard cleaned.count > 600 else { return cleaned }
        let prefix = String(cleaned.prefix(600))
        if let end = prefix.range(of: ". ", options: .backwards) {
            return String(prefix[..<end.upperBound]) + "…"
        }
        return prefix + "…"
    }
}
