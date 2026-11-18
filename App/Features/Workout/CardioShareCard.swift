import AppCore
import SwiftUI

/// What the cardio share card shows, worked out once per set of switches.
/// Distance is rounded and pace taken from the rounded distance whenever the
/// route was trimmed (spec rule 4; `ShareCards.shownDistanceMeters`), and the
/// date is shown without the start time.
struct CardioShareContent {
    var title: String
    var date: Date
    var stats: [(String, String)]
    var zoneMinutes: [Double]
    var splits: [(String, String)]
    var footnote: String

    init(detail: CardioWorkoutDetail, route: CardioRoute?, heart: CardioHeartSummary?, miles: Bool,
         trimmed: Bool, showHeartRate: Bool, showCalories: Bool) {
        title = detail.name
        date = detail.start
        let unitMeters = miles ? CardioSummary.metersPerMile : 1000
        var stats: [(String, String)] = [("Time", Self.time(detail.activeSeconds))]
        let measured = detail.distanceMeters ?? route.flatMap { $0.distanceMeters > 0 ? $0.distanceMeters : nil }
        if let measured, measured >= CardioSummary.minimumDistanceForPace {
            stats.append(("Distance", ShareCards.distanceText(meters: measured, miles: miles, trimmed: trimmed)))
            let shown = ShareCards.shownDistanceMeters(measured, miles: miles, trimmed: trimmed)
            if detail.showsPace, let pace = CardioSummary.pace(seconds: detail.activeSeconds, meters: shown, miles: miles) {
                stats.append(("Avg pace", CardioSummary.paceText(pace, miles: miles)))
            } else if let speed = CardioSummary.speed(seconds: detail.activeSeconds, meters: shown, miles: miles) {
                stats.append(("Avg speed", CardioSummary.speedText(speed, miles: miles)))
            }
        }
        if let climb = detail.elevationAscended ?? route?.elevation?.gain, climb >= 1 {
            stats.append(("Climb", CardioSummary.elevationText(meters: climb, feet: miles)))
        }
        if showHeartRate, let average = heart?.averageBpm {
            stats.append(("Avg HR", "\(whole(average)) bpm"))
        }
        var notes: [String] = []
        if showCalories, let calories = ShareCards.calorieText(detail.activeKcal) {
            stats.append(("Energy", calories))
            notes.append("Calories are a wrist estimate, ±20% or more.")
        }
        self.stats = stats
        zoneMinutes = showHeartRate ? (heart?.zoneMinutes ?? []) : []
        let pieces = route.map { ShareCards.topSplits($0.splits(unitMeters: unitMeters)) } ?? []
        splits = pieces.map { split in
            let label = "\(miles ? "Mi" : "Km") \(split.index)"
            let value = detail.showsPace
                ? CardioSummary.paceText(unitMeters / split.speed, miles: miles)
                : CardioSummary.speedText(metersPerSecond: split.speed, miles: miles)
            return (label, value)
        }
        if trimmed { notes.insert("Route trimmed near private places; distance rounded.", at: 0) }
        footnote = notes.joined(separator: " ")
    }

    static func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded()).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}

/// The cardio share image (spec B1): map or route line, activity and date,
/// the main numbers, a heart-rate zone bar and the fastest splits.
struct CardioShareCard: View {
    let content: CardioShareContent
    let style: ShareCardStyle
    /// The map snapshot (light and dark cards) or nil.
    let map: UIImage?
    /// The route line on its own (overlay style), or empty.
    let line: [[RouteProjection.Point]]
    /// A route existed but every part of it was private.
    var routeHidden = false
    /// The map snapshot couldn't be made (offline): `line` is drawn alone.
    var mapUnavailable = false

    var body: some View {
        ShareCardFrame(style: style, wash: [Theme.Wash.sky, Theme.Wash.mint], footnote: content.footnote.isEmpty ? nil : content.footnote) {
            header
            routeArea
            statGrid
            if !content.zoneMinutes.isEmpty, content.zoneMinutes.reduce(0, +) > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HEART-RATE ZONES")
                        .font(.system(size: 8, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.secondaryText)
                    ShareZoneBar(minutes: content.zoneMinutes)
                }
            }
            if !content.splits.isEmpty {
                splitRow
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(content.date.formatted(date: .long, time: .omitted))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var routeArea: some View {
        if let map {
            Image(uiImage: map)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 14))
        } else if !line.isEmpty {
            RouteLineShape(pieces: line)
                .stroke(Theme.primaryText, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            if mapUnavailable {
                Text("Map unavailable offline")
                    .font(.system(size: 8))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else if routeHidden {
            Text("Route hidden: it stays near a private place.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var statGrid: some View {
        let rows = stride(from: 0, to: content.stats.count, by: 3).map { Array(content.stats[$0..<min($0 + 3, content.stats.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, stat in
                        ShareStat(label: stat.0, value: stat.1)
                    }
                    // Keep columns aligned on a short last row.
                    ForEach(0..<(3 - row.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private var splitRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.splits.count > 1 ? "SPLITS" : "SPLIT")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                ForEach(Array(content.splits.enumerated()), id: \.offset) { _, split in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(split.0)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        Text(split.1)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
