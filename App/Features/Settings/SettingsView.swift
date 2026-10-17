import SwiftUI
import AppCore

struct SettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health

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
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Age and sex set your heart-rate zones. Leave max heart rate on \"estimate\" unless you've measured it.")
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

                Section("Apple Health") {
                    Button("Review Health access") {
                        Task { try? await health?.requestAuthorization() }
                    }
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
        }
    }
}
