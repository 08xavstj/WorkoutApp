import AppCore
import SwiftUI

extension View {
    /// The cardio detail's Share button and its sheet (share image and GPX).
    /// Hidden until the workout has loaded.
    func cardioShareToolbar(detail: CardioWorkoutDetail?, route: CardioRoute?, heart: CardioHeartSummary?,
                            zones: HeartRateZoneScheme?, miles: Bool) -> some View {
        modifier(CardioShareToolbar(detail: detail, route: route, heart: heart, zones: zones, miles: miles))
    }
}

private struct CardioShareToolbar: ViewModifier {
    let detail: CardioWorkoutDetail?
    let route: CardioRoute?
    let heart: CardioHeartSummary?
    let zones: HeartRateZoneScheme?
    let miles: Bool
    @State private var sharing = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if detail != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Share", systemImage: "square.and.arrow.up") { sharing = true }
                    }
                }
            }
            .sheet(isPresented: $sharing) {
                if let detail {
                    CardioShareSheet(detail: detail, route: route, heart: heart, zones: zones, miles: miles)
                }
            }
    }
}

/// Preview the share image with a few switches, then share it; or export the
/// route as GPX. Route privacy (`RoutePrivacyStore`) applies to the image
/// always and to the GPX unless "Full route" is on. Heart rate is on by
/// default; calories are off, and shown as a range when on (spec §5a).
struct CardioShareSheet: View {
    let detail: CardioWorkoutDetail
    let route: CardioRoute?
    let heart: CardioHeartSummary?
    let zones: HeartRateZoneScheme?
    let miles: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle.light
    @State private var showMap = true
    @State private var showHeartRate = true
    @State private var showCalories = false
    /// The last image made, and the switches it was made for: it is shown
    /// and shared only while they still match, so turning a switch off never
    /// leaves the old image (with heart rate, say) ready to share.
    @State private var image: RenderedShareImage?
    @State private var renderedFor: Options?
    /// Map snapshots already made in this sheet, so flipping a switch doesn't
    /// ask MapKit for the same map again.
    @State private var snapshots: [SnapshotKey: UIImage] = [:]
    @State private var fullRouteFile = false
    @State private var file: ExportedFile?
    @State private var exporting = false
    @State private var problem: String?

    private var store: RoutePrivacyStore { RoutePrivacyStore.shared }
    private var hasRoute: Bool { (route?.points.count ?? 0) >= 2 }

    private struct Options: Equatable {
        var style: ShareCardStyle
        var showMap: Bool
        var showHeartRate: Bool
        var showCalories: Bool
    }

    /// What a snapshot depends on: light or dark map, and what colours the line.
    private struct SnapshotKey: Hashable {
        var dark: Bool
        var metric: RouteMetric
    }

    private var options: Options {
        Options(style: style, showMap: showMap, showHeartRate: showHeartRate, showCalories: showCalories)
    }

