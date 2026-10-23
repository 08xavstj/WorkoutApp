import SwiftUI
import os
import SwiftData
import AppCore

enum CheckInKind: String, Identifiable {
    case morning, evening
    var id: String { rawValue }
}

/// The morning or evening check-in form. Every question is optional.
struct CheckInView: View {
    let kind: CheckInKind

    @Environment(CheckInStore.self) private var store
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(MedicationsModel.self) private var meds
    @Environment(\.healthClient) private var health
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var morning = MorningCheckIn(day: Calendar.current.startOfDay(for: .now))
    @State private var evening = EveningCheckIn(day: Calendar.current.startOfDay(for: .now))
    @State private var hrv: Double?
    @State private var hrvSource = "Garmin"
    @State private var showingCameraHRV = false
    /// Opens progress photos once this sheet has fully closed.
    @State private var openPhotosAfter = false

    var body: some View {
        NavigationStack {
            Form {
                if kind == .morning { morningQuestions } else { eveningQuestions }
            }
            .scrollContentBackground(.hidden)
            .background(alignment: .top) {
                TopGlow(colors: kind == .morning
                        ? [Theme.Wash.butter, Theme.Wash.peach, Theme.Wash.sky]
                        : [Theme.Wash.lavender, Theme.Wash.sky, Theme.Wash.rose], height: 300)
            }
            .background(Theme.background)
            .navigationTitle(kind == .morning ? "Morning check-in" : "Evening check-in")
            .sheet(isPresented: $showingCameraHRV) {
                CameraHRVView { rmssd in
                    hrv = rmssd
                    hrvSource = "Camera"
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                Logger.diagnostics.notice("check-in screen appeared: \(kind.rawValue, privacy: .public)")
                load()
            }
            .onDisappear {
                if openPhotosAfter { router.showProgressPhotos = true }
            }
        }
    }

    /// True when last night's HRV already came from Apple Health, so there's no need to ask.
    private var hrvFromHealth: Bool {
        metrics.hrv != nil && !metrics.hrvIsManual
    }

    // MARK: Morning

    @ViewBuilder
    private var morningQuestions: some View {
        if !hrvFromHealth {
            Section {
                TextField("e.g. 52", value: $hrv, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .font(.title3.weight(.semibold))
                Button {
                    showingCameraHRV = true
                } label: {
                    Label(hrvSource == "Camera" ? "Measured with camera · measure again" : "Measure with camera (1 minute)", systemImage: "camera.fill")
                }
            } header: {
                Text("Last night's HRV (ms)")
            } footer: {
                Text("Optional, from your watch's app (on Garmin: Garmin Connect → HRV Status). It makes recovery more accurate.")
            }
        }
        Section("How rested do you feel?") {
            ScalePicker(value: $morning.rested, labels: ["Exhausted", "Tired", "OK", "Good", "Great"], color: Theme.sleep)
        }
        Section {
            ScalePicker(value: $morning.soreness, range: 0...10, color: Theme.lifting, endLabels: ("None", "Very sore"))
            if (morning.soreness ?? 0) > 0 {
                ChipFlow(options: MorningCheckIn.BodyArea.allCases, selection: $morning.soreAreas, label: \.rawValue, color: Theme.lifting)
            }
        } header: {
            Text("How sore are you? Where?")
        } footer: {
            Text("The trainer works around sore muscles.")
        }
        Section("Mood") {
            ScalePicker(value: $morning.mood, labels: ["Low", "Meh", "OK", "Good", "Great"], color: Theme.recoveryHigh)
        }
        Section {
            ChipFlow(options: MorningCheckIn.Symptom.allCases, selection: $morning.symptoms, label: \.rawValue, color: Theme.recoveryLow)
        } header: {
            Text("Feeling sick?")
        } footer: {
            Text("Leave empty if you feel fine.")
        }
        Section("Woke up during the night?") {
            Picker("Wakings", selection: $morning.nightWakings) {
                Text("–").tag(Int?.none)
                Text("No").tag(Int?.some(0))
                Text("Once").tag(Int?.some(1))
                Text("2+").tag(Int?.some(2))
            }
            .pickerStyle(.segmented)
        }
        if settings.sex == .female {
            Section {
                Picker("Cycle", selection: $morning.cycle) {
                    Text("–").tag(MorningCheckIn.Cycle?.none)
                    ForEach(MorningCheckIn.Cycle.allCases, id: \.self) { Text($0.rawValue).tag(MorningCheckIn.Cycle?.some($0)) }
                }
            } header: {
                Text("Menstrual cycle")
            } footer: {
                Text("Resting heart rate rises and HRV dips before a period; this stops it reading as poor recovery.")
            }
        }
        Section {
            Button {
                openPhotosAfter = true
                save()
            } label: {
                Label("Save and take progress photos", systemImage: "camera.fill")
            }
        } footer: {
            Text("Saves your answers, then opens the camera for your front and side photos.")
        }
    }

    // MARK: Evening

    @ViewBuilder
    private var eveningQuestions: some View {
        Section {
            Stepper("\(Int(evening.caffeineMg ?? 0)) mg", value: Binding(get: { evening.caffeineMg ?? 0 }, set: { evening.caffeineMg = $0 }), in: 0...1500, step: 10)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(EveningCheckIn.caffeinePresets, id: \.name) { preset in
                        Button("+ \(preset.name)") { evening.caffeineMg = (evening.caffeineMg ?? 0) + preset.mg }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(Theme.strain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            if (evening.caffeineMg ?? 0) > 0 {
                optionalTime("Last caffeine", \.lastCaffeineMinutes, default: 13 * 60)
                if let minutes = evening.lastCaffeineMinutes,
                   CaffeineTiming.isTooLate(minutes: minutes, mg: evening.caffeineMg ?? 0, bedtimeMinutes: usualBedtime) {
                    Label("Later than your cut-off for a \(CaffeineTiming.clockText(usualBedtime)) bedtime; it may cost sleep tonight.", systemImage: "moon.zzz.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.recoveryModerateText)
                }
            }
        } header: {
            Text("Caffeine today")
        } footer: {
            Text("For your usual \(CaffeineTiming.clockText(usualBedtime)) bedtime: last coffee by \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: usualBedtime, mg: 100))), pre-workout by \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: usualBedtime, mg: 200))). In a review of 24 studies, caffeine closer to bed than that cut sleep by about 45 minutes.")
        }
        Section("Alcohol") {
            Stepper("\(evening.drinks ?? 0) drinks", value: Binding(get: { evening.drinks ?? 0 }, set: { evening.drinks = $0 }), in: 0...20)
            if (evening.drinks ?? 0) > 0 {
                optionalTime("Last drink", \.lastDrinkMinutes, default: 21 * 60)
            }
        }
        Section("Stress today") {
            ScalePicker(value: $evening.stress, labels: ["Calm", "Low", "Some", "High", "Very high"], color: Theme.recoveryModerate)
        }
        Section("Food") {
            optionalTime("Last meal", \.lastMealMinutes, default: 19 * 60)
        }
        Section("Anything else today?") {
            Toggle("Nicotine or vaping", isOn: boolBinding(\.nicotine))
            Toggle("Sauna", isOn: boolBinding(\.sauna))
            Toggle("Cold plunge", isOn: boolBinding(\.coldPlunge))
        }
        let untaken = meds.todayDoses.filter { !meds.isTaken($0) }
        if !untaken.isEmpty {
            Section("Medications not ticked off yet") {
                TodayDosesList()
            }
        }
    }

    // MARK: Bindings and saving

    private func minutesBinding(_ keyPath: WritableKeyPath<EveningCheckIn, Int?>, default value: Int) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval((evening[keyPath: keyPath] ?? value) * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                evening[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    /// When you usually fall asleep (minutes after midnight), for the caffeine cut-off.
    private var usualBedtime: Int { CaffeineTiming.usualBedtimeMinutes(metrics.recentBedtimes) }

    /// A time that's only saved once you add it, so the form never shows a
    /// time you didn't enter.
    @ViewBuilder
    private func optionalTime(_ title: String, _ keyPath: WritableKeyPath<EveningCheckIn, Int?>, default value: Int) -> some View {
        if evening[keyPath: keyPath] == nil {
            Button("Add \(title.lowercased()) time") { evening[keyPath: keyPath] = value }
        } else {
            HStack {
                DatePicker(title, selection: minutesBinding(keyPath, default: value), displayedComponents: .hourAndMinute)
                Button {
                    evening[keyPath: keyPath] = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(title.lowercased()) time")
            }
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<EveningCheckIn, Bool?>) -> Binding<Bool> {
        Binding(get: { evening[keyPath: keyPath] ?? false }, set: { evening[keyPath: keyPath] = $0 })
    }

    private var todayHRV: HRVReading? {
        hrvReadings.first { Calendar.current.isDateInToday($0.date) }
    }

    private func load() {
        if let saved = store.morning() { morning = saved }
        if let saved = store.evening() { evening = saved }
        hrv = todayHRV?.milliseconds
        hrvSource = todayHRV?.source ?? "Garmin"
    }

    private func save() {
        switch kind {
        case .morning:
            if let hrv, hrv > 0 {
                if let existing = todayHRV {
                    existing.milliseconds = hrv
                    existing.source = hrvSource
                } else {
                    modelContext.insert(HRVReading(date: .now, milliseconds: hrv, source: hrvSource))
                }
                try? modelContext.save()
            }
            store.save(morning)
            // Late hard workout last night is filled in from your data, not asked.
            let yesterday = Calendar.current.date(byAdding: .day, value: -2, to: .now) ?? .now
            let recent = sessions.filter { !$0.isActive && $0.startedAt >= yesterday }.map(\.strainSummary)
            let sleep = metrics.sleep
            let profile = metrics.heartRateProfile
            let checkIn = morning
            if let health {
                Task {
                    var updated = checkIn
                    updated.lateHardWorkout = await store.detectLateWorkout(health: health, sleep: sleep, sessions: recent, profile: profile)
                    store.save(updated)
                }
            }
        case .evening:
            store.save(evening)
        }
        dismiss()
    }
}

/// A row of numbered buttons (1-5 or 0-10), tap again to clear.
struct ScalePicker: View {
    @Binding var value: Int?
    var range: ClosedRange<Int> = 1...5
    var labels: [String] = []
    let color: Color
    /// Words for the two ends of a numeric scale, e.g. ("None", "Very sore").
    var endLabels: (String, String)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(Array(range), id: \.self) { number in
                    let selected = value == number
                    Button {
                        value = selected ? nil : number
                    } label: {
                        Text("\(number)")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? .white : Theme.primaryText)
                            .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(Theme.cardRaised), in: .rect(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(labels.count == range.count ? "\(number), \(labels[number - range.lowerBound])" : "\(number)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let endLabels {
                HStack {
                    Text(endLabels.0)
                    Spacer()
                    Text(endLabels.1)
                }
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
            }
            if let value, labels.count == range.count, range.contains(value) {
                Text(labels[value - range.lowerBound])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textColor(for: color))
            }
        }
    }
}

/// Wrapping multi-select chips.
struct ChipFlow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: [Option]
    let label: (Option) -> String
    let color: Color

    init(options: [Option], selection: Binding<[Option]>, label: KeyPath<Option, String>, color: Color) {
        self.options = options
        self._selection = selection
        self.label = { $0[keyPath: label] }
        self.color = color
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                let selected = selection.contains(option)
                Button {
                    if selected { selection.removeAll { $0 == option } } else { selection.append(option) }
                } label: {
                    Text(label(option))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .foregroundStyle(selected ? .white : Theme.primaryText)
                        .background(selected ? color : Theme.cardRaised, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}
