import Foundation
import HealthKit
import AppCore

/// Long-term baselines for the Biology tab. Loaded when the tab opens.
@Observable
final class BiologyModel {
    struct Marker: Identifiable, Equatable {
        enum Tone: Equatable { case good, neutral, caution }
        var id: String
        var name: String
        var value: String
        var unit: String
        var status: String
        var tone: Tone
        var series: [DatedValue]
    }

    private(set) var hrvSeries: [DatedValue] = []
    private(set) var hrvBaseline: Double?
    private(set) var hrvChangePercent: Double?
    private(set) var markers: [Marker] = []
    private(set) var isLoading = false

    func refresh(health: HealthKitClient, settings: UserSettings, manualHRV: [Date: Double], proteinTarget: Double?) async {
        guard health.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }

        let today = Calendar.current.startOfDay(for: .now)
        let unit = settings.weightUnit
        async let vitalsTask = health.nightlyVitals(days: 90, endingOn: today)
        async let weightTask = health.dailySeries(.bodyMass, unit: .gramUnit(with: .kilo), days: 90, cumulative: false)
        async let fatTask = health.dailySeries(.bodyFatPercentage, unit: .percent(), days: 90, cumulative: false)
        async let vo2Task = health.dailySeries(.vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), days: 180, cumulative: false)
        async let proteinTask = health.dailySeries(.dietaryProtein, unit: .gram(), days: 14, cumulative: true)

        // RMSSD first (typed, camera, Apple Watch beat-to-beat), never mixed with SDNN.
        let nights = (try? await health.sleepHistory(nights: 90)) ?? []
        let rmssd = await health.nightlyRMSSD(nights: nights).merging(manualHRV.filter { $0.value > 0 }) { _, typed in typed }
        let vitals = DailyVitals.merging((try? await vitalsTask) ?? [], manualHRV: rmssd, manualOnlyHRV: true).sorted { $0.date < $1.date }
        hrvSeries = vitals.compactMap { v in v.hrvMilliseconds.map { DatedValue(date: v.date, value: $0) } }
        let rhrSeries = vitals.compactMap { v in v.restingHeartRate.map { DatedValue(date: v.date, value: $0) } }

        if !hrvSeries.isEmpty {
            // Geometric mean (mean of ln HRV), the same baseline Recovery uses;
            // HRV is skewed, so a plain average is pulled up by high nights.
            let logs = hrvSeries.map(\.value).filter { $0 > 0 }.map { log($0) }
            hrvBaseline = logs.isEmpty ? nil : exp(logs.reduce(0, +) / Double(logs.count))
            let recent = hrvSeries.suffix(30).map(\.value)
            let earlier = hrvSeries.dropLast(30).suffix(30).map(\.value)
            if !recent.isEmpty, !earlier.isEmpty {
                let r = recent.reduce(0, +) / Double(recent.count)
                let e = earlier.reduce(0, +) / Double(earlier.count)
                hrvChangePercent = e > 0 ? (r / e - 1) * 100 : nil
            } else {
                hrvChangePercent = nil
            }
        }

        var result: [Marker] = []
        func fmt(_ v: Double, _ digits: Int = 1) -> String { v.formatted(.number.precision(.fractionLength(digits))) }

        let weight = (try? await weightTask) ?? []
        if let last = weight.last {
            let trend = Biomarkers.trend(weight.suffix(30).map(\.value), threshold: 0.005)
            result.append(Marker(
                id: "weight", name: "Weight", value: fmt(unit.display(last.value)), unit: unit.rawValue,
                status: trend.rawValue.capitalized, tone: .neutral,
                series: weight.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
            ))
        }
        if !rhrSeries.isEmpty {
            let recent = rhrSeries.suffix(14).map(\.value)
            let avg = recent.reduce(0, +) / Double(recent.count)
            let label = Biomarkers.restingHeartRateLabel(avg)
            result.append(Marker(
                id: "rhr", name: "RHR baseline", value: fmt(avg, 0), unit: "bpm", status: label,
                tone: label == "Excellent" || label == "Good" ? .good : .caution, series: rhrSeries
            ))
        }
        let fat = (try? await fatTask) ?? []
        if let last = fat.last {
            let percent = last.value * 100
            let label = Biomarkers.bodyFatLabel(percent, sex: settings.sex)
            result.append(Marker(
                id: "fat", name: "Body fat", value: fmt(percent), unit: "%", status: label,
                tone: label == "High" ? .caution : .good,
                series: fat.map { DatedValue(date: $0.date, value: $0.value * 100) }
            ))
        }
        let vo2 = (try? await vo2Task) ?? []
        if let last = vo2.last {
            let label = Biomarkers.vo2MaxLabel(last.value, age: settings.age, sex: settings.sex)
            result.append(Marker(
                id: "vo2", name: "VO₂ max", value: fmt(last.value), unit: "", status: label,
                tone: label == "Poor" ? .caution : .good, series: vo2
            ))
        }
        let protein = ((try? await proteinTask) ?? []).filter { $0.value > 0 }
        if !protein.isEmpty {
            // Full days only: today is still being logged.
            let fullDays = protein.filter { !Calendar.current.isDateInToday($0.date) }
            let week = (fullDays.isEmpty ? protein : fullDays).suffix(7).map(\.value)
            let avg = week.reduce(0, +) / Double(week.count)
            let onTarget = proteinTarget.map { avg >= $0 * 0.9 } ?? true
            result.append(Marker(
                id: "protein", name: "Protein · 7-day avg", value: fmt(avg, 0), unit: "g",
                status: onTarget ? "On target" : "Below target", tone: onTarget ? .good : .caution, series: protein
            ))
        }
        markers = result
    }
}