    private var currentImage: RenderedShareImage? {
        renderedFor == options ? image : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    ShareImagePreview(image: currentImage, style: style, subject: detail.name)
                        .listRowBackground(Color.clear)
                }
                Section {
                    if hasRoute {
                        Toggle("Show map", isOn: $showMap)
                    }
                    Toggle("Show heart rate", isOn: $showHeartRate)
                    if detail.activeKcal != nil {
                        Toggle("Show calories", isOn: $showCalories)
                    }
                } footer: {
                    Text(footer)
                }
                if hasRoute {
                    gpxSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: options) {
                await render(options)
            }
            .sheet(item: $file, onDismiss: DataExport.removeFiles) { ExportReadySheet(file: $0) }
        }
    }

    private var footer: String {
        var text = "The image is made on this iPhone and has no location data in it."
        if hasRoute {
            text += " The route near your private places, and the start and end if that's on, is left off the map (Settings › Data & privacy › Route privacy); when anything is left off, the distance is rounded and the start time isn't shown."
        }
        if showCalories {
            text += " Wrist calorie estimates were off by 20% or more in validation studies (Shcherbina 2017), so they show as a range."
        }
        return text
    }

    private var gpxSection: some View {
        Section {
            Toggle("Full route (not trimmed)", isOn: $fullRouteFile)
            if fullRouteFile {
                Label("The file will show where you started and finished, including near home.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
            Button("Export route (GPX)", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                Task { await exportGPX() }
            }
            .disabled(exporting)
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.recoveryModerateText)
            }
        } header: {
            Text("Route file")
        } footer: {
            Text("GPX 1.1 with time, elevation and heart rate, for Strava, Garmin Connect or a route planner. Trimmed like the image unless you turn on Full route.")
        }
    }

    // MARK: Rendering

    private func render(_ options: Options) async {
        let privacy = route.map { store.trim($0, workoutID: detail.uuid) }
        let trimmed = privacy?.isTrimmed ?? false
        let content = CardioShareContent(detail: detail, route: route, heart: heart, miles: miles, trimmed: trimmed,
                                         showHeartRate: options.showHeartRate, showCalories: options.showCalories)
        var map: UIImage?
        var line: [[RouteProjection.Point]] = []
        var hidden = false
        var mapUnavailable = false
        if options.showMap, let route, let privacy, route.points.count >= 2 {
            hidden = privacy.hidesEverything
            if !hidden {
                if options.style != .transparent {
                    map = await snapshot(route: route, privacy: privacy, options: options)
                    guard !Task.isCancelled else { return }
                    mapUnavailable = map == nil
                }
                // The overlay style, or no map (offline): the trimmed line on its own.
                if map == nil {
                    line = RouteProjection.normalized(RoutePrivacy.segments(route.points, privacy))
                }
            }
        }
        guard !Task.isCancelled else { return }
        let card = CardioShareCard(content: content, style: options.style, map: map, line: line, routeHidden: hidden,
                                   mapUnavailable: mapUnavailable)
        let rendered = ShareRenderer.image(card, size: ShareRenderer.cardSize, style: options.style)
        image = rendered
        renderedFor = rendered == nil ? nil : options
    }

    /// The map with the visible route on it, made once per key. The line is
    /// coloured by speed when there is one; by heart-rate zone only while
    /// heart rate is shown, else by elevation, so the colours can't give
    /// away heart rate the user turned off.
    private func snapshot(route: CardioRoute, privacy: RoutePrivacy.Result, options: Options) async -> UIImage? {
        let moves = detail.activity?.movement != .stationary
        let metric: RouteMetric = route.range(for: .speed) != nil && moves ? .speed
            : options.showHeartRate ? .heartRate : .elevation
        let key = SnapshotKey(dark: options.style == .dark, metric: metric)
        if let cached = snapshots[key] { return cached }
        let lines = RouteSnapshot.lines(route: route, privacy: privacy, metric: metric, zones: zones, dark: key.dark)
        let data = await RouteSnapshot.image(lines: lines, size: CGSize(width: ShareRenderer.cardSize.width - 40, height: 140),
                                             dark: key.dark)
        // Not cached when it failed (offline), so the next switch tries again.
        guard let map = data.flatMap(UIImage.init(data:)) else { return nil }
        snapshots[key] = map
        return map
    }

    private func exportGPX() async {
        guard let route, !exporting else { return }
        problem = nil
        exporting = true
        defer { exporting = false }
        let privacy = store.trim(route, workoutID: detail.uuid, full: fullRouteFile)
        do {
            // Built off the main actor: a long route has thousands of points.
            let url = try await DataExport.gpxFile(route: route, privacy: privacy, name: detail.name, type: gpxType, date: detail.start)
            file = ExportedFile(url: url, title: "Route file")
        } catch {
            problem = privacy.hidesEverything
                ? "Every part of this route is near a private place, so there's nothing to export. Turn on Full route to export it anyway."
                : error.localizedDescription
        }
    }

    /// Plain activity words most route tools read.
    private var gpxType: String? {
        switch detail.name {
        case "Run": "running"
        case "Walk": "walking"
        case "Ride": "cycling"
        case "Hike": "hiking"
        default: detail.activity.map { $0.title.lowercased() }
        }
    }
}
