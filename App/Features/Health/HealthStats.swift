import SwiftUI
import AppCore

/// The Body-category stats Health builds itself on top of `VitalsModel`:
/// protein from the food log and the hand-typed waist-to-height and grip
/// strength. Shared by Key measures, the All measures counts and the Body
/// page, so all three show the same numbers.
struct HealthExtraStats {
    let biology: BiologyModel
    let metrics: DailyMetricsModel
    let settings: UserSettings
    let measurements: BodyMeasurementsStore

    var heightCm: Double? {
        metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil)
    }

    /// Tiles Health adds after the `VitalsModel` stats of a category (Body only).
    func stats(in category: VitalsModel.Category) -> [VitalsModel.Stat] {
        guard category == .body else { return [] }
        var result: [VitalsModel.Stat] = []
        if let protein = biology.markers.first(where: { $0.id == "protein" }) {
            result.append(proteinStat(protein))
        }
        result.append(waistStat)
        result.append(gripStat)
        return result
    }

    /// Every stat of a category: `VitalsModel`'s, then Health's own.
    func allStats(in category: VitalsModel.Category, vitals: VitalsModel) -> [VitalsModel.Stat] {
        vitals.stats(in: category) + stats(in: category)
    }

    func proteinStat(_ protein: BiologyModel.Marker) -> VitalsModel.Stat {
        var stat = VitalsModel.Stat(
            id: "protein", category: .body, title: "Protein · 7 days", icon: "fork.knife",
            value: protein.value, unit: protein.unit, status: protein.status,
            tone: protein.tone == .caution ? .caution : .good, series: protein.series
        )
        stat.chart = .bars
        stat.goal = metrics.proteinTarget
        stat.about = "Protein logged in your food app each day. Your target comes from your goal and weight: about 1.6 g per kg helps build muscle with lifting, and more while losing weight (Morton et al., Br J Sports Med 2018)."
        return stat
    }

    /// Waist-to-height ratio: under 0.5 is the target (Ashwell 2012); the history chart is the ratio per measurement.
    var waistStat: VitalsModel.Stat {
        let ratio = measurements.waistToHeightRatio(heightCm: heightCm)
        let category = ratio.map(WaistToHeightRatio.category)
        let tone: VitalsModel.Tone = switch category {
        case .healthy: .good
        case .raised, .high: .caution
        case .low, nil: .neutral
        }
        var stat = VitalsModel.Stat(
            id: "whtr", category: .body, title: "Waist-to-height", icon: "ruler",
            value: ratio.map { $0.formatted(.number.precision(.fractionLength(2))) },
            unit: ratio == nil ? "" : "ratio",
            status: category?.rawValue ?? (measurements.latestWaist == nil ? "Add a waist measurement" : "Add your height"),
            tone: tone,
            series: waistRatioSeries
        )
        stat.digits = 2
        stat.defaultDays = 180
        stat.goal = WaistToHeightRatio.target
        stat.normalRange = 0.4...WaistToHeightRatio.target
        stat.about = "Waist divided by height. Keep it under 0.5 (waist less than half your height): across 31 studies it picked out diabetes, high blood pressure and heart-disease risk better than BMI, and it isn't fooled by muscle (Ashwell, Gunn & Gibson, Obes Rev 2012; Browning 2010 for the 0.5 line). 0.5-0.6 is raised, over 0.6 high. Measure monthly in the Log tab under Waist & grip. When a reading is less than 90 days old, body age uses it instead of BMI."
        stat.footnote = measurements.waistDue ? "A waist measurement is due (monthly)." : nil
        return stat
    }

    /// One ratio per measurement day, for the history chart.
    private var waistRatioSeries: [DatedValue] {
        guard let heightCm else { return [] }
        return measurements.waistSeries.compactMap { point in
            WaistToHeightRatio.ratio(waistCm: point.value, heightCm: heightCm).map { DatedValue(date: point.date, value: $0) }
        }
    }

    var gripStat: VitalsModel.Stat {
        var stat = GripCard.stat(series: measurements.gripSeries, unit: settings.weightUnit, age: settings.age, sex: settings.sex)
        if let latest = measurements.latestGrip {
            let reading = GripStrength.reading(kg: latest.kilograms, age: settings.age, sex: settings.sex)
            stat.status = reading.rawValue
            stat.tone = reading == .aboveAverage ? .good : (reading == .average ? .neutral : .caution)
        } else {
            stat.status = "Add a reading twice a year"
        }
        stat.footnote = measurements.gripDue && measurements.latestGrip != nil ? "A grip reading is due (every 6 months)." : nil
        return stat
    }
}

/// How VoiceOver should say a stat's unit ("bpm" → "beats per minute").
enum HealthSpokenUnit {
    static func words(for unit: String) -> String? {
        switch unit {
        case "bpm": "beats per minute"
        case "mmHg": "millimetres of mercury"
        case "ml/kg/min": "millilitres per kilogram per minute"
        case "kg": "kilograms"
        case "lb": "pounds"
        case "%": "percent"
        case "/min": "per minute"
        default: nil
        }
    }
}
