import SwiftUI
import AppCore

/// Settings, a sheet from the profile button on every tab. One inset-grouped
/// list in the order of ux-audit.md 4.6: You → Profile → Training →
/// Reminders → Sleep & rest → Nutrition → Coach → Data sources → Appearance →
/// About. Everything that opens a page pushes inside this sheet's own stack
/// (ux-audit.md 4.1 rule 5); only the RPE guide, which has its own stack and
/// is shared with the workout screens, is still a sheet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingRPEGuide = false

    var body: some View {
        NavigationStack {
            Form {
                YouSettingsSection()
                ProfileSettingsSection()
                TrainingSettingsSection(showRPEGuide: { showingRPEGuide = true })
                RemindersSettingsSection()
                SleepSettingsSection()
                NutritionSettingsSection()
                CoachSettingsSection()
                DataSourcesSettingsSection()
                AppearanceSettingsSection()
                AboutSettingsSection()
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(Theme.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingRPEGuide) { RPEGuideView() }
        }
    }
}

// MARK: - You

private struct YouSettingsSection: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            TextField("Your name", text: $settings.name)
                .textContentType(.givenName)
            NavigationLink {
                GoalsView(pushed: true)
            } label: {
                LabeledContent("Goals", value: settings.goalsSet ? settings.goals.title : "Not set")
            }
            NavigationLink {
                LocationPicker(pushed: true)
            } label: {
                LabeledContent("City", value: settings.hasLocation ? settings.placeName : "Not set")
            }
        } header: {
            Text("You")
        } footer: {
            Text("Your city gives the coach local weather, air quality and daylight hours. Only the city's coordinates are stored, on this phone.")
        }
    }
}

// MARK: - Profile

