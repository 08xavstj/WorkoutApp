import Foundation
import Testing
@testable import AppCore

struct GymRegistryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test func migratesTheSavedProfileWithoutLosingIt() {
        var legacy = GymProfile.commercialPounds
        legacy.name = "Riverside"
        legacy.dumbbells = [5, 10, 105]
        let registry = GymRegistry.migrating(legacy: legacy, fallback: .commercialKilograms, now: now)
        #expect(registry.gyms.count == 1)
        #expect(registry.isConfigured)
        #expect(registry.active.profile == legacy)
        #expect(registry.active.name == "Riverside")
        #expect(registry.active.kind == .regular)
    }

    @Test func migrationNamesPresetGymsMyGym() {
        let registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialPounds, now: now)
        #expect(registry.active.name == "My gym")
        #expect(registry.active.profile.unit == .kg)
        let fresh = GymRegistry.migrating(legacy: nil, fallback: .commercialPounds, now: now)
        #expect(!fresh.isConfigured)
        #expect(fresh.active.name == "My gym")
        #expect(fresh.active.profile.unit == .lb)
    }

    @Test func travelGymSwitchesBackWhenItEnds() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let home = registry.activeGymID
        let end = TravelGymDates.end(days: 3, from: now, calendar: calendar)
        let hotel = registry.addTravel(name: "Hotel gym", profile: TravelGymPreset.hotel.profile(unit: .kg),
                                       expiresAt: end, now: now)
        #expect(registry.activeGymID == hotel)
        #expect(registry.isTraveling)
        let early = registry.expireIfNeeded(now: now.addingTimeInterval(3600))
        #expect(early == nil)

        let ended = registry.expireIfNeeded(now: end)
        #expect(ended?.id == hotel)
        #expect(registry.activeGymID == home)
        #expect(registry.endedTravelGym?.id == hotel)
        #expect(registry.pastTravelGyms(at: end).map(\.id) == [hotel])

        registry.keepEndedTravelGym()
        #expect(registry.endedTravelGym == nil)
        #expect(registry.gyms.count == 2)
    }

    @Test func endedTravelGymCanBeReusedWithANewDate() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let hotel = registry.addTravel(name: "Hotel", profile: TravelGymPreset.hotelMinimal.profile(unit: .kg),
                                       expiresAt: now.addingTimeInterval(86_400), now: now)
        let later = now.addingTimeInterval(10 * 86_400)
        registry.expireIfNeeded(now: later)
        let activated = registry.activate(hotel, now: later)
        #expect(!activated)
        let reused = registry.reuseTravelGym(hotel, expiresAt: later.addingTimeInterval(86_400), now: later)
        #expect(reused)
        #expect(registry.activeGymID == hotel)
        #expect(registry.endedTravelGym == nil)
    }

    @Test func hoppingBetweenTravelGymsReturnsToTheRegularOne() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let home = registry.activeGymID
        let work = registry.addRegular(name: "Work gym", profile: .homeDumbbells, now: now)
        #expect(registry.activeGymID == work)
        registry.activate(home, now: now)
        registry.addTravel(name: "A", profile: .homeDumbbells, expiresAt: now.addingTimeInterval(86_400), now: now)
        registry.addTravel(name: "B", profile: .homeDumbbells, expiresAt: now.addingTimeInterval(3600), now: now)
        registry.expireIfNeeded(now: now.addingTimeInterval(7200))
        #expect(registry.activeGymID == home)
    }

    @Test func lastRegularGymCantBeDeleted() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let home = registry.activeGymID
        let deletedHome = registry.delete(home)
        #expect(!deletedHome)
        let hotel = registry.addTravel(name: "Hotel", profile: .homeDumbbells, expiresAt: now.addingTimeInterval(86_400), now: now)
        let deletedHotel = registry.delete(hotel)
        #expect(deletedHotel)
        #expect(registry.activeGymID == home)
        #expect(registry.gyms.count == 1)
    }

    @Test func machineNotesArePerGym() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let home = registry.activeGymID
        registry.setMachineNote(MachineNote(seat: " 4 ", pin: "7", note: ""), for: "Leg_Press")
        #expect(registry.machineNote(for: "Leg_Press")?.settingsLine == "Seat 4 · Pin 7")
        #expect(registry.machineNote(for: "Leg_Press")?.note == nil)
        registry.addTravel(name: "Hotel", profile: .homeDumbbells, expiresAt: now.addingTimeInterval(86_400), now: now)
        #expect(registry.machineNote(for: "Leg_Press") == nil)
        #expect(registry.machineNote(for: "Leg_Press", gymID: home)?.seat == "4")
        // An empty note clears it.
        registry.setMachineNote(MachineNote(seat: "  "), for: "Leg_Press", gymID: home)
        #expect(registry.machineNote(for: "Leg_Press", gymID: home) == nil)
    }

    @Test func machineNoteLines() {
        let note = MachineNote(handles: "wide", pad: "2", note: "Use the left one")
        #expect(note.settingsLine == "Handles wide · Pad 2")
        #expect(MachineNote(note: "Left machine").shortLine == "Left machine")
        #expect(MachineNote(seat: String(repeating: "x", count: 40)).cleaned()?.seat?.count == MachineNote.maxSettingLength)
    }

    @Test func sessionsKeepTheFirstGymAndFlagAChange() {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        let monday = now
        let added = registry.recordSession(startedAt: monday)
        #expect(added)
        registry.addTravel(name: "Hotel gym", profile: TravelGymPreset.hotel.profile(unit: .kg),
                           expiresAt: now.addingTimeInterval(5 * 86_400), now: now)
        // Recording again doesn't rewrite where Monday's workout was.
        let addedAgain = registry.recordSession(startedAt: monday)
        #expect(!addedAgain)
        #expect(registry.sessionGym(startedAt: monday)?.name == "My gym")
        #expect(registry.isDifferentGym(lastSessionStart: monday))
        #expect(registry.gymChangeNote(lastSessionStart: monday, load: .machine) == GymRegistry.gymChangeText)
        #expect(registry.gymChangeNote(lastSessionStart: monday, load: .barbell) == nil)
        // No record (before gyms existed): no note.
        #expect(registry.gymChangeNote(lastSessionStart: now.addingTimeInterval(-86_400), load: .machine) == nil)
    }

    @Test func roundTripsAndDecodesOlderFiles() throws {
        var registry = GymRegistry.migrating(legacy: .commercialKilograms, fallback: .commercialKilograms, now: now)
        registry.setMachineNote(MachineNote(seat: "3"), for: "Leg_Press")
        registry.addTravel(name: "Hotel", profile: .homeDumbbells, expiresAt: now.addingTimeInterval(86_400), now: now)
        registry.recordSession(startedAt: now)
        let data = try JSONEncoder().encode(registry)
        #expect(try JSONDecoder().decode(GymRegistry.self, from: data) == registry)

        // A file with only gyms (no active id, no sessions) still loads.
        let gym = SavedGym(name: "Old", profile: .commercialPounds)
        let minimal = try JSONEncoder().encode(["gyms": [gym]])
        let decoded = try JSONDecoder().decode(GymRegistry.self, from: minimal)
        #expect(decoded.active.name == "Old")
        #expect(decoded.sessionGyms.isEmpty)
    }

    @Test func travelPresetsOnlyHaveTheirEquipment() {
        let hotel = TravelGymPreset.hotel.profile(unit: .kg)
        #expect(hotel.dumbbells.last == 25)
        #expect(!hotel.has(.barbell))
        #expect(TravelGymPreset.hotel.profile(unit: .lb).dumbbells.last == 50)
        #expect(TravelGymPreset.bodyweight.profile(unit: .kg).equipment.isEmpty)
        let garage = TravelGymPreset.garage.profile(unit: .lb)
        #expect(garage.has(.barbell) && garage.has(.squatRack))
        #expect(garage.achievableLoads(for: .barbell).contains(225))
        #expect(TravelGymPreset.hotelMinimal.profile(unit: .kg).equipment == [.dumbbell])
        // The planner plans only what the room has.
        let planner = WorkoutPlanner(gym: TravelGymPreset.bodyweight.profile(unit: .kg))
        #expect(!planner.gymSummary().isEmpty)
    }

    @Test func travelEndDates() {
        // 1_800_000_000 is Friday 15 Jan 2027, 08:00 UTC.
        let sunday = TravelGymDates.endOfSunday(after: now, calendar: calendar)
        #expect(calendar.component(.weekday, from: sunday) == 2) // ends as Monday starts
        #expect(sunday.timeIntervalSince(now) < 3 * 86_400)
        let threeDays = TravelGymDates.end(days: 3, from: now, calendar: calendar)
        #expect(calendar.component(.day, from: TravelGymDates.lastDay(expiresAt: threeDays)) == 17)
    }
}
