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
            maxHeartRateRow
            if settings.maxHeartRate == 0, settings.learnedMaxOverride != nil {
                Button("Reset learned max heart rate", role: .destructive) {
                    settings.resetLearnedMaxHeartRate()
                }
            }
            heightRow
            weightRow
        } header: {
            Text("Profile")
        } footer: {
            Text("Age and sex set your heart-rate zones, calorie estimate and body age. Fields marked \"Health\" come from Apple Health and update by themselves; add missing ones in Apple Health (profile → Health Details) or turn the switch off to type your own. Leave max heart rate blank and the app learns it from your hardest workouts; only type it if you've had it measured.")
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
        LabeledContent("Weight\(source("weight"))") {
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
        }
    }
}

// MARK: - Training

/// Gym equipment (the canonical place for it, ux-audit.md 4.3), rest, the
/// Watch, the RPE guide and lifting experience.
private struct TrainingSettingsSection: View {
    @Environment(UserSettings.self) private var settings
    @Environment(GymStore.self) private var gym
    /// 0 = automatic (from your goal). See RestPreferences.
    @AppStorage(RestPreferences.globalKey) private var restSeconds = 0
    let showRPEGuide: () -> Void

    var body: some View {
        @Bindable var settings = settings
        Section {
            NavigationLink {
                MyGymView(pushed: true)
            } label: {
                LabeledContent("Gym equipment", value: gym.isConfigured ? gym.profile.name : "Not set up")
            }
            Picker("Rest timer", selection: $restSeconds) {
                Text("Automatic").tag(0)
                ForEach(RestTimer.choices, id: \.self) { seconds in
                    Text(RestPreferences.label(seconds)).tag(seconds)
                }
            }
            Toggle("Start workouts on Apple Watch", isOn: $settings.startWatchWithWorkout)
            // Warm-up before lifting (`WarmUpRoutine.Tier`); the builder can
            // override it per focus. Default: ramp sets only (best evidence:
            // Ribeiro 2020 IJERPH; Ribeiro/Neves 2021 Motricidade).
            Picker("Warm-up", selection: $settings.warmUpTier) {
                ForEach(WarmUpRoutine.Tier.allCases) { tier in
                    Text(tier.menuLabel).tag(tier)
                }
            }
            Button(action: showRPEGuide) {
                LabeledContent("RPE guide", value: "What each number means")
            }
            LiftingExperienceRows()
        } header: {
            Text("Training")
        } footer: {
            Text("Gym equipment lists what your gym has, down to the plates and dumbbells, so planned weights are ones you can load. Automatic rest follows your goal: about 2 min on big lifts and 90 s on small ones for muscle, 3 min for strength; set rest per exercise from its ••• menu during a workout. Warm-up: ramp sets have the best evidence. Movement prep adds a small, mostly feel-based benefit. You can pick a different warm-up for one focus from the workout planner. Lifting experience is used to choose your calorie equation and how fast to gain. Your logged workouts update it once there are 8 weeks of them; the 6-month and 2-year lines are rough guides, not exact.")
        }
    }
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

    private var creatineOn: Binding<Bool> {
        Binding(
            get: { meds.creatineReminderOn },
            set: { meds.setCreatineReminder(on: $0) }
        )
    }

    private var creatineTime: Binding<Date> {
        Binding(
            get: { Reminders.fireDate(day: .now, minutes: meds.creatineMinutes) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                meds.setCreatineReminder(on: true, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Check-in reminders", isOn: $settings.checkInRemindersOn)
            if settings.checkInRemindersOn {
                DatePicker("Morning", selection: minutesBinding(\.morningCheckInMinutes), displayedComponents: .hourAndMinute)
                DatePicker("Evening", selection: minutesBinding(\.eveningCheckInMinutes), displayedComponents: .hourAndMinute)
            }
            workoutRows
            Toggle("Daily creatine", isOn: creatineOn)
            if meds.creatineReminderOn {
                DatePicker("Creatine time", selection: creatineTime, displayedComponents: .hourAndMinute)
            }
            // The list itself is Health › Records › Medications (ux-audit.md 4.3).
            NavigationLink("Medication reminders") {
                MedicationsView(pushed: true)
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Two check-ins a day: a morning one for last night's HRV and how you feel, and an evening one for one win and how today felt, with tonight's bed-by time. Each is skipped once it's done. Workout reminders come 30 minutes before a planned training day only, with your if-then line; after two go unanswered they pause until you confirm the next week's plan. The Monday review shows last week in plain numbers, then three changes for this week. Medication and creatine reminders have a Taken button, and today's doses also show on your Lock Screen.")
        }
    }

    @ViewBuilder
    private var workoutRows: some View {
        @Bindable var settings = settings
        Toggle("Workout reminders", isOn: $settings.workoutRemindersOn)
        if settings.workoutRemindersOn, Reminders.workoutRemindersPaused {
            Text("Paused: two in a row went unanswered. They come back when you confirm next week's plan.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        // The same setting as This week › Weekly review.
        Toggle("Monday review reminder", isOn: $settings.weeklyReviewOn)
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
            Text("The coach runs on your iPhone with Apple Intelligence; your data never leaves the device.")
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
            Text("iOS only shows the permission screen once. To change access later, open Apple Health → your profile picture → Apps → Tensile, and tap Turn On All.")
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
