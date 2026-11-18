import AppCore
import MapKit
import SwiftUI

/// Settings › Data & privacy: the row that opens Route privacy.
struct RoutePrivacySettingsSection: View {
    @State private var store = RoutePrivacyStore.shared

    var body: some View {
        Section {
            NavigationLink {
                RoutePrivacyView()
            } label: {
                LabeledContent("Route privacy", value: summary)
            }
        } footer: {
            Text("Hides your home and other places on route images and GPX files you share. The map in the app still shows you the whole route.")
        }
    }

    private var summary: String {
        switch store.zones.count {
        case 0: store.hideEndpoints ? "Start and end hidden" : "Off"
        case 1: "1 place"
        default: "\(store.zones.count) places"
        }
    }
}

/// Saved places and the start/end switch. Evidence: endpoint privacy zones
/// leaked the hidden place for 84% (Hassan 2018) and up to 85% (Dhondt 2022)
/// of users, mostly from exact distances (`RoutePrivacy`).
struct RoutePrivacyView: View {
    @State private var store = RoutePrivacyStore.shared

    var body: some View {
        Form {
            Section {
                Toggle("Hide start and end", isOn: Binding(get: { store.hideEndpoints }, set: { store.hideEndpoints = $0 }))
            } footer: {
                Text("Cuts 250–400 m off both ends of every shared route, a different length for each workout, so the cut can't be measured back to your door.")
            }
            Section {
                ForEach(store.zones) { zone in
                    NavigationLink {
                        PrivacyZoneEditor(zone: zone, isNew: false)
                    } label: {
                        LabeledContent(zone.name.isEmpty ? "Place" : zone.name, value: privacyRadiusText(zone.radiusMeters))
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.zones[$0] }
                    for zone in removed { store.remove(zone) }
                }
                if store.canAddZone {
                    NavigationLink {
                        PrivacyZoneEditor(zone: PrivacyZone(name: store.zones.isEmpty ? "Home" : "", latitude: 0, longitude: 0), isNew: true)
                    } label: {
                        Label("Add a place", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Private places")
            } footer: {
                Text("On shared routes, the part within the radius is hidden, plus 50–200 m more along the route, chosen per workout. Distances on route images are rounded to 0.1 km or mi. Studies of fitness apps found that hiding a fixed circle and printing exact distances let others find the hidden home for most users (Hassan 2018; Dhondt 2022). This lowers that risk; it can't remove it, so turn off \"Show map\" when you share a route you'd rather not show at all.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Route privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "500 m" or "0.3 mi" where distances are in miles.
func privacyRadiusText(_ meters: Double) -> String {
    let system = Locale.current.measurementSystem
    if system == .us || system == .uk {
        return "\((meters / CardioSummary.metersPerMile).formatted(.number.precision(.fractionLength(1)))) mi"
    }
    return "\(Int(meters)) m"
}

/// One place: a name, a pin (tap the map or use the current location) and a radius.
private struct PrivacyZoneEditor: View {
    @State var zone: PrivacyZone
    let isNew: Bool

    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var store = RoutePrivacyStore.shared
    @State private var finder = LocationFinder()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hasPin = false

    private var pin: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Home", text: $zone.name)
                    .textInputAutocapitalization(.words)
            }
            Section {
                MapReader { proxy in
                    Map(position: $position) {
                        if hasPin {
                            MapCircle(center: pin, radius: zone.radiusMeters)
                                .foregroundStyle(Theme.oxygen.opacity(0.18))
                                .stroke(Theme.oxygen, lineWidth: 2)
                            Marker(zone.name.isEmpty ? "Place" : zone.name, systemImage: "house.fill", coordinate: pin)
                                .tint(Theme.oxygen)
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .onTapGesture { location in
                        guard let coordinate = proxy.convert(location, from: .local) else { return }
                        drop(coordinate, recenter: false)
                    }
                }
                .frame(height: 280)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel(hasPin ? "Map with the place's pin and radius" : "Map. Tap to drop a pin.")
                Button {
                    Task {
                        if let coordinate = await finder.locate() { drop(coordinate, recenter: true) }
                    }
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
            } footer: {
                Text(hasPin ? "Tap the map to move the pin." : "Tap the map to drop a pin, or use where you are now.")
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Radius", value: privacyRadiusText(zone.radiusMeters))
                    Slider(value: $zone.radiusMeters, in: RoutePrivacy.radiusRange, step: RoutePrivacy.radiusStep)
                        .accessibilityValue(privacyRadiusText(zone.radiusMeters))
                }
            } footer: {
                // Spec B2 (200 m–1 km, 500 m default); bigger zones were harder to attack (Dhondt 2022).
                Text("200 m to 1 km. Bigger hides more: in one study, larger zones were harder to work back to the address.")
            }
            if !isNew {
                Section {
                    Button("Remove place", role: .destructive) {
                        store.remove(zone)
                        dismiss()
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(isNew ? "New place" : (zone.name.isEmpty ? "Place" : zone.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.save(PrivacyZone(id: zone.id, name: zone.name.trimmingCharacters(in: .whitespaces),
                                           latitude: zone.latitude, longitude: zone.longitude, radiusMeters: zone.radiusMeters))
                    dismiss()
                }
                .disabled(!hasPin)
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        if !isNew {
            hasPin = true
            position = .region(MKCoordinateRegion(center: pin, latitudinalMeters: 3000, longitudinalMeters: 3000))
        } else if settings.hasLocation {
            // The city from Settings, until the owner picks the spot.
            let city = CLLocationCoordinate2D(latitude: settings.latitude, longitude: settings.longitude)
            position = .region(MKCoordinateRegion(center: city, latitudinalMeters: 8000, longitudinalMeters: 8000))
        }
    }

    private func drop(_ coordinate: CLLocationCoordinate2D, recenter: Bool) {
        zone.latitude = coordinate.latitude
        zone.longitude = coordinate.longitude
        hasPin = true
        if recenter {
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
        }
    }
}
