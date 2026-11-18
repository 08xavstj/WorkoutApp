import EventKit
import Foundation
import SwiftData
import SwiftUI
import AppCore

/// Keeps the planned sessions in Apple Calendar (`PlanCalendar` holds the
/// rules; this applies them with EventKit). Off by default; calendar access
/// is asked for only when the switch is turned on (`PlanCalendarSection`).
///
/// Access: full access to events. Write-only access can create events but
/// "doesn't let it read any events or other calendar information, including
/// events your app created" (Apple, "Accessing the event store", read
/// 2026-11-17), so with it a moved, cancelled or finished session could never
/// be updated or removed: the stale events the research file names as the
/// risk. There is no narrower access that can edit the app's own events.
///
/// How the app knows its own events: it keeps them in one calendar it
/// creates, "Tensile", whose identifier is saved in UserDefaults
/// (`calendarIDKey`), and tags each event with a link
/// (`workoutapp://plan?entry=<key>`, `PlanCalendar.url(for:)`). Each sync
/// reads only that calendar, only for this week and next
/// (`PlanCalendar.window`), and matches events by the tag, not by EventKit's
/// event identifiers, which can change when a calendar syncs. It also reads
/// the week before, only to remove its own planned sessions that passed
/// (`PlanCalendar.isPassedSession`). After a reinstall it takes back a
/// "Tensile" calendar it finds instead of making a second. Nothing in any
/// other calendar is read or touched. Turning the switch off removes the
/// Tensile calendar.
@MainActor
final class PlanCalendarSync {
    static let shared = PlanCalendarSync()

    /// The switch (`@AppStorage` in `PlanCalendarSection`).
    static let enabledKey = "planCalendarOn"
    /// The Tensile calendar's identifier.
    static let calendarIDKey = "planCalendarIdentifier"

    /// Made after access is granted: a store made before that sees nothing.
    private var store: EKEventStore?

    private var defaults: UserDefaults { .standard }
    var isOn: Bool { defaults.bool(forKey: Self.enabledKey) }

    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Asks iOS for full access to events (the system prompt shows
    /// `NSCalendarsFullAccessUsageDescription`). True when granted.
    nonisolated static func requestAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        let store = EKEventStore()
        return await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    func accessGranted() {
        store = EKEventStore()
    }

    /// Removes the Tensile calendar and forgets it.
    func turnedOff() {
        defer { defaults.removeObject(forKey: Self.calendarIDKey) }
        guard Self.hasAccess, let id = defaults.string(forKey: Self.calendarIDKey) else { return }
        let store = eventStore()
        if let calendar = store.calendar(withIdentifier: id) {
            try? store.removeCalendar(calendar, commit: true)
        }
    }

    /// Makes the Tensile calendar hold exactly `desired` inside `window`.
    func sync(desired: [PlanCalendar.Entry], window: DateInterval) {
        guard isOn, Self.hasAccess, DemoHealth.active == nil else { return }
        let store = eventStore()
        guard let calendar = ownCalendar(in: store) else { return }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: [calendar])
        let events = store.events(matching: predicate)
        var byID: [String: EKEvent] = [:]
        var existing: [PlanCalendar.Existing] = []
        for event in events {
            guard let id = event.eventIdentifier else { continue }
            byID[id] = event
            existing.append(PlanCalendar.Existing(id: id, key: PlanCalendar.key(from: event.url), title: event.title ?? "",
                                                  start: event.startDate, end: event.endDate, notes: event.notes))
        }
        var changes = PlanCalendar.changes(desired: desired, existing: existing)
        // The week before the window: planned sessions there that passed without one go too
        // (`PlanCalendar.isPassedSession`); finished ones stay.
        let lookback = PlanCalendar.lookback(before: window.start)
        let now = Date.now
        let earlier = store.predicateForEvents(withStart: lookback.start, end: lookback.end, calendars: [calendar])
        for event in store.events(matching: earlier) {
            guard let id = event.eventIdentifier, byID[id] == nil,
                  PlanCalendar.isPassedSession(key: PlanCalendar.key(from: event.url), start: event.startDate, now: now) else { continue }
            byID[id] = event
            changes.remove.append(id)
        }
        guard !changes.isEmpty else { return }
        for id in changes.remove {
            if let event = byID[id] { try? store.remove(event, span: .thisEvent, commit: false) }
        }
        for update in changes.update {
            guard let event = byID[update.id] else { continue }
            fill(event, with: update.entry)
            try? store.save(event, span: .thisEvent, commit: false)
        }
        for entry in changes.create {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            fill(event, with: entry)
            try? store.save(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let made = EKEventStore()
        store = made
        return made
    }

    private func fill(_ event: EKEvent, with entry: PlanCalendar.Entry) {
        event.title = entry.title
        event.startDate = entry.start
        event.endDate = entry.end
        event.notes = entry.notes
        event.url = PlanCalendar.url(for: entry.key)
    }

    /// The Tensile calendar, made on first use in the default calendar's
    /// account (iCloud for most people), else on the device.
    private func ownCalendar(in store: EKEventStore) -> EKCalendar? {
        if let id = defaults.string(forKey: Self.calendarIDKey), let calendar = store.calendar(withIdentifier: id) {
            return calendar
        }
        var sources: [EKSource] = []
        if let source = store.defaultCalendarForNewEvents?.source { sources.append(source) }
        sources += store.sources.filter { $0.sourceType == .calDAV || $0.sourceType == .local }
        // After a reinstall the saved identifier is gone but the calendar isn't (iCloud
        // keeps it): take it back rather than make a second "Tensile".
        let named = store.calendars(for: .event).filter {
            $0.title == PlanCalendar.calendarTitle && $0.allowsContentModifications
        }
        for source in sources {
            if let found = named.first(where: { ($0.source as EKSource?)?.sourceIdentifier == source.sourceIdentifier }) {
                defaults.set(found.calendarIdentifier, forKey: Self.calendarIDKey)
                return found
            }
        }
        for source in sources {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = PlanCalendar.calendarTitle
            calendar.source = source
            do {
                try store.saveCalendar(calendar, commit: true)
                defaults.set(calendar.calendarIdentifier, forKey: Self.calendarIDKey)
                return calendar
            } catch {
                continue
            }
        }
        return nil
    }
}

/// Runs the calendar sync whenever the plan as it stands changes: a saved
/// plan, a session moved by the week's queue, a busy week, rest mode, a
/// finished session, a new day. Draws nothing.
struct PlanCalendarSyncView: View {
    @Environment(WeeklyPlanStore.self) private var plans
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MuscleModel.self) private var muscles
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage(PlanCalendarSync.enabledKey) private var isOn = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .task(id: key) {
                guard isOn, scenePhase == .active else { return }
                sync()
            }
    }

