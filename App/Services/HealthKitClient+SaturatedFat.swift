import Foundation
import HealthKit
import AppCore

/// Saturated fat from the food log (Cronometer and other food apps write
/// `dietaryFatSaturated` to Apple Health), as a share of the week's energy
/// (`SaturatedFat`; evidence-audit-2026-11.md, Gaps, item 3).
nonisolated extension HealthKitClient {
    /// The last 7 full days: energy and saturated fat per day. Nil when the
    /// food app sends no saturated fat (never a zero) or too few days are logged.
    @concurrent
    func saturatedFatWeek(days: Int = 7) async throws -> SaturatedFat.Week? {
        let today = Calendar.current.startOfDay(for: .now)
        let energy = try await dailySeries(.dietaryEnergyConsumed, unit: .kilocalorie(), days: days + 1, cumulative: true)
            .filter { $0.date < today }
        guard !energy.isEmpty else { return nil }
        // A day with no saturated-fat samples is absent here, so it reads as "not sent", not 0 g.
        let saturated = (try? await dailySeries(.dietaryFatSaturated, unit: .gram(), days: days + 1, cumulative: true)) ?? []
        let byDay = Dictionary(saturated.map { ($0.date, $0.value) }, uniquingKeysWith: +)
        let week = energy.map { day in
            SaturatedFat.Day(date: day.date, energyKcal: day.value, saturatedGrams: byDay[day.date])
        }
        return SaturatedFat.week(week)
    }
}
