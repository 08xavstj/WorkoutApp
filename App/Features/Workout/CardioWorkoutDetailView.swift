import AppCore
import Charts
import MapKit
import SwiftUI

/// One cardio workout or sport from Apple Health (Tensile's Watch cardio
/// mode, Apple's Workout app, Garmin...): the route on a map coloured by
/// speed, heart rate or elevation, then the totals, heart rate (average,
/// peak, zones, one-minute recovery), the cardio fitness estimate it
/// produced, and splits.
///
/// The map tiles come from Apple Maps, which loads the area shown; the route
/// itself stays in Apple Health on the phone.
struct CardioWorkoutDetailView: View {
    let workoutID: UUID
    let title: String

    @Environment(\.healthClient) private var health
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings

    @State private var detail: CardioWorkoutDetail?
    @State private var route: CardioRoute?
    @State private var heart: CardioHeartSummary?
    @State private var zones: HeartRateZoneScheme?
    @State private var metric: RouteMetric = .speed
    @State private var loaded = false

    /// Miles and feet where distances are in miles (the US and the UK), as on the Watch.
    private var miles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }

    private var unitMeters: Double { miles ? CardioSummary.metersPerMile : 1000 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    if let route, route.points.count >= 2 {
                        mapCard(route)
                    }
                    totalsCard(detail)
                    if let route, route.points.count >= 2 {
                        RouteChartsCard(route: route, showsPace: detail.showsPace)
                    }
                    heartCard(detail)
                    IntervalBoutsCard(workoutID: detail.uuid, heartRate: detail.heartRate, route: route, showsPace: detail.showsPace,
                                      hasSplits: route.map { !$0.splits(unitMeters: unitMeters).isEmpty } ?? false)
                    if let vo2 = detail.vo2Max {
                        fitnessCard(vo2, detail: detail)
                    }
                    if let route, !route.splits(unitMeters: unitMeters).isEmpty {
                        splitsCard(route, showsPace: detail.showsPace)
                    }
                    if let route, route.points.count >= 2 {
                        CardioBestsCard(workoutID: detail.uuid, date: detail.start, kind: detail.kind, route: route)
                    }
                    Text(footnote(detail))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else if loaded {
                    ContentUnavailableView(
                        "Workout not found",
                        systemImage: "figure.run",
                        description: Text("It may have been deleted from Apple Health, or Tensile can't read it. Check Health access in Settings.")
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(detail?.name ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        // Share image and GPX, privacy-trimmed (CardioShareSheet.swift).
        .cardioShareToolbar(detail: detail, route: route, heart: heart, zones: zones, miles: miles)
    }

    private func load() async {
        defer { loaded = true }
        guard let health, let read = try? await health.cardioWorkoutDetail(id: workoutID) as CardioWorkoutDetail?? else { return }
        // Read fine but gone from Health: forget its best efforts too.
        guard let found = read else { return CardioBestsStore.remove(workoutID) }
        let profile = metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
        let scheme = await ZonePreferences.current(profile: profile, health: health).scheme
        let readings = found.heartRate.map { (date: $0.date, bpm: $0.bpm) }
        // Thousands of fixes: worked out off the main thread.
        let points = found.route
        let path = await Task.detached(priority: .userInitiated) {
            CardioRoute(points: points, heartRate: readings)
        }.value
        zones = scheme
        route = path
        heart = CardioHeartSummary(readings: readings, start: found.start, end: found.end, zones: scheme)
        detail = found
        // A sport with no speed to speak of opens on heart rate.
        if path.range(for: .speed) == nil || found.activity?.movement == .stationary { metric = .heartRate }
    }

    /// Whose estimate it is, and Apple Watch's measured bias only when it
    /// came from one (`VO2Source.appleWatchAccuracy`, Lambe 2025).
    private func vo2Note(_ detail: CardioWorkoutDetail) -> String {
        let whose = detail.vo2IsAppleWatch ? "Apple Watch's" : (detail.vo2SourceName.map { "\($0)'s" } ?? "Your watch's")
        var text = "\(whose) estimate from this workout (ml/kg/min)."
        if detail.vo2IsAppleWatch { text += " " + VO2Source.appleWatchAccuracy }
        return text + " Higher cardio fitness goes with longer life (Mandsager 2018); the trend is under Fitness › Cardio fitness."
    }

    // MARK: Map

    private func mapCard(_ route: CardioRoute) -> some View {
        let available = RouteMetric.allCases.filter { route.range(for: $0) != nil }
        return VStack(alignment: .leading, spacing: 12) {
            RouteMapView(route: route, metric: metric, zones: zones)
                .frame(height: 320)
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityLabel(mapLabel(route))
            if available.count > 1 {
                Picker("Colour the route by", selection: $metric) {
                    ForEach(available) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            legend(route)
        }
        .card()
    }

    private func mapLabel(_ route: CardioRoute) -> String {
        let distance = CardioSummary.distanceText(meters: route.distanceMeters, miles: miles)
        return "Map of the route, \(distance), coloured by \(metric.title.lowercased())."
    }

    @ViewBuilder
    private func legend(_ route: CardioRoute) -> some View {
        if metric == .heartRate, zones != nil {
            HStack(spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.zoneColors[index]).frame(width: 8, height: 8)
                        Text("Z\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Colours show heart-rate zones 1 to 5")
        } else if let range = route.range(for: metric) {
            HStack(spacing: 8) {
                Text(valueText(range.lowerBound))
                Capsule()
                    .fill(LinearGradient(colors: Theme.zoneColors, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                Text(valueText(range.upperBound))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.secondaryText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metric.title) from \(valueText(range.lowerBound)) to \(valueText(range.upperBound))")
        }
    }

    /// A value of the map's metric in display units.
    private func valueText(_ value: Double) -> String {
        switch metric {
        case .speed: CardioSummary.speedText(metersPerSecond: value, miles: miles)
        case .heartRate: "\(whole(value)) bpm"
        case .elevation: CardioSummary.elevationText(meters: value, feet: miles)
        }
    }

    // MARK: Totals

    private func totalsCard(_ detail: CardioWorkoutDetail) -> some View {
        let distance = detail.distanceMeters ?? route.flatMap { $0.distanceMeters > 0 ? $0.distanceMeters : nil }
        let climb = detail.elevationAscended ?? route?.elevation?.gain
        var tiles: [(String, String)] = [("Time", workoutTime(detail.activeSeconds))]
        if let distance, distance >= CardioSummary.minimumDistanceForPace {
            tiles.append(("Distance", CardioSummary.distanceText(meters: distance, miles: miles)))
            if detail.showsPace, let pace = CardioSummary.pace(seconds: detail.activeSeconds, meters: distance, miles: miles) {
                tiles.append(("Avg pace", CardioSummary.paceText(pace, miles: miles)))
            } else if let speed = CardioSummary.speed(seconds: detail.activeSeconds, meters: distance, miles: miles) {
                tiles.append(("Avg speed", CardioSummary.speedText(speed, miles: miles)))
            }
        }
        if let top = route?.maximumSpeed, top > 0 {
            if detail.showsPace {
                tiles.append(("Best pace", CardioSummary.paceText(unitMeters / top, miles: miles)))
            } else {
                tiles.append(("Top speed", CardioSummary.speedText(metersPerSecond: top, miles: miles)))
            }
        }
        if let climb {
            tiles.append(("Climb", CardioSummary.elevationText(meters: climb, feet: miles)))
        }
        if let kcal = detail.activeKcal, kcal > 0 {
            tiles.append(("Active energy", "\(whole(kcal)) kcal"))
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text("\(detail.start.formatted(date: .abbreviated, time: .shortened))\(detail.sourceName.map { " · \($0)" } ?? "")")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            StatGrid(tiles: tiles)
        }
        .card()
    }

    private func workoutTime(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    // MARK: Heart rate

    @ViewBuilder
    private func heartCard(_ detail: CardioWorkoutDetail) -> some View {
        if let heart, heart.averageBpm != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Heart rate")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                StatGrid(tiles: heartTiles(heart))
                HeartRateChart(readings: detail.heartRate, start: detail.start, end: detail.end)
                    .frame(height: 140)
                WorkoutZonesRow(minutes: heart.zoneMinutes, scheme: zones)
                recoveryText(heart)
            }
            .card()
        } else {
            Text("No heart rate was recorded with this workout.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .card()
        }
    }

    private func heartTiles(_ heart: CardioHeartSummary) -> [(String, String)] {
        var tiles: [(String, String)] = []
        if let average = heart.averageBpm { tiles.append(("Average", "\(whole(average)) bpm")) }
        if let peak = heart.maximumBpm {
            tiles.append(("Peak", "\(whole(peak)) bpm"))
            // Share of the maximum the zones use (measured, typed, or estimated from age).
            if let maximum = metrics.heartRateProfile?.maxHeartRate, maximum > 0 {
                tiles.append(("Peak of your max", "\(whole(100 * peak / maximum))%"))
            }
        }
        if let lowest = heart.minimumBpm { tiles.append(("Lowest", "\(whole(lowest)) bpm")) }
        return tiles
    }

    /// The fall in the first minute after stopping, with what it can and can't say.
    @ViewBuilder
    private func recoveryText(_ heart: CardioHeartSummary) -> some View {
        if let drop = heart.recoveryDrop {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recovery: down \(whole(drop)) bpm in the first minute")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                // Cole et al., NEJM 1999 (`CardioHeartSummary.lowRecoveryDrop`).
                Text(drop <= CardioHeartSummary.lowRecoveryDrop
                     ? "A drop of 12 bpm or less after a treadmill test with a walking cool-down was linked with higher risk (Cole 1999). After a workout it depends on how you stopped, so watch the trend over several workouts, not one number."
                     : "A faster drop is a sign of good heart fitness (Cole 1999). It depends on how you stopped, so compare workouts that ended the same way.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Cardio fitness

    private func fitnessCard(_ vo2: Double, detail: CardioWorkoutDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cardio fitness")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(vo2.formatted(.number.precision(.fractionLength(1))))
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                Text("VO₂ max")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            // Mandsager 2018 (JAMA Netw Open): fitness is among the strongest predictors of survival.
            Text(vo2Note(detail))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    // MARK: Splits

    private func splitsCard(_ route: CardioRoute, showsPace: Bool) -> some View {
        let splits = route.splits(unitMeters: unitMeters)
        let fastest = splits.filter { !$0.isPartial }.max { $0.speed < $1.speed }?.index
        return VStack(alignment: .leading, spacing: 8) {
            Text("Splits")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(miles ? "Mile" : "Km")
                    Text(showsPace ? "Pace" : "Speed")
                    Text("HR")
                    Text(miles ? "Elev ft" : "Elev m")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                ForEach(splits) { split in
                    GridRow {
                        Text(split.isPartial ? CardioSummary.distanceText(meters: split.meters, miles: miles) : "\(split.index)")
                        Text(splitSpeed(split, showsPace: showsPace))
                            .fontWeight(split.index == fastest ? .bold : .regular)
                        Text(split.averageBpm.map { "\(whole($0))" } ?? "–")
                        Text(split.elevationChange.map { signed($0 * (miles ? CardioSummary.feetPerMeter : 1)) } ?? "–")
                    }
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .card()
    }

    private func splitSpeed(_ split: CardioRoute.Split, showsPace: Bool) -> String {
        guard split.speed > 0 else { return "–" }
        return showsPace
            ? CardioSummary.paceText(unitMeters / split.speed, miles: miles)
            : CardioSummary.speedText(metersPerSecond: split.speed, miles: miles)
    }

    private func signed(_ value: Double) -> String {
        let rounded = whole(value)
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func footnote(_ detail: CardioWorkoutDetail) -> String {
        var parts: [String] = []
        if route.map({ $0.points.count < 2 }) ?? true {
            parts.append("No route: the workout was indoors or recorded without GPS.")
        } else {
            parts.append("Speed is averaged over \(whole(CardioRoute.speedWindowSeconds)) seconds so GPS jitter doesn't show as sprints. The map tiles come from Apple Maps; your route stays in Apple Health.")
        }
        if detail.activity?.takesTarget == false {
            parts.append("Sports have no heart-rate target: in stop-and-go play heart rate follows the game.")
        }
        return parts.joined(separator: " ")
    }
}

/// Label-over-value tiles, two to a row.
private struct StatGrid: View {
    let tiles: [(String, String)]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.0)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Text(tile.1)
                        .font(.title3.weight(.semibold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// The route drawn in coloured stretches (`CardioRoute.stretches`), with a
/// start and finish marker.
private struct RouteMapView: View {
    let route: CardioRoute
    let metric: RouteMetric
    let zones: HeartRateZoneScheme?

    private var coordinates: [CLLocationCoordinate2D] {
        route.points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// The route's bounds with a margin, so the line isn't drawn on the edge.
    private var region: MKMapRect {
        let rects = coordinates.map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
        let bounds = rects.dropFirst().reduce(rects.first ?? .null) { $0.union($1) }
        let margin = max(bounds.width, bounds.height) * 0.15 + 200
        return bounds.insetBy(dx: -margin, dy: -margin)
    }

    var body: some View {
        let points = coordinates
        let stretches = route.stretches(for: metric, zones: metric == .heartRate ? zones : nil, minimumPoints: max(5, route.points.count / 200))
        Map(initialPosition: .rect(region), interactionModes: [.pan, .zoom]) {
            ForEach(Array(stretches.enumerated()), id: \.offset) { _, stretch in
                MapPolyline(coordinates: Array(points[stretch.range]))
                    .stroke(color(stretch.level), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation("Start", coordinate: first) {
                    Circle().fill(.green).stroke(.white, lineWidth: 2).frame(width: 14, height: 14)
                }
            }
            if let last = points.last, points.count > 1 {
                Annotation("Finish", coordinate: last) {
                    Image(systemName: "flag.checkered")
                        .font(.caption.weight(.bold))
                        .padding(4)
                        .background(.white, in: .circle)
                        .foregroundStyle(.black)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
    }

    private func color(_ level: Int?) -> Color {
        guard let level, Theme.zoneColors.indices.contains(level) else { return Theme.neutralIcon }
        return Theme.zoneColors[level]
    }
}

/// Heart rate through the workout, with the minute after it (the recovery)
/// shaded.
private struct HeartRateChart: View {
    let readings: [HeartRateSample]
    let start: Date
    let end: Date

    var body: some View {
        let shown = readings.filter { $0.date >= start && $0.date <= end.addingTimeInterval(120) }
        Chart {
            RectangleMark(xStart: .value("End", end), xEnd: .value("After", end.addingTimeInterval(120)))
                .foregroundStyle(Theme.track.opacity(0.5))
            ForEach(Array(shown.enumerated()), id: \.offset) { _, reading in
                LineMark(x: .value("Time", reading.date), y: .value("Heart rate", reading.bpm))
                    .foregroundStyle(Theme.heart)
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .accessibilityLabel("Heart rate over the workout")
    }
}
