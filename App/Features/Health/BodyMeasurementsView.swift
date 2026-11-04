import SwiftUI
import AppCore

/// Waist (and waist-to-height ratio), grip strength and the STOP-Bang sleep
/// apnoea screen: typed in by hand, on their own slow cadences.
///
/// Pushed from Health › Records (`pushed: true`); a root sheet from the Log
/// tab, reminders and workoutapp://measurements. Histories and the STOP-Bang
/// questions open by push, so there's never a sheet on a sheet
/// (ux-audit.md 4.1 rule 5).
struct BodyMeasurementsView: View {
    @Environment(BodyMeasurementsStore.self) private var store
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showingStopBang = false
    @State private var history: VitalsModel.Stat?
    /// True when pushed onto another NavigationStack.
    var pushed = false

    private var heightCm: Double? {
        metrics.heightCm ?? (settings.heightCm > 0 ? settings.heightCm : nil)
    }

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    WaistCard(heightCm: heightCm, goals: metrics.goals) { history = $0 }
                    GripCard(age: settings.age, sex: settings.sex) { history = $0 }
                    StopBangSummaryCard { showingStopBang = true }
                    Text("Measurements you take yourself. They track change; none of them is a diagnosis.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Body measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .navigationDestination(isPresented: $showingStopBang) { StopBangView(pushed: true) }
            .navigationDestination(isPresented: showingHistory) {
                if let stat = history {
                    VitalDetailView(stat: stat, colors: VitalTile.colors(for: stat.category), pushed: true)
                }
            }
        }
    }

    /// `VitalsModel.Stat` isn't Hashable, so the history push is driven by a Bool.
    private var showingHistory: Binding<Bool> {
        Binding(get: { history != nil }, set: { if !$0 { history = nil } })
    }
}

// MARK: - Waist

/// Waist entry in cm or inches, the ratio against height and its band.
struct WaistCard: View {
    @Environment(BodyMeasurementsStore.self) private var store
    let heightCm: Double?
    let goals: Goals?
    let openHistory: (VitalsModel.Stat) -> Void
    @State private var value: Double?
    @State private var unit: LengthUnit = Locale.current.measurementSystem == .metric ? .centimeters : .inches

    private var ratio: Double? { store.waistToHeightRatio(heightCm: heightCm) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Waist", color: Theme.nutrition)
                Spacer()
                if store.waistDue {
                    Chip(text: store.latestWaist == nil ? "Not measured yet" : "Due", color: Theme.recoveryModerate)
                }
            }
            if let latest = store.latestWaist {
                WaistReading(latest: latest, ratio: ratio, heightCm: heightCm, unit: unit, goals: goals)
            }
            entryRow
            if store.waistSeries.count > 1 {
                Button("Waist history") { openHistory(WaistCard.stat(series: store.waistSeries, unit: unit, heightCm: heightCm)) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.nutrition)
            }
            Text("Tape at navel height, standing relaxed, after a normal breath out; same time of day each month. Waist under half your height (ratio under 0.5) is the target: it picks out heart and diabetes risk better than BMI and isn't fooled by muscle (Ashwell et al., Obes Rev 2012).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.nutrition)
    }

