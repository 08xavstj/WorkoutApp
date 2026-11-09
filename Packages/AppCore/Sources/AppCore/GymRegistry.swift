import Foundation

// Several gyms (your usual one, a second one, a hotel gym for a trip), each
// with its own equipment and machine settings. The planner only ever sees the
// active gym's `GymProfile`, so every load stays one you can make where you are.
//
// Nothing here is a training threshold: the travel presets describe typical
// equipment (app choice), and the "different gym" note is plain advice, not a
// number from a study.

/// A regular gym stays until you delete it; a temporary (travel) one ends on a date.
public enum GymKind: String, Codable, Sendable, CaseIterable {
    case regular, temporary
}

/// How a machine was set up for you at one gym: seat, pin, handles, pad.
/// Short free text, all optional ("4", "B", "wide", "2nd hole").
public struct MachineNote: Codable, Sendable, Equatable {
    public var seat: String?
    public var pin: String?
    public var handles: String?
    /// Pad or back-rest angle / position.
    public var pad: String?
    public var note: String?

    /// Longest setting kept (app choice: a word or two fits on one line).
    public static let maxSettingLength = 16
    /// Longest free-text note kept (app choice).
    public static let maxNoteLength = 120

    public init(seat: String? = nil, pin: String? = nil, handles: String? = nil, pad: String? = nil, note: String? = nil) {
        self.seat = seat
        self.pin = pin
        self.handles = handles
        self.pad = pad
        self.note = note
    }

    /// Trimmed and shortened, empty fields dropped; nil when nothing is left.
    public func cleaned() -> MachineNote? {
        func clean(_ value: String?, _ limit: Int) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : String(trimmed.prefix(limit))
        }
        let result = MachineNote(
            seat: clean(seat, Self.maxSettingLength),
            pin: clean(pin, Self.maxSettingLength),
            handles: clean(handles, Self.maxSettingLength),
            pad: clean(pad, Self.maxSettingLength),
            note: clean(note, Self.maxNoteLength)
        )
        return result.isEmpty ? nil : result
    }

    public var isEmpty: Bool {
        [seat, pin, handles, pad, note].allSatisfy { ($0 ?? "").isEmpty }
    }

    /// "Seat 4 · Pin 7 · Handles wide · Pad 2" (settings only; nil when none).
    public var settingsLine: String? {
        var parts: [String] = []
        if let seat, !seat.isEmpty { parts.append("Seat \(seat)") }
        if let pin, !pin.isEmpty { parts.append("Pin \(pin)") }
        if let handles, !handles.isEmpty { parts.append("Handles \(handles)") }
        if let pad, !pad.isEmpty { parts.append("Pad \(pad)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The settings, else the note: one short line for the Watch.
    public var shortLine: String? {
        if let settingsLine { return settingsLine }
        if let note, !note.isEmpty { return note }
        return nil
    }
}

/// One gym you train at.
public struct SavedGym: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Equipment, plates, dumbbells and stacks. Its `name` is the gym's name.
    public var profile: GymProfile
    public var kind: GymKind
    /// When a temporary gym ends (the start of the day after its last day).
    public var expiresAt: Date?
    /// Machine settings by exercise ID.
    public var machineNotes: [String: MachineNote]
    public var createdAt: Date

    public var name: String {
        get { profile.name }
        set { profile.name = newValue }
    }

    public var isTemporary: Bool { kind == .temporary }

    public init(id: UUID = UUID(), name: String, profile: GymProfile, kind: GymKind = .regular,
                expiresAt: Date? = nil, machineNotes: [String: MachineNote] = [:], createdAt: Date = .now) {
        self.id = id
        self.profile = profile
        self.kind = kind
        self.expiresAt = kind == .temporary ? expiresAt : nil
        self.machineNotes = machineNotes
        self.createdAt = createdAt
        self.profile.name = name
    }

    /// A temporary gym whose end has passed. Regular gyms never expire.
    public func isExpired(at now: Date) -> Bool {
        guard kind == .temporary, let expiresAt else { return false }
        return expiresAt <= now
    }

    private enum CodingKeys: String, CodingKey {
        case id, profile, kind, expiresAt, machineNotes, createdAt
    }

    // Lenient: fields added later decode with defaults, so an older file still loads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profile = try container.decode(GymProfile.self, forKey: .profile)
        kind = try container.decodeIfPresent(GymKind.self, forKey: .kind) ?? .regular
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        machineNotes = try container.decodeIfPresent([String: MachineNote].self, forKey: .machineNotes) ?? [:]
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
    }
}

