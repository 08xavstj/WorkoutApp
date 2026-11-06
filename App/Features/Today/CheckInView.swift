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
        // Joint pain, not muscle soreness: the trainer avoids or eases the lifts that load it (`PainGuard`).
        PainQuestions(pains: $morning.pains)
        MoodQuestions(mood: $morning.mood, feelings: $morning.feelings, associations: $morning.associations)
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
                        Button {
                            evening.caffeineMg = (evening.caffeineMg ?? 0) + preset.mg
                        } label: {
                            // With the bordered inset this makes a 44 pt target (ux-audit 4.8).
                            Text("+ \(preset.name)")
                                .frame(minHeight: 34)
                        }
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
            Text("For your usual \(CaffeineTiming.clockText(usualBedtime)) bedtime: last coffee by \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: usualBedtime, mg: 100))), pre-workout by \(CaffeineTiming.clockText(CaffeineTiming.cutoffMinutes(bedtimeMinutes: usualBedtime, mg: 200))). In a review of 24 studies, caffeine closer to bed than that cut sleep by about 45 minutes. \(CaffeineTiming.cautionNote)")
        }
        Section {
            if let logged = store.evening(on: evening.day), let total = logged.standardDrinks {
                NavigationLink {
                    AlcoholLogView(day: evening.day)
                } label: {
                    LabeledContent("\(logged.alcohol?.count ?? 0) drink\(logged.alcohol?.count == 1 ? "" : "s") logged",
                                   value: "\(total.formatted(.number.precision(.fractionLength(1)))) standard")
                }
            } else {
                Stepper("\(evening.drinks ?? 0) drinks", value: Binding(get: { evening.drinks ?? 0 }, set: { evening.drinks = $0 }), in: 0...20)
                if (evening.drinks ?? 0) > 0 {
                    optionalTime("Last drink", \.lastDrinkMinutes, default: 21 * 60)
                }
                NavigationLink("Log by type and amount") {
                    AlcoholLogView(day: evening.day)
                }
            }
        } header: {
            Text("Alcohol")
        } footer: {
            Text("A quick count is fine. Logging the type and amount counts standard drinks for you. Forgot last night? Tap Log › Drinks.")
        }
        Section("Stress today") {
            ScalePicker(value: $evening.stress, labels: ["Calm", "Low", "Some", "High", "Very high"], color: Theme.recoveryModerate)
        }
        MoodQuestions(mood: $evening.mood, feelings: $evening.feelings, associations: $evening.associations)
        Section("Food") {
            optionalTime("Last meal", \.lastMealMinutes, default: 19 * 60)
        }
        Section {
            Toggle("Nicotine or vaping", isOn: boolBinding(\.nicotine))
            Toggle("Sauna", isOn: boolBinding(\.sauna))
            Toggle("Cold plunge", isOn: boolBinding(\.coldPlunge))
        } header: {
            Text("Anything else today?")
        } footer: {
            // Roberts 2015; Piñero 2024 (cold) and Laukkanen 2015 (sauna); see `HeatAndCold`.
            VStack(alignment: .leading, spacing: 6) {
                Text("Cold plunge: " + HeatAndCold.coldPlungeNote)
                Text("Sauna: " + HeatAndCold.saunaNote)
            }
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
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
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
            // Mood → Apple Health state of mind (daily mood; iOS 18 type;
            // HealthKitClient+Writes), so Health's mental-wellbeing view sees it,
            // with the chosen words and what it's about, plus what the app knows:
            // training in the last day → fitness, symptoms → health (watch-features.md 4.2).
            if let mood = morning.mood, let health {
                var associations = morning.associations ?? []
                let dayAgo = Date.now.addingTimeInterval(-24 * 3600)
                if sessions.contains(where: { !$0.isActive && $0.startedAt >= dayAgo }), !associations.contains(MoodAssociation.fitness.rawValue) {
                    associations.append(MoodAssociation.fitness.rawValue)
                }
                if morning.isSick, !associations.contains(MoodAssociation.health.rawValue) {
                    associations.append(MoodAssociation.health.rawValue)
                }
                let feelings = morning.feelings ?? []
                Task {
                    try? await health.saveStateOfMind(mood: mood, date: .now, kind: .daily, feelings: feelings, associations: associations)
                }
            }
            // Symptoms → Apple Health symptom samples (HealthKitClient+Symptoms), so
            // Health and other apps see them; clearing them here clears Health too.
            if let health {
                let symptoms = morning.symptoms
                Task { try? await health.saveSymptoms(symptoms, date: .now) }
                // Lower back pain → Apple Health's symptom type, the only area it has.
                let backPain = morning.pains?.first { $0.area == .lowerBack }?.level
                Task { try? await health.saveLowerBackPain(level: backPain, date: .now) }
            }
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
            // Drinks logged one by one were saved straight to the store; keep them.
            if let logged = store.evening(on: evening.day), logged.alcohol != nil {
                evening.alcohol = logged.alcohol
                evening.syncDrinksFromAlcohol()
            }
            store.save(evening)
            // Evening mood (or, failing that, the stress scale turned around) →
            // a momentary emotion in Apple Health (watch-features.md 4.2).
            if let valence = evening.eveningValence, let health {
                let mood = evening.mood ?? evening.stress.map { 6 - $0 } ?? 3
                let feelings = evening.feelings ?? []
                let associations = evening.associations ?? []
                Task {
                    try? await health.saveStateOfMind(mood: mood, date: .now, valence: valence, kind: .momentary,
                                                      feelings: feelings, associations: associations)
                }
            }
        }
        dismiss()
    }
}

