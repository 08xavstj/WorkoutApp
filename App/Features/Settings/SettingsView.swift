import SwiftUI
import AppCore

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State private var showingGym = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Stepper("Age: \(settings.age)", value: $settings.age, in: 13...100)
                    Picker("Sex", selection: $settings.sex) {
                        Text("Male").tag(BiologicalSex.male)
                        Text("Female").tag(BiologicalSex.female)
                    }
                    Stepper(
                        settings.maxHeartRate == 0 ? "Max heart rate: estimate" : "Max heart rate: \(settings.maxHeartRate)",
                        value: $settings.maxHeartRate,
                        in: 0...230,
                        step: 1
                    )
                    LabeledContent("Height (if not in Health)") {
                        TextField("cm", value: $settings.heightCm, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("cm").foregroundStyle(Theme.secondaryText)
                    }
                    LabeledContent("Weight (if not in Health)") {
                        TextField("kg", value: $settings.weightKg, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kg").foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Age and sex set your heart-rate zones and calorie estimate. Leave max heart rate on \"estimate\" unless you've measured it. Height and weight from Apple Health are used first.")
                }

                Section {
                    Button {
                        showingGym = true
                    } label: {
                        LabeledContent("My Gym", value: gym.isConfigured ? gym.profile.name : "Not set up")
                    }
                } header: {
                    Text("Trainer")
                } footer: {
                    Text("Your equipment, plates and dumbbells, so planned weights are ones you can load.")
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
                            .foregroundStyle(Theme.recoveryModerate)
                    }
                    if settings.coachMode == .cloud {
                        TextField("Supabase URL (https://xyz.supabase.co)", text: $settings.supabaseURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        SecureField("Supabase anon key", text: $settings.supabaseAnonKey)
                    }
                } header: {
                    Text("AI coach")
                } footer: {
                    Text("On-device is free and private. Claude gives deeper answers and runs through your own Supabase server, so your Anthropic key never ships in the app. See README.")
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
                    Text("Exercise library: free-exercise-db (public domain). Scores are estimates for training guidance, not medical advice.")
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
        }
    }
}
