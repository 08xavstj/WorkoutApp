import AppCore
import MapKit
import SwiftUI
import UIKit

/// A still map with the route drawn on it, for share images: a live `Map`
/// doesn't render into `ImageRenderer`, so the map comes from
/// `MKMapSnapshotter` and the line is drawn on top. Only the visible
/// (privacy-trimmed) pieces are drawn, and the map is framed on them alone,
/// so the edge of the picture doesn't point at a hidden start.
nonisolated enum RouteSnapshot {
    nonisolated struct RGBA: Sendable, Equatable {
        var red, green, blue, alpha: Double
    }

    /// One coloured stretch of the route.
    nonisolated struct Line: Sendable, Equatable {
        var latitudes: [Double]
        var longitudes: [Double]
        var color: RGBA
    }

    /// The stretches of `route` that `privacy` keeps, coloured as the in-app
    /// map colours them (`CardioRoute.stretches`, `Theme.zoneColors`).
    @MainActor
    static func lines(route: CardioRoute, privacy: RoutePrivacy.Result, metric: RouteMetric,
                      zones: HeartRateZoneScheme?, dark: Bool) -> [Line] {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        func rgba(_ color: Color) -> RGBA {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
            return RGBA(red: r, green: g, blue: b, alpha: a)
        }
        let palette = Theme.zoneColors.map(rgba)
        let neutral = rgba(Theme.neutralIcon)
        var lines: [Line] = []
        for stretch in route.stretches(for: metric, zones: metric == .heartRate ? zones : nil) {
            for visible in privacy.visibleRanges {
                let low = max(stretch.range.lowerBound, visible.lowerBound)
                let high = min(stretch.range.upperBound, visible.upperBound)
                guard high > low else { continue }
                let points = route.points[low...high]
                let color = stretch.level.flatMap { palette.indices.contains($0) ? palette[$0] : nil } ?? neutral
                lines.append(Line(latitudes: points.map(\.latitude), longitudes: points.map(\.longitude), color: color))
            }
        }
        return lines
    }

    /// The map at `size` points (at the share scale) with `lines` drawn on
    /// it, as PNG data (plain `Data` crosses back to the main actor safely);
    /// nil when there is nothing to draw or the map can't be loaded (offline).
    @concurrent
    static func image(lines: [Line], size: CGSize, dark: Bool) async -> Data? {
        let coordinates = lines.flatMap { line in zip(line.latitudes, line.longitudes).map { CLLocationCoordinate2D(latitude: $0, longitude: $1) } }
        guard !coordinates.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.mapRect = framing(coordinates, aspect: size.width / size.height)
        options.size = size
        options.scale = ShareCards.renderScale
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        return UIGraphicsImageRenderer(size: snapshot.image.size, format: format).pngData { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            // A pale casing under the coloured line, so it reads on any map.
            for (width, casing) in [(7.0, true), (4.0, false)] {
                cg.setLineWidth(width)
                for line in lines {
                    let points = zip(line.latitudes, line.longitudes).map {
                        snapshot.point(for: CLLocationCoordinate2D(latitude: $0, longitude: $1))
                    }
                    guard let first = points.first else { continue }
                    cg.beginPath()
                    cg.move(to: first)
                    for point in points.dropFirst() { cg.addLine(to: point) }
                    let color = casing
                        ? (dark ? UIColor.black.withAlphaComponent(0.55) : UIColor.white.withAlphaComponent(0.9))
                        : UIColor(red: line.color.red, green: line.color.green, blue: line.color.blue, alpha: line.color.alpha)
                    cg.setStrokeColor(color.cgColor)
                    cg.strokePath()
                }
            }
        }
    }

    /// The bounds of `coordinates` with a margin, widened to the image's aspect ratio.
    static func framing(_ coordinates: [CLLocationCoordinate2D], aspect: CGFloat) -> MKMapRect {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let margin = max(rect.width, rect.height) * 0.12 + 150
        rect = rect.insetBy(dx: -margin, dy: -margin)
        if rect.width / rect.height < aspect {
            let width = rect.height * aspect
            rect = rect.insetBy(dx: -(width - rect.width) / 2, dy: 0)
        } else {
            let height = rect.width / aspect
            rect = rect.insetBy(dx: 0, dy: -(height - rect.height) / 2)
        }
        return rect
    }
}

/// The visible route as a line on its own, for the transparent overlay
/// (`RouteProjection`). A Shape is drawn off the main thread, so it is
/// `nonisolated` (CLAUDE.md).
nonisolated struct RouteLineShape: Shape {
    let pieces: [[RouteProjection.Point]]

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2
        var path = Path()
        for piece in pieces where piece.count >= 2 {
            path.move(to: CGPoint(x: originX + piece[0].x * side, y: originY + piece[0].y * side))
            for point in piece.dropFirst() {
                path.addLine(to: CGPoint(x: originX + point.x * side, y: originY + point.y * side))
            }
        }
        return path
    }
}
