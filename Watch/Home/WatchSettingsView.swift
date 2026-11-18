import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// The Watch's own settings: which metric pages each activity shows, the
/// taps, and distance units. Weight units, rest lengths and zones come from
/// the iPhone.
struct WatchSettingsView: View {
    @AppStorage(WatchPreferences.restWarningKey) private var restWarning = true
    @AppStorage(WatchPreferences.splitTapsKey) private var splitTaps = true
    @AppStorage(WatchPreferences.distanceUnitKey) private var distanceUnit = "auto"

    var body: some View {
        List {
            Section {
                ForEach(CardioActivity.Category.allCases) { category in
                    NavigationLink(category.title) {
                        List {
                            ForEach(CardioActivity.all(in: category)) { activity in
                                NavigationLink {
                                    CardioPagesEditor(activity: activity)
                                } label: {
                                    Label(activity.title, systemImage: activity.systemImage)
                                }
                            }
                        }
                        .navigationTitle(category.title)
                    }
                }
            } header: {
                Text("Workout pages")
            } footer: {
                Text("Choose the pages each activity shows and their order.")
            }
            Section("Taps") {
                Toggle("10 s before rest ends", isOn: $restWarning)
                Toggle("At each split and lap", isOn: $splitTaps)
            }
            Section("Distance") {
                Picker("Units", selection: $distanceUnit) {
                    Text("Automatic").tag("auto")
                    Text("Kilometres").tag("km")
                    Text("Miles").tag("mi")
                }
            }
            Section {
                Text("Weight units, rest times and heart-rate zones come from Tensile on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
    }
}
