import Foundation
import AppCore

/// Waist (and hip), grip strength, DEXA scan numbers and STOP-Bang answers,
/// saved as JSON in Application Support (like `CheckInStore`). Waist and hip
/// are stored in centimetres and grip and lean mass in kilograms; the views
/// convert for display. Waist readings other apps saved to Apple Health are
/// merged in for display (`healthWaist`, never saved here), so there is one
/// waist history (docs/research/next-features-2026-11.md, I10).
@Observable
final class BodyMeasurementsStore {
    nonisolated struct WaistEntry: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        var centimeters: Double
        /// Hip at the widest point, when typed with the waist (for waist-to-hip).
        var hipCentimeters: Double?
        /// True for a reading read from Apple Health (another app's); never saved.
        var fromHealth: Bool?
    }

    /// Numbers typed from a DEXA scan report (`DexaMeasures`; I9). Each optional.
    nonisolated struct DexaEntry: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
        var date: Date
        /// Visceral fat, as the report gives it (mass in g or area in cm²).
        var vat: Double?
        var vatUnit: DexaMeasures.VATUnit?
        /// Arms plus legs lean mass, kg.
        var appendicularLeanKg: Double?
        /// Height used for the ALMI, cm (the profile height at entry).
        var heightCm: Double?

        var almi: Double? {
            guard let appendicularLeanKg, let heightCm else { return nil }
            return DexaMeasures.almi(appendicularLeanKg: appendicularLeanKg, heightCm: heightCm)
        }
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
        /// Optional, so files saved before DEXA fields existed still load.
        var dexa: [DexaEntry]?
    }

    private var saved = Saved()
    /// Waist readings other apps saved to Apple Health (`refreshFromHealth`), in memory only.
    private(set) var healthWaist: [WaistReadings.Reading] = []

    @ObservationIgnored private let file = SafeJSONFile.appSupport("measurements.json")
    /// False while the file exists but couldn't be read (a background launch
    /// while the phone was locked): nothing is saved over it until it loads.
    @ObservationIgnored private var canSave = false

    init() {
        reload()
    }

    /// Reads the file again if the last read failed (call when the phone unlocks).
    func reloadIfUnavailable() {
        if !canSave { reload() }
    }

    private func reload() {
        let loaded = file.loadLogged(Saved.self)
        canSave = loaded.state.canSave
        if canSave { saved = loaded.value ?? Saved() }
    }

    private func write() {
        file.saveLogged(saved, canSave: canSave)
        scheduleReminders()
    }

    // MARK: Waist

    /// Typed readings, oldest first.
    var waistEntries: [WaistEntry] { saved.waist.sorted { $0.date < $1.date } }

    /// Typed readings plus Health's from other apps (same day within 1 cm
    /// counts once, the typed one kept; `WaistReadings.merge`), oldest first.
    var allWaistEntries: [WaistEntry] {
        let typed = waistEntries
        let merged = WaistReadings.merge(
            typed: typed.map { WaistReadings.Reading(date: $0.date, centimeters: $0.centimeters, fromHealth: false) },
            health: healthWaist
        )
        var typedQueue = typed
        return merged.map { reading in
            if !reading.fromHealth, let index = typedQueue.firstIndex(where: { $0.date == reading.date && $0.centimeters == reading.centimeters }) {
                return typedQueue.remove(at: index)
            }
            return WaistEntry(date: reading.date, centimeters: reading.centimeters, fromHealth: true)
        }
    }

    var latestWaist: WaistEntry? { allWaistEntries.last }

    /// The newest typed reading with a hip measurement.
    var latestHip: WaistEntry? { waistEntries.last { $0.hipCentimeters != nil } }

    /// Saves a typed waist (and hip). Returns the entry, or nil for an implausible value.
    @discardableResult
    func addWaist(centimeters: Double, hipCentimeters: Double? = nil, date: Date = .now) -> WaistEntry? {
        reloadIfUnavailable()
        guard centimeters > 20, centimeters < 250 else { return nil }
        let hip = hipCentimeters.flatMap { $0 > 40 && $0 < 250 ? $0 : nil }
        let entry = WaistEntry(date: date, centimeters: centimeters, hipCentimeters: hip)
        saved.waist.append(entry)
        write()
        return entry
    }

    /// Reads the waist readings other apps saved to Apple Health.
    func refreshFromHealth(_ health: HealthKitClient) async {
        healthWaist = (try? await health.healthWaistReadings()) ?? healthWaist
    }

    /// Waist / hip from the newest typed reading that has both.
    var waistToHipRatio: Double? {
        guard let entry = latestHip, let hip = entry.hipCentimeters else { return nil }
        return WaistToHipRatio.ratio(waistCm: entry.centimeters, hipCm: hip)
    }

    func deleteWaist(_ entry: WaistEntry) {
        reloadIfUnavailable()
        saved.waist.removeAll { $0.id == entry.id }
        write()
    }

    /// Waist / height from the latest reading, or nil without one or a height.
    func waistToHeightRatio(heightCm: Double?) -> Double? {
        guard let latest = latestWaist, let heightCm else { return nil }
        return WaistToHeightRatio.ratio(waistCm: latest.centimeters, heightCm: heightCm)
    }

    /// One point per measurement day (the last reading of the day), for the history chart.
    var waistSeries: [DatedValue] {
        var byDay: [Date: Double] = [:]
        for entry in allWaistEntries {
            byDay[Calendar.current.startOfDay(for: entry.date)] = entry.centimeters
        }
        return byDay.keys.sorted().map { DatedValue(date: $0, value: byDay[$0] ?? 0) }
    }

    var waistDue: Bool { WaistToHeightRatio.isDue(lastMeasured: latestWaist?.date) }

    // MARK: Grip

    var gripEntries: [GripEntry] { saved.grip.sorted { $0.date < $1.date } }
    /// The best hand on the latest test day (grip norms use the stronger,
    /// usually dominant, hand: Dodds et al., PLoS One 2014).
    var latestGrip: GripEntry? {
        guard let last = gripEntries.last else { return nil }
        let day = Calendar.current.startOfDay(for: last.date)
        return gripEntries.filter { Calendar.current.startOfDay(for: $0.date) == day }.max { $0.kilograms < $1.kilograms }
    }

    func addGrip(kilograms: Double, hand: GripStrength.Hand, date: Date = .now) {
        reloadIfUnavailable()
        guard kilograms > 2, kilograms < 150 else { return }
        saved.grip.append(GripEntry(date: date, kilograms: kilograms, hand: hand))
        write()
    }

    func deleteGrip(_ entry: GripEntry) {
        reloadIfUnavailable()
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

    // MARK: DEXA

    /// Oldest first.
    var dexaEntries: [DexaEntry] { (saved.dexa ?? []).sorted { $0.date < $1.date } }
    var latestDexa: DexaEntry? { dexaEntries.last }

    /// The VAT before the latest scan's, in the same unit (for "since your last scan").
    var previousVAT: Double? {
        guard let latest = latestDexa, latest.vat != nil else { return nil }
        return dexaEntries.dropLast().last { $0.vat != nil && $0.vatUnit == latest.vatUnit }?.vat
    }

    func addDexa(vat: Double?, vatUnit: DexaMeasures.VATUnit, appendicularLeanKg: Double?, heightCm: Double?, date: Date = .now) {
        reloadIfUnavailable()
        let vatValue = vat.flatMap { $0 > 0 && $0 < 10_000 ? $0 : nil }
        let lean = appendicularLeanKg.flatMap { $0 > 5 && $0 < 80 ? $0 : nil }
        guard vatValue != nil || lean != nil else { return }
        var list = saved.dexa ?? []
        list.append(DexaEntry(date: date, vat: vatValue, vatUnit: vatValue == nil ? nil : vatUnit, appendicularLeanKg: lean, heightCm: heightCm))
        saved.dexa = list
        write()
    }

    func deleteDexa(_ entry: DexaEntry) {
        reloadIfUnavailable()
        saved.dexa?.removeAll { $0.id == entry.id }
        write()
    }

    // MARK: STOP-Bang

    var stopBang: StopBangEntry? { saved.stopBang }

    func saveStopBang(answers: [String: Bool], date: Date = .now) {
        reloadIfUnavailable()
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
        // Unread file (locked phone): no measurements known yet, so nothing is "due".
        guard canSave else { return }
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
        if let ratio = waistToHipRatio {
            parts.append("waist-to-hip \(ratio.formatted(.number.precision(.fractionLength(2))))")
        }
        if let scan = latestDexa {
            var text = "DEXA \(scan.date.formatted(date: .abbreviated, time: .omitted)):"
            if let vat = scan.vat, let unit = scan.vatUnit { text += " visceral fat \(Int(vat.rounded())) \(unit.rawValue) (ungraded)" }
            if let almi = scan.almi {
                text += " ALMI \(almi.formatted(.number.precision(.fractionLength(1)))) kg/m² (\(DexaMeasures.reading(almi: almi, sex: sex).rawValue.lowercased()))"
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
