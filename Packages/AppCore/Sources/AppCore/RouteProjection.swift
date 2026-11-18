import Foundation

/// Route pieces projected to a unit square for drawing without a map (the
/// transparent share overlay): Web Mercator, the projection map tiles use,
/// so the shape matches what the map shows; scaled to fit with its aspect
/// ratio kept and centred.
public nonisolated enum RouteProjection {
    public struct Point: Sendable, Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Each piece as points in 0...1 (y grows downward, north up). Empty
    /// pieces are dropped; a single point sits in the middle.
    public static func normalized(_ segments: [[RoutePoint]]) -> [[Point]] {
        let projected = segments.filter { !$0.isEmpty }.map { $0.map(mercator) }
        let all = projected.flatMap { $0 }
        guard let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
              let minY = all.map(\.y).min(), let maxY = all.map(\.y).max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        guard span > 0 else { return projected.map { $0.map { _ in Point(x: 0.5, y: 0.5) } } }
        let offsetX = (span - (maxX - minX)) / 2
        let offsetY = (span - (maxY - minY)) / 2
        return projected.map { piece in
            piece.map { Point(x: ($0.x - minX + offsetX) / span, y: ($0.y - minY + offsetY) / span) }
        }
    }

    /// Web Mercator in unit-free numbers, y flipped so north is up on screen.
    static func mercator(_ point: RoutePoint) -> Point {
        let latitude = min(85, max(-85, point.latitude)) * .pi / 180
        let x = point.longitude * .pi / 180
        let y = -log(tan(.pi / 4 + latitude / 2))
        return Point(x: x, y: y)
    }
}
