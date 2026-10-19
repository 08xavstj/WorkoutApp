import SwiftUI

/// Pick where you live: search for a city or use your current location once.
struct LocationPicker: View {
    @Environment(UserSettings.self) private var settings
    @Environment(ConditionsModel.self) private var conditions
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Place] = []
    @State private var finder = LocationFinder()
    @State private var searchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await useCurrentLocation() }
                    } label: {
                        HStack {
                            Label("Use my current location", systemImage: "location.fill")
                            if finder.isLocating {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    if let problem = finder.problem {
                        Text(problem).font(.footnote).foregroundStyle(Theme.recoveryModerateText)
                    }
                }
                Section {
                    ForEach(results) { place in
                        Button {
                            choose(place.label, latitude: place.latitude, longitude: place.longitude)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(Theme.primaryText)
                                if !place.region.isEmpty {
                                    Text(place.region).font(.caption).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    if let searchError {
                        Text(searchError).font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                } header: {
                    if !results.isEmpty { Text("Results") }
                }
                if settings.hasLocation {
                    Section {
                        Button("Remove location", role: .destructive) {
                            settings.placeName = ""
                            settings.latitude = 0
                            settings.longitude = 0
                            Task { await conditions.refresh(settings: settings, force: true) }
                            dismiss()
                        }
                    } footer: {
                        Text("Current: \(settings.placeName)")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for your city")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                do {
                    results = try await WeatherClient.searchPlaces(query)
                    searchError = results.isEmpty && query.count >= 2 ? "No places found." : nil
                } catch {
                    searchError = "Search isn't available right now."
                }
            }
            .navigationTitle("Where you live")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func useCurrentLocation() async {
        guard let coordinate = await finder.locate() else { return }
        // Round to about 1 km: plenty for weather, and less precise to store.
        let latitude = (coordinate.latitude * 100).rounded() / 100
        let longitude = (coordinate.longitude * 100).rounded() / 100
        choose("Current location", latitude: latitude, longitude: longitude)
    }

    private func choose(_ name: String, latitude: Double, longitude: Double) {
        settings.placeName = name
        settings.latitude = latitude
        settings.longitude = longitude
        Task { await conditions.refresh(settings: settings, force: true) }
        dismiss()
    }
}