/// The gym a workout was done at, kept by session start (no SwiftData field).
public struct SessionGym: Codable, Sendable, Equatable {
    public var gymID: UUID
    public var name: String

    public init(gymID: UUID, name: String) {
        self.gymID = gymID
        self.name = name
    }
}

/// All your gyms, which one is active, and which gym each workout was done at.
public struct GymRegistry: Codable, Sendable, Equatable {
    public private(set) var gyms: [SavedGym]
    public private(set) var activeGymID: UUID
    /// The regular gym to go back to when a travel gym ends.
    public private(set) var returnGymID: UUID?
    /// A travel gym that just ended: the app asks whether to keep it for next time.
    public private(set) var endedTravelGymID: UUID?
    /// False until a gym has been saved once (the default one isn't set up).
    public var isConfigured: Bool
    /// Session start (whole seconds since 1970, as `WatchSession.id`) → gym.
    public private(set) var sessionGyms: [String: SessionGym]

    /// Used when a gym has no name or the default preset's name.
    public static let defaultName = "My gym"

    public init(gyms: [SavedGym], activeGymID: UUID? = nil, isConfigured: Bool = true) {
        // Never empty: there is always one regular gym to fall back to.
        var list = gyms
        if !list.contains(where: { $0.kind == .regular }) {
            list.insert(SavedGym(name: Self.defaultName, profile: .commercialKilograms), at: 0)
        }
        self.gyms = list
        let wanted = activeGymID.flatMap { id in list.first { $0.id == id }?.id }
        self.activeGymID = wanted ?? list.first { $0.kind == .regular }?.id ?? list[0].id
        self.returnGymID = nil
        self.endedTravelGymID = nil
        self.isConfigured = isConfigured
        self.sessionGyms = [:]
    }

    /// First launch with gyms: the one profile saved before (if any) becomes
    /// your regular gym, so nothing is lost.
    public static func migrating(legacy: GymProfile?, fallback: GymProfile, now: Date = .now) -> GymRegistry {
        let profile = legacy ?? fallback
        let gym = SavedGym(name: migratedName(profile.name), profile: profile, kind: .regular, createdAt: now)
        return GymRegistry(gyms: [gym], activeGymID: gym.id, isConfigured: legacy != nil)
    }

