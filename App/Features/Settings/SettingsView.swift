import SwiftUI
import AppCore

/// Settings, a sheet from the profile button on every tab. The root is one
/// short screen: You (name, goals, city), five pages (Profile, Training,
/// Notifications, Sleep & nutrition, Data & privacy), then Appearance and
/// About. It was a single list seven screens long; a short root with pages
/// one level down follows HIG Settings ("Minimize the number of settings you
/// offer") and NN/g's two-level limit for progressive disclosure
/// (docs/research/cleanup-2026-11.md, rules 1 and B). Pages push inside this
/// sheet's own stack; only the RPE guide, which has its own stack and is
/// shared with the workout screens, is still a sheet.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                YouSettingsSection()
                Section {
                    SettingsPageLink(title: "Profile", detail: "Age, height, weight, heart rate", icon: "person.fill", id: "profile") {
                        ProfileSettingsSection()
                    }
                    SettingsPageLink(title: "Training", detail: "Gym, rest timer, warm-up, Apple Watch", icon: "dumbbell.fill", id: "training") {
                        TrainingSettingsSection()
                    }
                    SettingsPageLink(title: "Notifications", detail: "Daily messages, reminders, doses", icon: "bell.fill", id: "notifications") {
                        CoachCheckInsSettingsSection()
                        // Offered in the morning check-in, so it sits with the daily messages.
                        MoodScreenSettingsSection()
                        RemindersSettingsSection()
                    }
                    SettingsPageLink(title: "Sleep & nutrition", detail: "Sleep need, rest mode, calories", icon: "bed.double.fill", id: "sleep-nutrition") {
                        SleepSettingsSection()
                        NutritionSettingsSection()
                    }
                    SettingsPageLink(title: "Data & privacy", detail: "Apple Health, Oura, route privacy, export", icon: "lock.fill", id: "data") {
                        DataSourcesSettingsSection()
                        CoachSettingsSection()
                        RoutePrivacySettingsSection()
                        DataExportSettingsSection()
                    }
                }
                AppearanceSettingsSection()
                AboutSettingsSection()
            }
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .background(Theme.background)
            .refreshingOnProfileChange()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// One row on the Settings root that pushes a page holding the given sections.
private struct SettingsPageLink<Sections: View>: View {
    let title: String
    let detail: String
    let icon: String
    /// "settings-<id>" for UI tests (ScreenshotTests).
    let id: String
    @ViewBuilder var sections: Sections