    private var key: String {
        guard isOn else { return "off" }
        let next = Calendar.current.date(byAdding: .day, value: 7, to: WeeklyPlan.weekStart(containing: .now)) ?? .now
        let nextPlan = plans.plan(for: next).map { plan in plan.sortedDays.map { "\($0.weekday)\($0.time)\($0.minutes)" }.joined() } ?? "-"
        let busy = plans.current?.isBusy == true ? "busy" : "normal"
        let times = plans.current?.sortedDays.map { "\($0.time)\($0.minutes)" }.joined() ?? ""
        let rest = settings.isRestMode ? "\(settings.restModeUntil?.timeIntervalSince1970 ?? 0)" : "-"
        let active = scenePhase == .active ? "a" : "b"
        return [plans.adaptiveKey(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns),
                busy, times, nextPlan, rest, active].joined(separator: "|")
    }

    private func sync() {
        let now = Date.now
        let calendar = Calendar.current
        let window = PlanCalendar.window(now: now, calendar: calendar)
        let plan = plans.current
        let week = plan?.isFlexible == false
            ? plans.adaptiveWeek(sessions: sessions, extra: metrics.recentLiftingDays, checkIns: checkIns, muscles: muscles, now: now)
            : nil
        let finished = sessions
            .filter { !$0.isActive && $0.startedAt >= window.start && $0.startedAt < window.end }
            .map { PlanCalendar.Finished(start: $0.startedAt, minutes: Int(($0.duration / 60).rounded()), name: $0.name) }
        let nextStart = calendar.date(byAdding: .day, value: 7, to: window.start) ?? window.end
        let desired = PlanCalendar.entries(plan: plan, week: week, nextPlan: plans.plan(for: nextStart), finished: finished,
                                           restUntil: settings.isRestMode ? settings.restModeUntil : nil, now: now, calendar: calendar)
        PlanCalendarSync.shared.sync(desired: desired, window: window)
    }
}
