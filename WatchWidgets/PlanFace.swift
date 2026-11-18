import Foundation

nonisolated extension WatchFaceData {
    /// What the phone sent, as the plan `PlanGlance` reads (the same rules as
    /// the iPhone's Plan widget: `Packages/AppCore/Sources/AppCore/Glances.swift`,
    /// compiled into this target). Data stored by a build from before the
    /// week fields existed has no week end: it reads as an open-ended plan
    /// with whatever sessions it has, as the complication always did.
    var plan: PlanGlance.Plan {
        PlanGlance.Plan(
            updated: updated,
            hasPlan: hasPlan ?? !slots.isEmpty,
            slots: slots.map { slot in
                PlanGlance.Slot(start: slot.start, title: slot.title, shortTitle: slot.shortTitle,
                                symbol: slot.symbol, minutes: slot.minutes)
            },
            weekEnd: weekEnd ?? .distantFuture,
            nextWeek: nextWeek.flatMap { PlanGlance.NextWeek(rawValue: $0) } ?? .open,
            doneAt: lastWorkoutEnd,
            restToday: restToday ?? false,
            bedByStart: bedByStart,
            bedByEnd: bedByEnd,
            weekDone: weekDone,
            weekPlanned: weekPlanned,
            restUntil: restUntil
        )
    }

    /// This week's hard cardio session as the "Intervals" card reads it
    /// (`IntervalGlance`, in the same Glances.swift); nil when the phone sent none.
    var intervalSession: IntervalGlance.Session? {
        intervals.map { intervals in
            IntervalGlance.Session(updated: updated, title: intervals.title, symbol: intervals.symbol,
                                   minutes: intervals.minutes, day: intervals.day, weekEnd: intervals.weekEnd,
                                   done: intervals.done, waitsOn: intervals.waitsOn)
        }
    }
}