    var body: some View {
        NavigationLink {
            Form { sections }
                .scrollContentBackground(.hidden)
                .scrollEdgeEffectStyle(.hard, for: .top)
                .background(Theme.background)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityIdentifier("settings-\(id)")
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
    @AppStorage(VitalsModel.vo2SourceKey) private var vo2Source: VO2Source = .standard
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
            // "Not set" until given, instead of a silent male / 30 (`UserSettings.sexIsSet`).
            AgePickerRow(suffix: source("age"))
                .disabled(locked("age"))
            SexPickerRow(suffix: source("sex"))
                .disabled(locked("sex"))
            heightRow
            weightRow
        } header: {
            Text("Profile")
        } footer: {
            // Only mentions "Health" labels when the switch is on and there can be some.
            Text(settings.profileFromHealth
                 ? "Age and sex set your heart-rate zones, calorie estimate and fitness norms. Fields marked \"Health\" come from Apple Health and update by themselves; add missing ones in Apple Health (profile › Health Details), or turn the switch off to type your own."
                 : "Age and sex set your heart-rate zones, calorie estimate and fitness norms. Turn on the switch to fill them in from Apple Health.")
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
        Section {
            Picker("VO₂ max to use", selection: $vo2Source) {
                ForEach(VO2Source.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } footer: {
            // Lambe et al., PLOS ONE 2025 (`VO2Source`).
            Text("Your fitness level and the coach use this one. Apple Watch only measures on outdoor walks, runs and hikes. \(VO2Source.appleWatchAccuracy) Tensile's estimate comes from your resting and max heart rate and your activity, lifting included, and is about ±5. If the one you pick has no value yet, the other is used.")
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
    /// The guide opens from its own row: this section now sits on a pushed
    /// page, so the sheet is presented from here, not from the Settings root.
    @State private var showingRPEGuide = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            // Your gyms, travel gyms and the one you're at (`GymsView`).
            NavigationLink {
                GymsView()
            } label: {
                LabeledContent("Gym equipment", value: gym.isConfigured ? gym.activeGym.name : "Not set up")
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
            HeartZonesSettingsRow() // Which heart-rate zones workouts and the Watch's cardio mode show.
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
            Button {
                showingRPEGuide = true
            } label: {
                LabeledContent("Reps left guide", value: "How the rating works")
            }
            .accessibilityIdentifier("settings-reps-left-guide") // UI tests (ScreenshotTests)
            .sheet(isPresented: $showingRPEGuide) { RPEGuideView() }
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
    @Environment(AppRouter.self) private var router
    /// iOS notifications are off for the app: nothing below can arrive.
    @State private var notificationsDenied = false
    /// iOS hasn't been asked yet: reminders that are on can't arrive until it is.
    @State private var notificationsNotAsked = false
    @State private var stretch = StretchStore.shared
    /// Today's doses as a Lock Screen card (`MedsLiveActivity`); on unless switched off.
    @AppStorage(MedsLiveActivity.enabledKey, store: SharedStore.defaults) private var dosesOnLockScreen = true
    /// Waist, grip and blood pressure reminders (`Reminders.measurementRemindersKey`); on unless switched off.
    @AppStorage(Reminders.measurementRemindersKey) private var measurementReminders = true

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
        Section {
            if notificationsDenied {
                NotificationsOffBanner(detail: "Workout and dose reminders won't arrive until you allow them.")
            } else if notificationsNotAsked {
                // Reminders never ask at launch; a switch below asks when it's turned on, and so does this.
                Button(action: askForNotifications) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow notifications")
                        Text("Reminders that are on can't arrive until iOS is allowed to send them.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            // The check-in has no reminder of its own: the daily messages above carry it.
            workoutRows
            stretchRows
            Toggle(isOn: $measurementReminders) {
                Text("Measurement reminders")
                Text("Monthly waist, grip twice a year, blood pressure re-check")
            }
            // On an always-present row: a modifier on the Section would run per row.
            .trackingNotificationsDenied($notificationsDenied)
            .task {
                notificationsNotAsked = await CoachNudges.permissionNotYetAsked()
            }
            // Asked from another switch (a daily message's, above): the row above goes.
            .onChange(of: router.remindersVersion) { notificationsNotAsked = false }
            .onChange(of: measurementReminders) { _, on in
                if on { askForNotifications() }
                Task { await Reminders.measurementRemindersChanged() }
            }
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
            Toggle(isOn: $dosesOnLockScreen) {
                Text("Doses on the Lock Screen")
                Text("A card with Taken buttons, from two hours before a dose; supplements from noon")
            }
            .onChange(of: dosesOnLockScreen) { _, on in
                Task {
                    if on {
                        await Reminders.startMedsActivityIfNeeded()
                    } else {
                        await Reminders.endMedsActivities()
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Every reminder here can be switched off, and iOS is only asked to allow notifications when you turn one on.")
        }
    }

    /// Asks iOS to allow notifications if it hasn't been asked yet (a reminder
    /// was just switched on), then has the app schedule everything that is on.
    private func askForNotifications() {
        Task {
            guard await CoachNudges.permissionNotYetAsked() else { return }
            let allowed = await Reminders.requestPermission()
            notificationsNotAsked = false
            notificationsDenied = !allowed
            if allowed { router.remindersVersion += 1 }
        }
    }

    /// "Creatine at 8:00 AM · dose reminders", or what the list is for.
    private var medsDetail: String {
        guard meds.creatineReminderOn, let time = Reminders.fireDate(day: .now, minutes: meds.creatineMinutes) else {
            return "Dose reminders with a Taken button"
        }
        return "Creatine at \(time.formatted(date: .omitted, time: .shortened)) · dose reminders"
    }

    /// The daily 5-minute stretch (`Stretching`): off until switched on, in the evening.
    @ViewBuilder
    private var stretchRows: some View {
        Toggle(isOn: Binding(get: { stretch.remindersOn }, set: { on in
            stretch.remindersOn = on
            if on { askForNotifications() }
            rescheduleStretch()
        })) {
            Text("Stretch reminder")
            Text("5 minutes a day, skipped once done; moved or skipped around a session")
        }
        if stretch.remindersOn {
            DatePicker("Stretch at", selection: Binding(
                get: { Reminders.fireDate(day: .now, minutes: stretch.reminderMinutes) ?? .now },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    stretch.reminderMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    rescheduleStretch()
                }
            ), displayedComponents: .hourAndMinute)
        }
    }

    /// Reschedules with what's known here; the app's next refresh adds today's planned session.
    private func rescheduleStretch() {
        let enabled = stretch.remindersOn && !settings.isRestMode
        let minutes = stretch.reminderMinutes
        let done = stretch.stretchedToday
        Task { await Reminders.scheduleStretchReminders(enabled: enabled, minutes: minutes, doneToday: done, slots: [], areas: []) }
    }

    @ViewBuilder
    private var workoutRows: some View {
        @Bindable var settings = settings
        Toggle(isOn: $settings.workoutRemindersOn) {
            Text("Workout reminders")
            Text("30 min before a planned training day")
        }
        .onChange(of: settings.workoutRemindersOn) { _, on in
            if on { askForNotifications() }
        }
        if settings.workoutRemindersOn, Reminders.workoutRemindersPaused {
            Text("Quiet for a few days: the last ones went unanswered. They come back sooner when you train or confirm a plan.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        if settings.workoutRemindersOn {
            // Tone (Playful or Plain) and "Show me one".
            WorkoutVoiceSettingsRows()
        }
        // The same setting as This week › Weekly review.
        Toggle(isOn: $settings.weeklyReviewOn) {
            Text("Monday review reminder")
            Text("Last week in numbers, one change for the week (up to three); skipped once you've opened it")
        }
        .onChange(of: settings.weeklyReviewOn) {
            // Asks iOS when this is the switch that turns it on (`Reminders.scheduleWeeklyReview`).
            Task { await Reminders.rescheduleWeeklyReview() }
        }
        if settings.weeklyReviewOn {
            DatePicker("Review time", selection: minutesBinding(\.weeklyReviewMinutes), displayedComponents: .hourAndMinute)
        }
    }
}

// MARK: - Sleep, nutrition, coach

private struct SleepSettingsSection: View {
    @Environment(UserSettings.self) private var settings
    @AppStorage(SleepSourceSetting.key) private var sleepSource: SleepSourcePreference = .standard

    var body: some View {
        @Bindable var settings = settings
        Section {
            Stepper(value: $settings.sleepNeedHours, in: 6...10, step: 0.25) {
                LabeledContent("Sleep need", value: Duration.seconds(settings.sleepNeedHours * 3600).formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
            }
            // Oura ring or Apple Watch first (`SleepSourceSetting`); also under Data sources › Oura Ring.
            Picker("Sleep from", selection: $sleepSource) {
                ForEach(SleepSourcePreference.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Toggle("Rest mode (sick or resting)", isOn: Binding(
                get: { settings.isRestMode },
                set: { settings.setRestMode($0) }
            ))
            // The insomnia path's way in (`SleepWindowView`); nothing else of it shows until it applies.
            SleepWindowSettingsRow()
        } header: {
            Text("Sleep & rest")
        } footer: {
            Text("Sleep need sets your sleep score and sleep debt; adults need 7 hours or more. Sleep from picks whose night counts when you wear more than one tracker to bed. Rest mode pauses strain targets and workout nudges for 3 days, then turns itself off.")
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
            Text("Chats, health data and photos stay on this iPhone. Only weather (your city, via Open-Meteo) and medication names (FDA drug labels) are looked up online, plus your Oura data if you connect your ring. Map tiles come from Apple Maps for the routes you view or share.")
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
            NavigationLink {
                OuraSettingsView()
            } label: {
                LabeledContent("Oura Ring", value: OuraLink.shared.status == .connected ? "Connected" : "Not connected")
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