/// "Something hurts?": body areas, then 0-10 and "worse after training?" for
/// each. The trainer leaves out lifts that load a 6+/10 area, eases a
/// 3-5/10 one, and forgets an answer after 7 days unless it's logged again
/// (`PainGuard`). 0 clears an area. Used by the morning check-in and the
/// trainer's "Something hurts?" sheet.
struct PainQuestions: View {
    @Binding var pains: [PainReport]?

    private var areas: Binding<[PainArea]> {
        Binding(
            get: { (pains ?? []).map(\.area) },
            set: { newAreas in
                var kept = (pains ?? []).filter { newAreas.contains($0.area) }
                for area in newAreas where !kept.contains(where: { $0.area == area }) {
                    kept.append(PainReport(area: area, level: 0, loggedAt: .now))
                }
                pains = kept.isEmpty ? nil : kept
            }
        )
    }

    var body: some View {
        Section {
            ChipFlow(options: PainArea.allCases, selection: areas, label: \.title, color: Theme.recoveryLow)
            ForEach(pains ?? []) { report in
                PainLevelRow(area: report.area, level: level(for: report.area), worse: worse(for: report.area))
            }
        } header: {
            Text("Something hurts?")
        } footer: {
            Text(PainGuard.ruleText + " 0 clears an area. This isn't a diagnosis.")
        }
    }

    private func level(for area: PainArea) -> Binding<Int?> {
        Binding(
            get: { pains?.first { $0.area == area }?.level },
            set: { value in update(area) { $0.level = value ?? 0 } }
        )
    }

    private func worse(for area: PainArea) -> Binding<Bool> {
        Binding(
            get: { pains?.first { $0.area == area }?.worseAfterTraining ?? false },
            set: { value in update(area) { $0.worseAfterTraining = value } }
        )
    }

    private func update(_ area: PainArea, _ change: (inout PainReport) -> Void) {
        guard var list = pains, let index = list.firstIndex(where: { $0.area == area }) else { return }
        change(&list[index])
        list[index].loggedAt = .now
        pains = list
    }
}

/// One painful area: 0-10 and "worse after training?".
private struct PainLevelRow: View {
    let area: PainArea
    @Binding var level: Int?
    @Binding var worse: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(area.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ScalePicker(value: $level, range: 0...10, color: Theme.recoveryLow, endLabels: ("None", "Worst"))
            Toggle("Worse after training or the next day?", isOn: $worse)
                .font(.subheadline)
            if let note = note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// What the trainer will do with this answer.
    private var note: String? {
        let report = PainReport(area: area, level: level ?? 0, worseAfterTraining: worse, loggedAt: .now)
        switch PainGuard.response(to: report) {
        case .avoid: return "The trainer leaves out lifts that load \(area.possessive)."
        case .regress: return "The trainer picks easier variants and about 20% lighter loads for \(area.possessive)."
        case .unchanged: return nil
        }
    }
}

/// "How are you feeling?": the 1-5 mood, then optional words for it and
/// what it's about (Apple's State of Mind labels and associations; see
/// `MoodFeeling`, `MoodAssociation`). Nothing is required. The chips only
/// appear once a mood is picked, so the form stays short.
private struct MoodQuestions: View {
    @Binding var mood: Int?
    /// `MoodFeeling` raw values.
    @Binding var feelings: [String]?
    /// `MoodAssociation` raw values.
    @Binding var associations: [String]?

    var body: some View {
        Section {
            ScalePicker(value: $mood, labels: ["Low", "Meh", "OK", "Good", "Great"], color: Theme.recoveryHigh)
            if mood != nil {
                ChipFlow(options: MoodFeeling.allCases, selection: feelingSelection, label: \.title, color: Theme.recoveryHigh)
            }
        } header: {
            Text("How are you feeling?")
        }
        if mood != nil {
            Section {
                ChipFlow(options: MoodAssociation.allCases, selection: associationSelection, label: \.title, color: Theme.sleep)
            } header: {
                Text("What's affecting it?")
            } footer: {
                Text("Optional. Saved to Apple Health with your mood, and used to spot what moves it.")
            }
        }
    }

    private var feelingSelection: Binding<[MoodFeeling]> {
        Binding(
            get: { (feelings ?? []).compactMap(MoodFeeling.init(rawValue:)) },
            set: { feelings = $0.isEmpty ? nil : $0.map(\.rawValue) }
        )
    }

    private var associationSelection: Binding<[MoodAssociation]> {
        Binding(
            get: { (associations ?? []).compactMap(MoodAssociation.init(rawValue:)) },
            set: { associations = $0.isEmpty ? nil : $0.map(\.rawValue) }
        )
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
                    // A tap gesture, not a Button: a Form row full of buttons
                    // can pass a tap to the wrong one.
                    Text("\(number)")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? .white : Theme.primaryText)
                        .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(Theme.cardRaised), in: .rect(cornerRadius: 9))
                        .contentShape(.rect(cornerRadius: 9))
                        .onTapGesture { value = selected ? nil : number }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(labels.count == range.count ? "\(number), \(labels[number - range.lowerBound])" : "\(number)")
                        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                        .accessibilityAction { value = selected ? nil : number }
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
        // Row spacing 0: each chip's 44 pt hit area below keeps the same 8 pt visual gap.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = selection.contains(option)
                // A tap gesture, not a Button: in a Form row, a tap on one
                // button (or on the row around them) can trigger another, which
                // ticked symptoms nobody chose.
                Text(label(option))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(selected ? .white : Theme.primaryText)
                    .background(selected ? color : Theme.cardRaised, in: .capsule)
                    .padding(.vertical, 4)
                    .contentShape(.rect)
                    .onTapGesture { toggle(option) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(label(option))
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { toggle(option) }
            }
        }
    }

    private func toggle(_ option: Option) {
        if selection.contains(option) { selection.removeAll { $0 == option } } else { selection.append(option) }
    }
}