    private var entryRow: some View {
        HStack(spacing: 10) {
            TextField(unit == .centimeters ? "84" : "33", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .accessibilityLabel("Waist in \(unit == .centimeters ? "centimetres" : "inches")")
            Picker("Unit", selection: $unit) {
                ForEach(LengthUnit.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 110)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.nutrition)
                .disabled(!isValid)
        }
    }

    private var isValid: Bool {
        guard let value else { return false }
        let cm = unit.toCentimeters(value)
        return cm > 40 && cm < 200
    }

    private func save() {
        guard let value, isValid else { return }
        store.addWaist(centimeters: unit.toCentimeters(value))
        self.value = nil
    }

    /// The history stat for `VitalDetailView`: one point per measurement, in the chosen unit, with the 0.5 line as the goal.
    static func stat(series: [DatedValue], unit: LengthUnit, heightCm: Double?) -> VitalsModel.Stat {
        var stat = VitalsModel.Stat(
            id: "waist", category: .body, title: "Waist", icon: "ruler",
            value: series.last.map { unit.display($0.value).formatted(.number.precision(.fractionLength(0...1))) },
            unit: unit.rawValue, status: nil, tone: .neutral,
            series: series.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        )
        stat.digits = unit == .centimeters ? 0 : 1
        stat.defaultDays = 180
        if let heightCm { stat.goal = unit.display(WaistToHeightRatio.waistAtTarget(heightCm: heightCm)) }
        stat.about = "Your waist each time you measured it. The goal line is half your height (waist-to-height ratio 0.5; Ashwell 2012). Monthly readings are enough: a tape moves a centimetre with the time of day."
        return stat
    }
}

private struct WaistReading: View {
    let latest: BodyMeasurementsStore.WaistEntry
    let ratio: Double?
    let heightCm: Double?
    let unit: LengthUnit
    let goals: Goals?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(unit.format(latest.centimeters))
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let ratio {
                let category = WaistToHeightRatio.category(ratio)
                HStack(spacing: 8) {
                    Text("Waist-to-height \(ratio.formatted(.number.precision(.fractionLength(2))))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Chip(text: category.rawValue, color: WaistReading.color(for: category))
                }
                Text(WaistToHeightRatio.advice(category, goals: goals))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let heightCm {
                    Text("Half your height is \(unit.format(WaistToHeightRatio.waistAtTarget(heightCm: heightCm))).")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("Add your height in Settings (or Apple Health) to see the waist-to-height ratio.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    static func color(for category: WaistToHeightRatio.Category) -> Color {
        switch category {
        case .low: Theme.secondaryText
        case .healthy: Theme.recoveryHigh
        case .raised: Theme.recoveryModerate
        case .high: Theme.recoveryLow
        }
    }
}

// MARK: - Grip

/// Grip strength entry (kg, dominant hand, best of three) with age and sex bands.
struct GripCard: View {
    @Environment(BodyMeasurementsStore.self) private var store
    @Environment(UserSettings.self) private var settings
    let age: Int
    let sex: BiologicalSex
    let openHistory: (VitalsModel.Stat) -> Void
    @State private var value: Double?
    @State private var hand: GripStrength.Hand = .right

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Grip strength", color: Theme.lifting)
                Spacer()
                if store.gripDue {
                    Chip(text: store.latestGrip == nil ? "Not measured yet" : "Due", color: Theme.recoveryModerate)
                }
            }
            if let latest = store.latestGrip {
                GripReading(latest: latest, age: age, sex: sex, unit: settings.weightUnit)
            }
            entryRow
            if store.gripSeries.count > 1 {
                Button("Grip history") { openHistory(GripCard.stat(series: store.gripSeries, unit: settings.weightUnit, age: age, sex: sex)) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.lifting)
            }
            Text("Squeeze a hand dynamometer three times with your dominant hand, arm at your side, and log the best. Twice a year is enough. Grip tracks whole-body strength: in 139,691 adults each 5 kg less went with about 16% more deaths (Leong et al., Lancet 2015).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.lifting)
    }

    private var entryRow: some View {
        HStack(spacing: 10) {
            TextField(settings.weightUnit == .kilograms ? "48" : "106", value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .accessibilityLabel("Grip strength in \(settings.weightUnit == .kilograms ? "kilograms" : "pounds")")
            Text(settings.weightUnit.rawValue)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Picker("Hand", selection: $hand) {
                ForEach(GripStrength.Hand.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            Spacer()
            Button("Save") { save() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.lifting)
                .disabled(!isValid)
        }
    }

    private var isValid: Bool {
        guard let value else { return false }
        let kg = settings.weightUnit.toKilograms(value)
        return kg > 5 && kg < 120
    }

    private func save() {
        guard let value, isValid else { return }
        store.addGrip(kilograms: settings.weightUnit.toKilograms(value), hand: hand)
        self.value = nil
    }

    static func stat(series: [DatedValue], unit: WeightUnit, age: Int, sex: BiologicalSex) -> VitalsModel.Stat {
        let band = GripStrength.band(age: age, sex: sex)
        var stat = VitalsModel.Stat(
            id: "grip", category: .body, title: "Grip strength", icon: "hand.raised.fill",
            value: series.last.map { unit.format($0.value) },
            unit: unit.rawValue, status: nil, tone: .neutral,
            series: series.map { DatedValue(date: $0.date, value: unit.display($0.value)) }
        )
        stat.digits = unit == .kilograms ? 0 : 1
        stat.defaultDays = 180
        stat.normalRange = unit.display(band.low)...unit.display(band.high)
        stat.about = "Best-of-three dominant-hand squeeze each time you measured it. The shaded band is about the typical range for your age and sex (Bohannon et al., Physiotherapy 2006); the European sarcopenia line is \(unit.format(GripStrength.sarcopeniaCutoffKg(sex: sex))) (EWGSOP2, 2019)."
        return stat
    }
}

private struct GripReading: View {
    let latest: BodyMeasurementsStore.GripEntry
    let age: Int
    let sex: BiologicalSex
    let unit: WeightUnit

    var body: some View {
        let reading = GripStrength.reading(kg: latest.kilograms, age: age, sex: sex)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(unit.format(latest.kilograms)) \(unit.rawValue)")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text("\(latest.hand.label.lowercased()) hand · \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Chip(text: reading.rawValue, color: GripReading.color(for: reading))
            Text(GripStrength.advice(reading, age: age, sex: sex))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func color(for reading: GripStrength.Reading) -> Color {
        switch reading {
        case .belowCutoff: Theme.recoveryLow
        case .belowAverage: Theme.recoveryModerate
        case .average: Theme.secondaryText
        case .aboveAverage: Theme.recoveryHigh
        }
    }
}

// MARK: - STOP-Bang summary

/// The last screen's score and when it's next due; opens the questions.
struct StopBangSummaryCard: View {
    @Environment(BodyMeasurementsStore.self) private var store
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardLabel(text: "Sleep apnoea screen (STOP-Bang)", color: Theme.oxygen)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                }
                if let screen = store.stopBang {
                    HStack(spacing: 8) {
                        Text("\(screen.score) of 8")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.primaryText)
                        Chip(text: screen.risk.rawValue, color: StopBangSummaryCard.color(for: screen.risk))
                    }
                    Text("Answered \(screen.date.formatted(date: .abbreviated, time: .omitted)). \(store.stopBangDue() ? "Due again now." : "Asked again in a year, or sooner if your blood pressure climbs.")")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    Text("Eight yes/no questions, once a year. Snoring, daytime tiredness and a big neck are the usual flags for lifters.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.oxygen)
        }
        .buttonStyle(.plain)
    }

    static func color(for risk: StopBang.Risk) -> Color {
        switch risk {
        case .low: Theme.recoveryHigh
        case .intermediate: Theme.recoveryModerate
        case .high: Theme.recoveryLow
        }
    }
}