private struct ProfileSettingsSection: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 80
    @ScaledMetric(relativeTo: .body) private var wideFieldWidth: CGFloat = 110

    /// " · Health" when Apple Health filled this field.
    private func source(_ field: String) -> String {
        locked(field) ? " · Health" : ""
    }

    private func locked(_ field: String) -> Bool {
        settings.profileFromHealth && settings.healthFilledFields.contains(field)
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Fill in from Apple Health", isOn: $settings.profileFromHealth)
                .onChange(of: settings.profileFromHealth) { _, on in
                    if on, let health { Task { await settings.syncProfile(from: health) } }
                }
            Stepper("Age: \(settings.age)\(source("age"))", value: $settings.age, in: 13...100)
                .disabled(locked("age"))
            Picker("Sex\(source("sex"))", selection: $settings.sex) {
                Text("Male").tag(BiologicalSex.male)
                Text("Female").tag(BiologicalSex.female)
            }
            .disabled(locked("sex"))
            heightRow
            weightRow
        } header: {
            Text("Profile")
        } footer: {
            // Only mentions "Health" labels when the switch is on and there can be some.
            Text(settings.profileFromHealth
                 ? "Age and sex set your heart-rate zones, calorie estimate and body age. Fields marked \"Health\" come from Apple Health and update by themselves; add missing ones in Apple Health (profile › Health Details), or turn the switch off to type your own."
                 : "Age and sex set your heart-rate zones, calorie estimate and body age. Turn on the switch to fill them in from Apple Health.")
        }
        Section {
            maxHeartRateRow
            if settings.maxHeartRate == 0, settings.learnedMaxOverride != nil {
                Button("Reset learned max heart rate", role: .destructive) {
                    settings.resetLearnedMaxHeartRate()
                }
            }
        } footer: {
            Text("Leave it blank and the app learns it from your hardest workouts. Only type it if you've had it measured.")
        }
    }

    private var maxHeartRateRow: some View {
        LabeledContent("Max heart rate") {
            HStack(spacing: 4) {
                TextField(
                    settings.learnedMaxOverride.map { "\(Int($0)) learned" } ?? "\(Int(settings.estimatedMaxHeartRate)) est.",
                    value: Binding<Int?>(
                        get: { settings.maxHeartRate > 0 ? settings.maxHeartRate : nil },
                        set: { settings.maxHeartRate = min(230, max(0, $0 ?? 0)) }
                    ),
                    format: .number
                )
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: wideFieldWidth)
                Text("bpm").foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Inches alongside pounds, centimetres alongside kilograms; stored in cm (`LengthUnit`).
    private var heightUnit: LengthUnit { settings.weightUnit == .pounds ? .inches : .centimeters }

    private var heightRow: some View {
        LabeledContent("Height\(source("height"))") {
            HStack(spacing: 4) {
                TextField(heightUnit.rawValue, value: Binding(
                    get: { (heightUnit.display(settings.heightCm) * 10).rounded() / 10 },
                    set: { settings.heightCm = heightUnit.toCentimeters($0) }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .disabled(locked("height"))
                Text(heightUnit.rawValue).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var weightRow: some View {
        LabeledContent {
            HStack(spacing: 4) {
                TextField(settings.weightUnit.rawValue, value: Binding(
                    get: { (settings.weightUnit.display(settings.weightKg) * 10).rounded() / 10 },
                    set: { settings.weightKg = settings.weightUnit.toKilograms($0) }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .disabled(locked("weight"))
                Text(settings.weightUnit.rawValue).foregroundStyle(Theme.secondaryText)
            }
        } label: {
            Text("Weight\(source("weight"))")
            // Health › Weight shows the smoothed trend, so the two can differ a little.
            Text("Latest scale reading, not the trend")
        }
    }
}

// MARK: - Training

/// Gym equipment (the canonical place for it, ux-audit.md 4.3), rest, the
/// Watch, the warm-up, the abs finisher, the RPE guide and lifting experience.
private struct TrainingSettingsSection: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    /// 0 = automatic (from your goal). See RestPreferences.
    @AppStorage(RestPreferences.globalKey) private var restSeconds = 0
    /// How rest end is signalled (`RestAlertPolicy`); in the App Group for the Live Activity's buttons.
    @AppStorage(RestAlertMode.key, store: SharedStore.defaults) private var restAlerts = RestAlertMode.watchFirst
    let showRPEGuide: () -> Void

    var body: some View {
        @Bindable var settings = settings
        Section {
            NavigationLink {
                MyGymView(pushed: true)
            } label: {
                LabeledContent("Gym equipment", value: gym.isConfigured ? gym.profile.name : "Not set up")
            }
            Picker(selection: $restSeconds) {
                Text("Automatic").tag(0)
                ForEach(RestTimer.choices, id: \.self) { seconds in
                    Text(RestPreferences.label(seconds)).tag(seconds)
                }
            } label: {
                Text("Rest timer")
                Text("Automatic follows your goal")
            }
            Picker(selection: $restAlerts) {
                ForEach(RestAlertMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            } label: {
                Text("Rest timer alerts")
                Text("No banner while the app is open")
            }
            .onChange(of: restAlerts) {
                Task { await WorkoutLiveActivity.rescheduleRestAlert() }
            }
            Toggle("Start workouts on Apple Watch", isOn: $settings.startWatchWithWorkout)
            Toggle(isOn: $settings.watchRepCounting) {
                Text("Count reps on Apple Watch")
                Text("Experimental · squat and deadlift only")
            }
            // Warm-up before lifting (`WarmUpRoutine.Tier`); the builder can
            // override it per focus. Default: ramp sets only (best evidence:
            // Ribeiro 2020 IJERPH; Ribeiro/Neves 2021 Motricidade).
            Picker(selection: $settings.warmUpTier) {
                ForEach(WarmUpRoutine.Tier.allCases) { tier in
                    Text(tier.menuLabel).tag(tier)
                }
            } label: {
                Text("Warm-up")
                Text("Ramp sets have the best evidence")
            }
            // Ab work on top of planned sessions (`AbsFinisher`); the builder can change it for one session.
            Picker(selection: $settings.absFinisher) {
                ForEach(AbsFinisher.Length.allCases) { length in
                    Text(length.label).tag(length)
                }
            } label: {
                Text("Abs finisher")
                Text("Added on top of planned workouts")
            }
            Button(action: showRPEGuide) {
                LabeledContent("RPE guide", value: "What each number means")
            }
            LiftingExperienceRows()
            EvidenceDisclosure(points: Self.details, title: "How these work")
        } header: {
            Text("Training")
        } footer: {
            Text("Planned weights use only what your gym can load.")
        }
    }
}

extension TrainingSettingsSection {
    /// The details that used to fill the footer, one short point per control.
    fileprivate static let details = [
        "Rest: automatic is about 2 min on big lifts and 90 s on small ones for muscle, 3 min for strength. Change one exercise from its ••• menu.",
        "Rest timer alerts: with the Watch app recording, only the Watch buzzes. Otherwise the phone alerts when the app is closed, and iOS passes it to the Watch while the phone is locked. With the app open, the timer turns green and taps once.",
        "Warm-up: movement prep adds a small, mostly feel-based benefit. Pick a different warm-up for one focus in the planner.",
        "Abs finisher: 5 or 10 minutes of paired ab moves after a planned workout, rotating crunches, leg raises and bracing. It builds the muscle; it won't burn belly fat on its own (Vispute 2011).",
        "Lifting experience picks your calorie equation and gain rate. After 8 weeks of logged workouts, your log sets it.",
        "Rep counting reads barbell squats and deadlifts from wrist motion and taps when the bar slows by about a fifth (1–2 reps left). Check it against how the set felt. Motion data stays on the Watch.",
    ]
}

/// How long you've lifted, for people who trained before they installed the
/// app (`TrainingStatus.resolve`; Helms 2014 and Iraki 2019 via
/// docs/research/calories.md), and the level the app currently uses.
private struct LiftingExperienceRows: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(AppRefresher.self) private var refresher

    var body: some View {
        @Bindable var settings = settings
        Picker("Lifting experience", selection: $settings.liftingExperience) {
            Text("Not set").tag(LiftingExperience?.none)
            ForEach(LiftingExperience.allCases, id: \.self) { experience in
                Text(experience.label).tag(Optional(experience))
            }
        }
        // The calorie equation and gain limit are worked out in a refresh.
        .onChange(of: settings.liftingExperience) {
            Task { await refresher.refresh() }
        }
        if let status = metrics.trainingStatus {
            LabeledContent("Counted as", value: status.label)
        }
    }
}

// MARK: - Reminders

private struct RemindersSettingsSection: View {
    @Environment(UserSettings.self) private var settings
    @Environment(MedicationsModel.self) private var meds

    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<UserSettings, Int>) -> Binding<Date> {
        Binding(
            get: { Reminders.fireDate(day: .now, minutes: settings[keyPath: keyPath]) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.checkInRemindersOn) {
                Text("Check-in reminders")
                Text("Morning and evening, skipped once done")
            }
            if settings.checkInRemindersOn {
                DatePicker("Morning", selection: minutesBinding(\.morningCheckInMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Evening", selection: minutesBinding(\.eveningCheckInMinutes), displayedComponents: .hourAndMinute)
            }
            workoutRows
            // Dose reminders, creatine included, are set on each entry in the list
            // (Health › Records › Medications; ux-audit.md 4.3), so they live in one place.
            NavigationLink {
                MedicationsView(pushed: true)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Medications & supplements")
                    Text(medsDetail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Today's doses also show on your Lock Screen.")
        }
    }

    /// "Creatine at 8:00 AM · dose reminders", or what the list is for.
    private var medsDetail: String {
        guard meds.creatineReminderOn, let time = Reminders.fireDate(day: .now, minutes: meds.creatineMinutes) else {
            return "Dose reminders with a Taken button"
        }
        return "Creatine at \(time.formatted(date: .omitted, time: .shortened)) · dose reminders"
    }

    @ViewBuilder
    private var workoutRows: some View {
        @Bindable var settings = settings
        Toggle(isOn: $settings.workoutRemindersOn) {
            Text("Workout reminders")
            Text("30 min before a planned training day")
        }
        if settings.workoutRemindersOn, Reminders.workoutRemindersPaused {
            Text("Paused after two went unanswered. Confirm next week's plan to resume.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        // The same setting as This week › Weekly review.
        Toggle(isOn: $settings.weeklyReviewOn) {
            Text("Monday review reminder")
            Text("Last week in numbers, three changes")
        }
        if settings.weeklyReviewOn {
            DatePicker("Review time", selection: minutesBinding(\.weeklyReviewMinutes), displayedComponents: .hourAndMinute)
        }
    }
}

// MARK: - Sleep, nutrition, coach

private struct SleepSettingsSection: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Stepper(value: $settings.sleepNeedHours, in: 6...10, step: 0.25) {
                LabeledContent("Sleep need", value: Duration.seconds(settings.sleepNeedHours * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
            }
            Toggle("Rest mode (sick or resting)", isOn: Binding(
                get: { settings.isRestMode },
                set: { settings.setRestMode($0) }
            ))
        } header: {
            Text("Sleep & rest")
        } footer: {
            Text("Sleep need sets your sleep score and sleep debt; adults need 7 hours or more. Rest mode pauses strain targets and workout nudges for 3 days, then turns itself off.")
        }
    }
}

private struct NutritionSettingsSection: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Hide calories", isOn: $settings.hideCalories)
        } header: {
            Text("Nutrition")
        } footer: {
            Text("Shows protein and fibre only, on Today and in the coach's chips. Calorie numbers aren't helpful for everyone; the app still uses them for maintenance and the coach.")
        }
    }
}

private struct CoachSettingsSection: View {
    var body: some View {
        Section {
            LabeledContent("Runs on", value: "This iPhone")
            if let message = OnDeviceCoach.availabilityMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
        } header: {
            Text("Coach")
        } footer: {
            Text("Chats, health data and photos stay on this iPhone. Only weather (your city, via Open-Meteo) and medication names (FDA drug labels) are looked up online.")
        }
    }
}

// MARK: - Data sources

/// Apple Health access plus setup help for the apps that feed it
/// (ux-audit.md 4.3, S4).
private struct DataSourcesSettingsSection: View {
    @Environment(\.healthClient) private var health

    var body: some View {
        Section {
            Button("Ask for Apple Health access") {
                Task { try? await health?.requestAuthorization() }
            }
            if let healthURL = URL(string: "x-apple-health://") {
                Link("Open Apple Health", destination: healthURL)
            }
            NavigationLink("Using a Garmin") {
                GarminHelpView()
            }
            NavigationLink("Using Cronometer") {
                CronometerHelpView()
            }
        } header: {
            Text("Data sources")
        } footer: {
            Text("iOS only shows the permission screen once. To change access later, open Apple Health › your profile picture › Apps › Tensile, and tap Turn On All.")
        }
    }
}

// MARK: - Appearance, about

/// Theme and units together (ux-audit.md S3: no one-row sections).
private struct AppearanceSettingsSection: View {
    @Environment(UserSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section("Appearance") {
            Picker("Theme", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.label).tag(appearance)
                }
            }
            Picker("Weight unit", selection: $settings.weightUnit) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.rawValue).tag(unit)
                }
            }
        }
    }
}

private struct AboutSettingsSection: View {
    var body: some View {
        Section("About") {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
            Text("Exercise library: free-exercise-db (public domain). Muscle map outlines: react-body-highlighter (MIT, © 2020 GV79). Weather data by Open-Meteo.com (CC BY 4.0). Drug labels: openFDA. Scores are estimates for training guidance, not medical advice.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
