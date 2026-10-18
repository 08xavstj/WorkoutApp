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

    func isTaken(_ dose: Dose) -> Bool { taken[dose.id] != nil }

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

    /// Protein per kg the app should aim for (1.6 unless a medication raises it).
    var proteinGramsPerKg: Double {
        matches.compactMap(\.drug.proteinGramsPerKg).max() ?? 1.6
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
            if adjustments.contains(.raiseProtein) {
                result.append("\(match.medication.name): protein target raised to 2.0 g/kg to protect muscle.")
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
