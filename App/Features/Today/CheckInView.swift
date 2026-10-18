import SwiftUI
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    // MARK: Morning

    @ViewBuilder
    private var morningQuestions: some View {
        Section {
            TextField("e.g. 52", value: $hrv, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .font(.title3.weight(.semibold))
        } header: {
            Text("Last night's HRV (ms)")
        } footer: {
            Text("From Garmin Connect → HRV Status. Optional, but it makes recovery accurate.")
        }
        Section("How rested do you feel?") {
            ScalePicker(value: $morning.rested, labels: ["Exhausted", "Tired", "OK", "Good", "Great"], color: Theme.sleep)
        }
        Section {
            ScalePicker(value: $morning.soreness, range: 0...10, color: Theme.lifting)
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
        Section {
            Button {
                save()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(400))
                    router.showProgressPhotos = true
                }
            } label: {
                Label("Take progress photos", systemImage: "camera.fill")
            }
        } footer: {
            Text("Saves your answers so far, then opens the camera for your front and side photos.")
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
                DatePicker("Last caffeine", selection: minutesBinding(\.lastCaffeineMinutes, default: 13 * 60), displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Caffeine today")
        } footer: {
            Text("Caffeine lasts about 5 hours in the body; 400 mg even 6 hours before bed cut sleep by over an hour in one study.")
        }
        Section("Alcohol") {
            Stepper("\(evening.drinks ?? 0) drinks", value: Binding(get: { evening.drinks ?? 0 }, set: { evening.drinks = $0 }), in: 0...20)
            if (evening.drinks ?? 0) > 0 {
                DatePicker("Last drink", selection: minutesBinding(\.lastDrinkMinutes, default: 21 * 60), displayedComponents: .hourAndMinute)
            }
        }
        Section("Stress today") {
            ScalePicker(value: $evening.stress, labels: ["Calm", "Low", "Some", "High", "Very high"], color: Theme.recoveryModerate)
        }
        Section("Food") {
            DatePicker("Last meal", selection: minutesBinding(\.lastMealMinutes, default: 19 * 60), displayedComponents: .hourAndMinute)
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
    }

    private func save() {
        switch kind {
        case .morning:
            if let hrv, hrv > 0 {
                if let existing = todayHRV {
                    existing.milliseconds = hrv
                } else {
                    modelContext.insert(HRVReading(date: .now, milliseconds: hrv))
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
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .foregroundStyle(selected ? .white : Theme.primaryText)
                            .background(selected ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Theme.cardRaised), in: .rect(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let value, labels.count == range.count {
                Text(labels[value - range.lowerBound])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
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
            }
        }
    }
}
