import Foundation

/// A route as a GPX 1.1 file (topografix.com/GPX/1/1): one track, one
/// segment per visible piece (route privacy can split a route), each point
/// with elevation and UTC time, and heart rate in Garmin's TrackPoint
/// extension v1, which Strava, Garmin Connect and most route tools read
/// (spec B5, docs/research/competitor-features-2026-11.md). The file is built
/// on the phone and handed to the share sheet; nothing is uploaded.
public nonisolated enum GPXExport {
    public static let creator = "Tensile"

    /// One point of a track: a route fix and the heart rate matched to it.
    public struct TrackPoint: Sendable, Equatable {
        public var point: RoutePoint
        public var heartRate: Double?

        public init(point: RoutePoint, heartRate: Double? = nil) {
            self.point = point
            self.heartRate = heartRate
        }
    }

    /// GPX `<type>` values: plain words, as most tools expect.
    public static func document(name: String, type: String?, segments: [[TrackPoint]]) -> String {
        let pieces = segments.filter { !$0.isEmpty }
        let usesHeartRate = pieces.contains { $0.contains { $0.heartRate != nil } }
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            "<gpx version=\"1.1\" creator=\"\(escape(creator))\" xmlns=\"http://www.topografix.com/GPX/1/1\""
                + " xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""
                + (usesHeartRate ? " xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\"" : "")
                + " xsi:schemaLocation=\"http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd\">",
        ]
        // `metadata` comes before `trk` in the 1.1 schema.
        if let first = pieces.first?.first {
            lines.append("  <metadata>")
            lines.append("    <name>\(escape(name))</name>")
            lines.append("    <time>\(time(first.point.time))</time>")
            lines.append("  </metadata>")
        }
        lines.append("  <trk>")
        lines.append("    <name>\(escape(name))</name>")
        if let type, !type.isEmpty { lines.append("    <type>\(escape(type))</type>") }
        for piece in pieces {
            lines.append("    <trkseg>")
            for item in piece {
                lines.append(trackPoint(item))
            }
            lines.append("    </trkseg>")
        }
        lines.append("  </trk>")
        lines.append("</gpx>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The pieces of `route` that `privacy` keeps, with heart rate, ready for `document`.
    public static func segments(route: CardioRoute, privacy: RoutePrivacy.Result) -> [[TrackPoint]] {
        privacy.visibleRanges.map { range in
            range.map { TrackPoint(point: route.points[$0], heartRate: route.heartRates[$0]) }
        }
    }

    static func trackPoint(_ item: TrackPoint) -> String {
        let point = item.point
        var text = "      <trkpt lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\">"
        // Child order is fixed by the schema: ele, time, ..., extensions.
        if let altitude = point.altitude, altitude.isFinite {
            text += "<ele>\(String(format: "%.1f", altitude))</ele>"
        }
        text += "<time>\(time(point.time))</time>"
        if let bpm = item.heartRate, bpm.isFinite, bpm > 0 {
            text += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(Int(bpm.rounded()))</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>"
        }
        return text + "</trkpt>"
    }

    /// Seven decimals: about 1 cm, finer than any GPS fix.
    static func coordinate(_ degrees: Double) -> String {
        String(format: "%.7f", degrees)
    }

    /// xsd:dateTime in UTC: "2026-11-18T06:30:05Z".
    static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// XML character escaping for text and attribute values.
    public static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                // XML 1.0 has no place for other control characters: dropped.
                let isControl = character.unicodeScalars.contains { $0.value < 0x20 && $0 != "\t" && $0 != "\n" && $0 != "\r" }
                if !isControl { result.append(character) }
            }
        }
        return result
    }

    /// A file name without characters iOS or other systems reject.
    public static func fileName(_ name: String, date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        let allowed = name.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        let base = String(allowed).split(separator: "-").joined(separator: "-")
        return "\(base.isEmpty ? "Workout" : base)-\(CSV.day(date, timeZone: timeZone)).\(ext)"
    }
}