    /// A name typed by you is kept; an empty or preset name becomes "My gym".
    static func migratedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let presetNames: Set<String> = [GymProfile.commercialKilograms.name, GymProfile.commercialPounds.name,
                                        GymProfile.homeDumbbells.name]
        return trimmed.isEmpty || presetNames.contains(trimmed) ? defaultName : trimmed
    }

    // MARK: Reading

    public var active: SavedGym {
        gyms.first { $0.id == activeGymID } ?? gyms[0]
    }

    public func gym(id: UUID) -> SavedGym? { gyms.first { $0.id == id } }

    public var regularGyms: [SavedGym] { gyms.filter { $0.kind == .regular } }

    /// Travel gyms that haven't ended.
    public func currentTravelGyms(at now: Date) -> [SavedGym] {
        gyms.filter { $0.isTemporary && !$0.isExpired(at: now) }
    }

    /// Travel gyms that ended, kept for reuse, newest first.
    public func pastTravelGyms(at now: Date) -> [SavedGym] {
        gyms.filter { $0.isTemporary && $0.isExpired(at: now) && $0.id != activeGymID }
            .sorted { ($0.expiresAt ?? .distantPast) > ($1.expiresAt ?? .distantPast) }
    }

    /// The active gym is a travel gym.
    public var isTraveling: Bool { active.isTemporary }

    // MARK: Changing

    /// Makes a gym the active one. A travel gym that has ended needs a new end
    /// date first (`reuseTravelGym`); returns false then, or for an unknown id.
    @discardableResult
    public mutating func activate(_ id: UUID, now: Date = .now) -> Bool {
        guard let target = gym(id: id), !target.isExpired(at: now) else { return false }
        if target.isTemporary {
            // Remember the regular gym to go back to (keep it when hopping between travel gyms).
            if !active.isTemporary { returnGymID = activeGymID }
        } else {
            returnGymID = nil
        }
        activeGymID = id
        return true
    }

    /// Adds a regular gym; it becomes active when `activate` is true.
    @discardableResult
    public mutating func addRegular(name: String, profile: GymProfile, activate: Bool = true, now: Date = .now) -> UUID {
        let gym = SavedGym(name: name, profile: profile, kind: .regular, createdAt: now)
        gyms.append(gym)
        if activate { self.activate(gym.id, now: now) }
        return gym.id
    }

    /// Adds a travel gym that ends at `expiresAt` and switches to it.
    @discardableResult
    public mutating func addTravel(name: String, profile: GymProfile, expiresAt: Date, now: Date = .now) -> UUID {
        let gym = SavedGym(name: name, profile: profile, kind: .temporary,
                           expiresAt: max(expiresAt, now.addingTimeInterval(60)), createdAt: now)
        gyms.append(gym)
        activate(gym.id, now: now)
        return gym.id
    }

    /// Uses a past travel gym again, until a new end date.
    @discardableResult
    public mutating func reuseTravelGym(_ id: UUID, expiresAt: Date, now: Date = .now) -> Bool {
        guard let index = gyms.firstIndex(where: { $0.id == id }), gyms[index].isTemporary, expiresAt > now else { return false }
        gyms[index].expiresAt = expiresAt
        if endedTravelGymID == id { endedTravelGymID = nil }
        return activate(id, now: now)
    }

    /// Moves a travel gym's end date (still in the future).
    public mutating func setEnd(_ expiresAt: Date, for id: UUID, now: Date = .now) {
        guard let index = gyms.firstIndex(where: { $0.id == id }), gyms[index].isTemporary, expiresAt > now else { return }
        gyms[index].expiresAt = expiresAt
    }

    /// Saves a gym's equipment (and name).
    public mutating func updateProfile(_ profile: GymProfile, for id: UUID) {
        guard let index = gyms.firstIndex(where: { $0.id == id }) else { return }
        gyms[index].profile = profile
    }

    public mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = gyms.firstIndex(where: { $0.id == id }) else { return }
        gyms[index].name = trimmed
    }

    /// Whether a gym can be deleted: every gym but the last regular one.
    public func canDelete(_ id: UUID) -> Bool {
        guard let target = gym(id: id) else { return false }
        return target.isTemporary || regularGyms.count > 1
    }

    /// Deletes a gym. Deleting the active one switches to the gym you came
    /// from, else your first regular gym. Workouts keep the gym's name.
    @discardableResult
    public mutating func delete(_ id: UUID) -> Bool {
        guard canDelete(id) else { return false }
        gyms.removeAll { $0.id == id }
        if endedTravelGymID == id { endedTravelGymID = nil }
        if returnGymID == id { returnGymID = nil }
        if activeGymID == id {
            activeGymID = fallbackRegularID
            returnGymID = nil
        }
        return true
    }

    private var fallbackRegularID: UUID {
        if let returnGymID, gym(id: returnGymID)?.kind == .regular { return returnGymID }
        return regularGyms.first?.id ?? gyms[0].id
    }

    /// When the active travel gym has ended: switches back to the regular gym
    /// you came from and returns the ended gym (kept, and flagged so the app
    /// can ask whether to delete it). Nil when nothing changed.
    @discardableResult
    public mutating func expireIfNeeded(now: Date = .now) -> SavedGym? {
        let current = active
        guard current.isExpired(at: now) else { return nil }
        activeGymID = fallbackRegularID
        returnGymID = nil
        endedTravelGymID = current.id
        return current
    }

    /// The ended travel gym to ask about, if any.
    public var endedTravelGym: SavedGym? { endedTravelGymID.flatMap { gym(id: $0) } }

    /// "Keep it": stays under past travel gyms; no more asking.
    public mutating func keepEndedTravelGym() { endedTravelGymID = nil }

    // MARK: Machine settings

    public func machineNote(for exerciseID: String, gymID: UUID? = nil) -> MachineNote? {
        gym(id: gymID ?? activeGymID)?.machineNotes[exerciseID]
    }

    /// Saves (or, when empty, clears) a machine's settings at a gym.
    public mutating func setMachineNote(_ note: MachineNote?, for exerciseID: String, gymID: UUID? = nil) {
        guard let index = gyms.firstIndex(where: { $0.id == (gymID ?? activeGymID) }) else { return }
        gyms[index].machineNotes[exerciseID] = note?.cleaned()
    }

    // MARK: Workouts

    public static func sessionKey(_ start: Date) -> String {
        String(Int(start.timeIntervalSince1970))
    }

    /// Notes the active gym for a workout. The first gym recorded stays, so
    /// switching gyms later doesn't rewrite history. True when it was added.
    @discardableResult
    public mutating func recordSession(startedAt: Date) -> Bool {
        let key = Self.sessionKey(startedAt)
        guard sessionGyms[key] == nil else { return false }
        sessionGyms[key] = SessionGym(gymID: active.id, name: active.name)
        return true
    }

    public func sessionGym(startedAt: Date) -> SessionGym? {
        sessionGyms[Self.sessionKey(startedAt)]
    }

    /// True when the last workout with this exercise was recorded at another
    /// gym than the active one (unknown gyms count as the same).
    public func isDifferentGym(lastSessionStart: Date?) -> Bool {
        guard let lastSessionStart, let last = sessionGym(startedAt: lastSessionStart) else { return false }
        return last.gymID != activeGymID
    }

    /// Plain advice when a machine-like lift was last done at another gym:
    /// machines with the same name can load differently (cams, pulleys,
    /// friction), so the old weight may not match. Advice, not a number from a
    /// study. Free weights weigh the same everywhere: no note.
    public func gymChangeNote(lastSessionStart: Date?, load: EquipmentKind?) -> String? {
        guard let load, Self.machineLike.contains(load), isDifferentGym(lastSessionStart: lastSessionStart) else { return nil }
        return Self.gymChangeText
    }

    public static let gymChangeText = "Different gym from last time: start a little lighter if the machine is new to you."
    static let machineLike: Set<EquipmentKind> = [.machine, .cable, .smithMachine]

    // MARK: Codable (lenient)

    private enum CodingKeys: String, CodingKey {
        case gyms, activeGymID, returnGymID, endedTravelGymID, isConfigured, sessionGyms
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedGyms = try container.decode([SavedGym].self, forKey: .gyms)
        let active = try container.decodeIfPresent(UUID.self, forKey: .activeGymID)
        let configured = try container.decodeIfPresent(Bool.self, forKey: .isConfigured) ?? true
        self.init(gyms: decodedGyms, activeGymID: active, isConfigured: configured)
        returnGymID = try container.decodeIfPresent(UUID.self, forKey: .returnGymID)
        endedTravelGymID = try container.decodeIfPresent(UUID.self, forKey: .endedTravelGymID)
        sessionGyms = try container.decodeIfPresent([String: SessionGym].self, forKey: .sessionGyms) ?? [:]
    }
}

