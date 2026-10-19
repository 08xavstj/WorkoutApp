import SwiftUI
import AppCore

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(GymStore.self) private var gym
    @Environment(MedicationsModel.self) private var meds
    @Environment(\.dismiss) private var dismiss
    @State private var showingGym = false
    @State private var showingMeds = false
    @State private var showingLocation = false
    @State private var showingGoals = false
    @State private var showingRPEGuide = false
    /// 0 = automatic (from your goal). See RestPreferences.
    @AppStorage(RestPreferences.globalKey) private var restSeconds = 0

    /// " · Health" when Apple Health filled this field.
    private func source(_ field: String) -> String {
        locked(field) ? " · Health" : ""
    }

    private func minutesBinding(_ keyPath: ReferenceWritableKeyPath<UserSettings, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings[keyPath: keyPath] * 60)) },
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
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(meds.creatineMinutes * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                meds.setCreatineReminder(on: true, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(settings.hrvReminderMinutes * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.hrvReminderMinutes = (parts.hour ?? 7) * 60 + (parts.minute ?? 30)
            }
        )
    }

    private func locked(_ field: String) -> Bool {
        settings.profileFromHealth && settings.healthFilledFields.contains(field)
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $settings.name)
                        .textContentType(.givenName)
                    Button {
                        showingLocation = true
                    } label: {
                        LabeledContent("Where you live", value: settings.hasLocation ? settings.placeName : "Not set")
                    }
                    Button {
                        showingGoals = true
                    } label: {
                        LabeledContent("Goals", value: settings.goalsSet ? settings.goals.title : "Not set")
                    }
                } header: {
                    Text("You")
                } footer: {
                    Text("Your city gives the coach local weather, air quality and daylight hours. Only the city's coordinates are stored, on this phone.")
                }

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
                            .frame(width: 110)
                            Text("bpm").foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if settings.maxHeartRate == 0, settings.learnedMaxOverride != nil {
                        Button("Reset learned max heart rate", role: .destructive) {
                            settings.resetLearnedMaxHeartRate()
                        }
                    }
                    LabeledContent("Height\(source("height"))") {
                        TextField("cm", value: $settings.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .disabled(locked("height"))
                        Text("cm").foregroundStyle(Theme.secondaryText)
                    }
                    LabeledContent("Weight\(source("weight"))") {
                        TextField(settings.weightUnit.rawValue, value: Binding(
                            get: { (settings.weightUnit.display(settings.weightKg) * 10).rounded() / 10 },
                            set: { settings.weightKg = settings.weightUnit.toKilograms($0) }
                        ), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .disabled(locked("weight"))
                        Text(settings.weightUnit.rawValue).foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Age and sex set your heart-rate zones, calorie estimate and body age. Fields marked \"Health\" come from Apple Health and update by themselves; add missing ones in the Health app (profile → Health Details) or turn the switch off to type your own. Leave max heart rate blank and the app learns it from your hardest workouts; only type it if you've had it measured.")
                }

                Section {
                    Button {
                        showingGym = true
                    } label: {
                        LabeledContent("My Gym", value: gym.isConfigured ? gym.profile.name : "Not set up")
                    }
                    Button {
                        showingRPEGuide = true
                    } label: {
                        LabeledContent("RPE guide", value: "What each number means")
                    }
                    Picker("Rest timer", selection: $restSeconds) {
                        Text("Automatic").tag(0)
                        ForEach(RestTimer.choices, id: \.self) { seconds in
                            Text(RestPreferences.label(seconds)).tag(seconds)
                        }
                    }
                } header: {
                    Text("Trainer")
                } footer: {
                    Text("Your equipment, plates and dumbbells, so planned weights are ones you can load. Automatic rest follows your goal: about 2 min on big lifts and 90 s on small ones for muscle, 3 min for strength. You can also set rest per exercise from its ••• menu during a workout.")
                }

                Section {
                    Toggle("Check-in reminders", isOn: $settings.checkInRemindersOn)
                    if settings.checkInRemindersOn {
                        DatePicker("Morning", selection: minutesBinding(\.morningCheckInMinutes), displayedComponents: .hourAndMinute)
                        DatePicker("Evening", selection: minutesBinding(\.eveningCheckInMinutes), displayedComponents: .hourAndMinute)
                    }
                    Toggle("Separate HRV reminder", isOn: $settings.hrvReminderOn)
                    if settings.hrvReminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                    Toggle("Daily creatine", isOn: creatineOn)
                    if meds.creatineReminderOn {
                        DatePicker("Creatine time", selection: creatineTime, displayedComponents: .hourAndMinute)
                    }
                    Button {
                        showingMeds = true
                    } label: {
                        LabeledContent("Medications", value: "Reminders & effects")
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("The morning check-in includes last night's HRV, so most people only need check-in reminders. Reminders are skipped once done. Medication and creatine reminders have a Taken button, and today's doses also show on your Lock Screen. Add the HRV widget from your Home Screen: hold an empty spot → Edit → Add Widget → WorkoutApp.")
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.label).tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Units") {
                    Picker("Weight", selection: $settings.weightUnit) {
                        ForEach(WeightUnit.allCases) { unit in
                            Text(unit.rawValue).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Coach", selection: $settings.coachMode) {
                        ForEach(CoachMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    if settings.coachMode == .onDevice, let message = OnDeviceCoach.availabilityMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.recoveryModerateText)
                    }
                    if settings.coachMode == .cloud {
                        DisclosureGroup("Advanced: server") {
                            TextField("Supabase URL (https://xyz.supabase.co)", text: $settings.supabaseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            SecureField("Supabase anon key", text: $settings.supabaseAnonKey)
                        }
                    }
                } header: {
                    Text("AI coach")
                } footer: {
                    Text("On-device is free and private. Claude gives deeper answers and runs through the app's secure server.")
                }

                Section {
                    Button("Ask for Health access") {
                        Task { try? await health?.requestAuthorization() }
                    }
                    if let healthURL = URL(string: "x-apple-health://") {
                        Link("Open the Health app", destination: healthURL)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("iOS only shows the permission screen once. To change access later, open the Health app → your profile picture → Apps → WorkoutApp, and tap Turn On All.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Text("Exercise library: free-exercise-db (public domain). Muscle map outlines: react-body-highlighter (MIT, © 2020 GV79). Weather data by Open-Meteo.com (CC BY 4.0). Drug labels: openFDA. Scores are estimates for training guidance, not medical advice.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingGym) { MyGymView() }
            .sheet(isPresented: $showingMeds) { MedicationsView() }
            .sheet(isPresented: $showingLocation) { LocationPicker() }
            .sheet(isPresented: $showingGoals) { GoalsView() }
            .sheet(isPresented: $showingRPEGuide) { RPEGuideView() }
        }
    }
}
