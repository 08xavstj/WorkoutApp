import Foundation
import AppCore

/// Waist, grip strength and STOP-Bang answers, saved as JSON in Application
/// Support (like `CheckInStore`). Waist is stored in centimetres and grip in
/// kilograms; the views convert for display.
@Observable
final class BodyMeasurementsStore {
    nonisolated struct WaistEntry: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        var centimeters: Double
    }

    nonisolated struct GripEntry: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        var kilograms: Double
        var hand: GripStrength.Hand
    }

    nonisolated struct StopBangEntry: Codable, Sendable, Equatable {
        var date: Date
        /// Question id → answer.
        var answers: [String: Bool]
        var score: Int { StopBang.score(answers) }
        var risk: StopBang.Risk { StopBang.risk(score: score) }
    }

    private struct Saved: Codable {
        var waist: [WaistEntry] = []
        var grip: [GripEntry] = []
        var stopBang: StopBangEntry?
    }

    private var saved = Saved()

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "measurements.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(Saved.self, from: data) {
            saved = decoded
        }
    }

    private func write() {
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: fileURL, options: .atomic)
        }
        scheduleReminders()
    }

    // MARK: Waist

    /// Oldest first.
    var waistEntries: [WaistEntry] { saved.waist.sorted { $0.date < $1.date } }
    var latestWaist: WaistEntry? { waistEntries.last }

    func addWaist(centimeters: Double, date: Date = .now) {
        guard centimeters > 20, centimeters < 250 else { return }
        saved.waist.append(WaistEntry(date: date, centimeters: centimeters))
        write()
    }

    func deleteWaist(_ entry: WaistEntry) {
        saved.waist.removeAll { $0.id == entry.id }
        write()
    }

    /// Waist / height from the latest reading, or nil without one or a height.
    func waistToHeightRatio(heightCm: Double?) -> Double? {
        guard let latest = latestWaist, let heightCm else { return nil }
        return WaistToHeightRatio.ratio(waistCm: latest.centimeters, heightCm: heightCm)
    }

    /// The ratio only while the reading is fresh enough for body age (last 90 days).
    func freshWaistToHeightRatio(heightCm: Double?, now: Date = .now) -> Double? {
        guard let latest = latestWaist, WaistToHeightRatio.isFresh(latest.date, now: now) else { return nil }
        return waistToHeightRatio(heightCm: heightCm)
    }

    /// One point per measurement day (the last reading of the day), for the history chart.
    var waistSeries: [DatedValue] {
        var byDay: [Date: Double] = [:]
        for entry in waistEntries {
            byDay[Calendar.current.startOfDay(for: entry.date)] = entry.centimeters
        }
        return byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0] ?? 0) }
    }

    var waistDue: Bool { WaistToHeightRatio.isDue(lastMeasured: latestWaist?.date) }

    // MARK: Grip

    var gripEntries: [GripEntry] { saved.grip.sorted { $0.date < $1.date } }
    var latestGrip: GripEntry? { gripEntries.last }

    func addGrip(kilograms: Double, hand: GripStrength.Hand, date: Date = .now) {
        guard kilograms > 2, kilograms < 150 else { return }
        saved.grip.append(GripEntry(date: date, kilograms: kilograms, hand: hand))
        write()
    }

    func deleteGrip(_ entry: GripEntry) {
        saved.grip.removeAll { $0.id == entry.id }
        write()
    }

    var gripSeries: [DatedValue] {
        var byDay: [Date: Double] = [:]
        for entry in gripEntries {
            byDay[Calendar.current.startOfDay(for: entry.date)] = entry.kilograms
        }
        return byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0] ?? 0) }
    }

    var gripDue: Bool { GripStrength.isDue(lastMeasured: latestGrip?.date) }

    // MARK: STOP-Bang

    var stopBang: StopBangEntry? { saved.stopBang }

    func saveStopBang(answers: [String: Bool], date: Date = .now) {
        saved.stopBang = StopBangEntry(date: date, answers: answers)
        write()
    }

    /// Yearly, or sooner when home blood pressure has turned elevated.
    func stopBangDue(bloodPressureElevated: Bool = false) -> Bool {
        StopBang.isDue(lastAnswered: saved.stopBang?.date, lastAnswers: saved.stopBang?.answers ?? [:],
                       bloodPressureElevated: bloodPressureElevated)
    }

    // MARK: Reminders and the coach

    /// Monthly waist and 6-monthly grip reminders (`Reminders`, "measure|waist", "measure|grip").
    func scheduleReminders() {
        let waistDue = WaistToHeightRatio.nextDue(lastMeasured: latestWaist?.date)
        let gripDue = GripStrength.nextDue(lastMeasured: latestGrip?.date)
        Task { await Reminders.scheduleMeasurementReminders(waistDue: waistDue, gripDue: gripDue) }
    }

    /// One line for the coach, or nil with nothing measured.
    func coachSummary(heightCm: Double?, age: Int, sex: BiologicalSex) -> String? {
        var parts: [String] = []
        if let waist = latestWaist {
            var text = "waist \(Int(waist.centimeters.rounded())) cm"
            if let ratio = waistToHeightRatio(heightCm: heightCm) {
                text += " (waist-to-height \(ratio.formatted(.number.precision(.fractionLength(2)))), \(WaistToHeightRatio.category(ratio).rawValue.lowercased()); target under 0.5)"
            }
            parts.append(text)
        }
        if let grip = latestGrip {
            parts.append("grip \(Int(grip.kilograms.rounded())) kg (\(GripStrength.reading(kg: grip.kilograms, age: age, sex: sex).rawValue.lowercased()))")
        }
        if let screen = saved.stopBang {
            parts.append("STOP-Bang sleep-apnoea screen \(screen.score)/8 (\(screen.risk.rawValue.lowercased()); a screen, not a diagnosis)")
        }
        return parts.isEmpty ? nil : "Body measurements: " + parts.joined(separator: "; ") + "."
    }
}