// MARK: - Travel gyms

/// Quick starting points for a gym you'll only use for a while. The
/// equipment is what such places typically have (app choice, not a survey);
/// edit it to match the real room.
public enum TravelGymPreset: String, CaseIterable, Sendable, Identifiable {
    case hotel, hotelMinimal, bodyweight, apartment, garage

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .hotel: "Hotel gym"
        case .hotelMinimal: "Hotel gym (light dumbbells)"
        case .bodyweight: "No equipment"
        case .apartment: "Apartment gym"
        case .garage: "Friend's garage"
        }
    }

    public var detail: String {
        switch self {
        case .hotel: "Dumbbells to 25 kg / 50 lb, a cable, a machine, a bench"
        case .hotelMinimal: "Light dumbbells only"
        case .bodyweight: "Bodyweight: a room or a park"
        case .apartment: "Dumbbells, a bench, a cable, a pull-up bar"
        case .garage: "Barbell, rack, bench and plates"
        }
    }

    public var systemImage: String {
        switch self {
        case .hotel: "building.2"
        case .hotelMinimal: "bed.double"
        case .bodyweight: "figure.core.training"
        case .apartment: "building"
        case .garage: "house"
        }
    }

    /// The equipment, in the unit you lift in.
    public func profile(unit: LoadUnit) -> GymProfile {
        let kg = unit == .kg
        let base: GymProfile = kg ? .commercialKilograms : .commercialPounds
        func rack(through top: Double) -> [Double] {
            let step = kg ? 2.5 : 5
            return stride(from: step, through: top, by: step).map { $0 }
        }
        func make(_ equipment: Set<EquipmentKind>, dumbbells: [Double] = [], plates: [PlateCount] = [],
                     cable: WeightStack? = nil, machine: WeightStack? = nil) -> GymProfile {
            GymProfile(
                name: name, unit: unit, equipment: equipment,
                barbellWeight: base.barbellWeight, ezBarWeight: base.ezBarWeight, smithBarWeight: base.smithBarWeight,
                plates: plates, dumbbells: dumbbells, kettlebells: [],
                cableStack: cable ?? base.cableStack, machineStack: machine ?? base.machineStack
            )
        }
        switch self {
        case .hotel:
            return make([.dumbbell, .cable, .machine, .bench], dumbbells: rack(through: kg ? 25 : 50),
                           cable: kg ? WeightStack(start: 5, step: 5, max: 70) : WeightStack(start: 10, step: 10, max: 150),
                           machine: kg ? WeightStack(start: 5, step: 5, max: 100) : WeightStack(start: 10, step: 10, max: 200))
        case .hotelMinimal:
            return make([.dumbbell], dumbbells: rack(through: kg ? 10 : 25))
        case .bodyweight:
            return make([])
        case .apartment:
            return make([.dumbbell, .bench, .cable, .pullUpBar], dumbbells: rack(through: kg ? 22.5 : 50),
                           cable: kg ? WeightStack(start: 5, step: 5, max: 70) : WeightStack(start: 10, step: 10, max: 150))
        case .garage:
            let plates: [PlateCount] = kg
                ? [PlateCount(weight: 20, pairs: 2), PlateCount(weight: 10, pairs: 2), PlateCount(weight: 5, pairs: 2),
                   PlateCount(weight: 2.5, pairs: 2), PlateCount(weight: 1.25, pairs: 1)]
                : [PlateCount(weight: 45, pairs: 2), PlateCount(weight: 25, pairs: 2), PlateCount(weight: 10, pairs: 2),
                   PlateCount(weight: 5, pairs: 2), PlateCount(weight: 2.5, pairs: 1)]
            return make([.barbell, .squatRack, .bench, .pullUpBar], plates: plates)
        }
    }
}

/// End dates for a travel gym: the end of a day, so "until Sunday" includes Sunday.
public enum TravelGymDates {
    /// The start of the day after `day`.
    public static func endOfDay(_ day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// The end of the coming Sunday (today, if today is Sunday).
    public static func endOfSunday(after now: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now) // 1 = Sunday
        let daysAhead = (8 - weekday) % 7
        let sunday = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
        return endOfDay(sunday, calendar: calendar)
    }

    /// The end of the last of `days` days, today counting as the first.
    public static func end(days: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let last = calendar.date(byAdding: .day, value: max(1, days) - 1, to: now) ?? now
        return endOfDay(last, calendar: calendar)
    }

    /// The last day a gym is used (the day before its end).
    public static func lastDay(expiresAt: Date) -> Date {
        expiresAt.addingTimeInterval(-1)
    }
}
