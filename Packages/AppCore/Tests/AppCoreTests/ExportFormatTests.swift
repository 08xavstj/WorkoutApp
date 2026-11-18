import Foundation
import Testing
@testable import AppCore

struct CSVExportTests {
    let utc = TimeZone(identifier: "UTC")!
    let date = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00:00Z

    @Test func fieldsWithCommasQuotesAndLineBreaksAreQuoted() {
        #expect(CSV.field("Bench press") == "Bench press")
        #expect(CSV.field("Press, incline") == "\"Press, incline\"")
        #expect(CSV.field("The \"big\" one") == "\"The \"\"big\"\" one\"")
        #expect(CSV.field("two\nlines") == "\"two\nlines\"")
        // "\r\n" is one Character in Swift; it still needs quotes.
        #expect(CSV.field("two\r\nlines") == "\"two\r\nlines\"")
        #expect(CSV.field("two\rlines") == "\"two\rlines\"")
        #expect(CSV.field("") == "")
    }

    @Test func formulaLikeTextIsDefused() {
        #expect(CSV.field("=SUM(A1)") == "'=SUM(A1)")
        #expect(CSV.field("@cmd") == "'@cmd")
        #expect(CSV.field("+1, more") == "\"'+1, more\"")
        // Numbers don't go through `field`, so negatives stay numbers.
        #expect(CSV.number(-3.25) == "-3.25")
    }

    @Test func numbersUseAPointAndNoTrailingZeros() {
        #expect(CSV.number(82.5) == "82.5")
        #expect(CSV.number(100.0) == "100")
        #expect(CSV.number(1.23456, decimals: 3) == "1.235")
        #expect(CSV.number(2.10, decimals: 2) == "2.1")
        #expect(CSV.number(nil as Double?) == "")
        #expect(CSV.number(.nan) == "")
        #expect(CSV.number(7) == "7")
        #expect(CSV.number(nil as Int?) == "")
    }

    @Test func datesAreISO8601() {
        #expect(CSV.timestamp(date, timeZone: utc) == "2027-01-15T08:00:00Z")
        let zurich = TimeZone(identifier: "Europe/Zurich")!
        #expect(CSV.timestamp(date, timeZone: zurich) == "2027-01-15T09:00:00+01:00")
        #expect(CSV.day(date, timeZone: utc) == "2027-01-15")
    }

    @Test func setsFileHasBothUnitsAndRIR() {
        let rows = [
            SetExportRow(date: date, workout: "Push, heavy", exercise: "Bench Press", setNumber: 1, setType: "warm-up",
                         weightKg: 40, reps: 10, rpe: nil),
            SetExportRow(date: date, workout: "Push, heavy", exercise: "Bench Press", setNumber: 2, setType: "straight",
                         weightKg: 100, reps: 5, rpe: 8.5),
        ]
        let text = SetsCSV.document(rows, pounds: true, timeZone: utc)
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines[0] == "\u{FEFF}date,workout,exercise,set,set_type,weight_lb,weight_kg,reps,rpe,rir")
        #expect(lines[1] == "2027-01-15T08:00:00Z,\"Push, heavy\",Bench Press,1,warm-up,88.18,40,10,,")
        #expect(lines[2] == "2027-01-15T08:00:00Z,\"Push, heavy\",Bench Press,2,straight,220.46,100,5,8.5,1.5")
        #expect(lines.last == "")
        let kilos = SetsCSV.document(rows, pounds: false, timeZone: utc)
        let kiloLines = kilos.components(separatedBy: "\r\n")
        #expect(kiloLines[0] == "\u{FEFF}date,workout,exercise,set,set_type,weight_kg,reps,rpe,rir")
        #expect(kiloLines[2] == "2027-01-15T08:00:00Z,\"Push, heavy\",Bench Press,2,straight,100,5,8.5,1.5")
    }

    @Test func rirFromRPE() {
        let row = SetExportRow(date: date, workout: "", exercise: "", setNumber: 1, setType: "straight", weightKg: 0, reps: 0, rpe: 10)
        #expect(row.rir == 0)
        var easy = row
        easy.rpe = 6
        #expect(easy.rir == 4)
        easy.rpe = nil
        #expect(easy.rir == nil)
    }

    @Test func cardioFileInKilometresOrMiles() {
        let rows = [CardioExportRow(start: date, type: "Run", source: "Apple Watch", durationSeconds: 1830,
                                    distanceMeters: 5012, averageBpm: 151.4, maximumBpm: 178, elevationGainMeters: 42.6),
                    CardioExportRow(start: date, type: "Yoga", durationSeconds: 3600)]
        let km = CardioCSV.document(rows, miles: false, timeZone: utc).components(separatedBy: "\r\n")
        #expect(km[0] == "\u{FEFF}date,type,source,duration_min,distance_km,avg_hr_bpm,max_hr_bpm,elevation_gain_m")
        #expect(km[1] == "2027-01-15T08:00:00Z,Run,Apple Watch,30.5,5.012,151,178,43")
        #expect(km[2] == "2027-01-15T08:00:00Z,Yoga,,60,,,,")
        let miles = CardioCSV.document(rows, miles: true, timeZone: utc).components(separatedBy: "\r\n")
        #expect(miles[0] == "\u{FEFF}date,type,source,duration_min,distance_mi,distance_km,avg_hr_bpm,max_hr_bpm,elevation_gain_m")
        #expect(miles[1] == "2027-01-15T08:00:00Z,Run,Apple Watch,30.5,3.114,5.012,151,178,43")
        #expect(miles[2] == "2027-01-15T08:00:00Z,Yoga,,60,,,,,")
    }

    @Test func filesStartWithAUTF8ByteOrderMarkForExcel() {
        let text = CSV.document(header: ["name"], rows: [["Zürich"]])
        #expect(Array(Data(text.utf8).prefix(3)) == [0xEF, 0xBB, 0xBF])
        #expect(String(text.dropFirst()) == "name\r\nZürich\r\n")
    }

    @Test func dailyScoresAreMergedByDayAndSorted() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let day1 = date
        let day2 = date.addingTimeInterval(86_400)
        let rows = [
            DailyScoreRow(date: day2.addingTimeInterval(3600), strain: 61.6),
            DailyScoreRow(date: day1, sleepScore: 82),
            DailyScoreRow(date: day2, sleepScore: 75),
            DailyScoreRow(date: day1.addingTimeInterval(-86_400 * 3)),
        ]
        let merged = DailyScoresCSV.merge(rows, calendar: calendar)
        #expect(merged.count == 2)
        #expect(merged[1].sleepScore == 75)
        #expect(merged[1].strain == 61.6)
        let lines = DailyScoresCSV.document(rows, calendar: calendar).components(separatedBy: "\r\n")
        #expect(lines[0] == "\u{FEFF}date,sleep_score,recovery,strain_percent")
        #expect(lines[1] == "2027-01-15,82,,")
        #expect(lines[2] == "2027-01-16,75,,62")
    }
}

struct GPXExportTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func point(_ index: Int, altitude: Double? = 410.3) -> RoutePoint {
        RoutePoint(latitude: 47.3505 + Double(index) * 0.0001, longitude: 8.539, altitude: altitude,
                   time: start.addingTimeInterval(Double(index) * 5), horizontalAccuracy: 5)
    }

    @Test func documentIsGPX11WithTimeElevationAndHeartRate() {
        let segment = [GPXExport.TrackPoint(point: point(0), heartRate: 140.4),
                       GPXExport.TrackPoint(point: point(1, altitude: nil), heartRate: nil)]
        let text = GPXExport.document(name: "Run & Ride <1>", type: "running", segments: [segment])
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<gpx version=\"1.1\" creator=\"Tensile\" xmlns=\"http://www.topografix.com/GPX/1/1\""))
        #expect(text.contains("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\""))
        #expect(text.contains("<metadata>\n    <name>Run &amp; Ride &lt;1&gt;</name>\n    <time>2027-01-15T08:00:00Z</time>\n  </metadata>"))
        #expect(text.contains("<type>running</type>"))
        #expect(text.contains("<trkpt lat=\"47.3505000\" lon=\"8.5390000\"><ele>410.3</ele><time>2027-01-15T08:00:00Z</time><extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>140</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions></trkpt>"))
        #expect(text.contains("<trkpt lat=\"47.3506000\" lon=\"8.5390000\"><time>2027-01-15T08:00:05Z</time></trkpt>"))
        #expect(text.hasSuffix("</gpx>\n"))
        // Balanced tags.
        #expect(text.components(separatedBy: "<trkseg>").count == text.components(separatedBy: "</trkseg>").count)
        #expect(text.components(separatedBy: "<trkpt ").count - 1 == 2)
    }

    @Test func eachVisiblePieceIsASegment() {
        let points = (0..<10).map { point($0) }
        let route = CardioRoute(points: points)
        let privacy = RoutePrivacy.Result(visibleRanges: [0...3, 6...9], isTrimmed: true, startTrimMeters: 0, endTrimMeters: 0)
        let segments = GPXExport.segments(route: route, privacy: privacy)
        #expect(segments.map(\.count) == [4, 4])
        let text = GPXExport.document(name: "Run", type: nil, segments: segments)
        #expect(text.components(separatedBy: "<trkseg>").count - 1 == 2)
        #expect(!text.contains("<type>"))
        // No heart rate anywhere: no extension namespace.
        #expect(!text.contains("gpxtpx"))
    }

    @Test func emptyRouteStillMakesAValidFile() {
        let text = GPXExport.document(name: "Walk", type: "walking", segments: [[]])
        #expect(text.contains("<trk>"))
        #expect(!text.contains("<trkseg>"))
        #expect(!text.contains("<metadata>"))
    }

    @Test func escapingCoversXMLSpecialsAndControls() {
        #expect(GPXExport.escape("a&b<c>d\"e'f") == "a&amp;b&lt;c&gt;d&quot;e&apos;f")
        #expect(GPXExport.escape("bell\u{07}") == "bell")
        #expect(GPXExport.escape("Zürich run") == "Zürich run")
    }

    @Test func fileNamesAreSafe() {
        let utc = TimeZone(identifier: "UTC")!
        #expect(GPXExport.fileName("Morning run / lake", date: start, ext: "gpx", timeZone: utc) == "Morning-run-lake-2027-01-15.gpx")
        #expect(GPXExport.fileName("///", date: start, ext: "gpx", timeZone: utc) == "Workout-2027-01-15.gpx")
    }
}

struct BackupDocumentTests {
    @Test func backupRoundTripsWithStoresAsJSON() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let set = BackupDocument.LoggedSet(order: 0, weightKg: 82.5, reps: 5, rpe: 8, isWarmup: false, completedAt: date, kind: nil)
        let session = BackupDocument.Session(
            name: "Push", startedAt: date, endedAt: date.addingTimeInterval(3600), sessionRPE: 7, notes: "", savedToHealth: true,
            linkedWorkoutUUID: nil, linkedWorkoutSource: nil, watchWorkoutUUID: nil,
            exercises: [BackupDocument.Exercise(exerciseID: "bench", name: "Bench Press", order: 0, sets: [set])])
        let store = try #require(JSONValue.parse(Data(#"{"a":[1,2.5,true,null,"x"],"b":{"c":false}}"#.utf8)))
        let document = BackupDocument(exportedAt: date, modelSchema: "1.3.0", sessions: [session], templates: [],
                                      hrvReadings: [.init(date: date, milliseconds: 55, source: "Garmin")],
                                      stores: ["gyms.json": store])
        let data = try document.encoded()
        let decoded = try BackupDocument.decode(data)
        #expect(decoded == document)
        #expect(decoded.format == BackupDocument.currentFormat)
        #expect(String(decoding: data, as: UTF8.self).contains("\"exportedAt\" : \"2027-01-15T08:00:00Z\""))
        #expect(store == .object(["a": .array([.number(1), .number(2.5), .bool(true), .null, .string("x")]),
                                  "b": .object(["c": .bool(false)])]))
    }

    @Test func onlyJSONStoresAreBackedUp() {
        #expect(BackupDocument.isBackedUpStore("gyms.json"))
        #expect(!BackupDocument.isBackedUpStore("gyms.json.bak"))
        #expect(!BackupDocument.isBackedUpStore("gyms.json.corrupt-123"))
        #expect(!BackupDocument.isBackedUpStore(".hidden.json"))
        // Private places and the trim salt stay on the phone.
        #expect(!BackupDocument.isBackedUpStore("route-privacy.json"))
        #expect(BackupDocument.excludedStores.allSatisfy { !BackupDocument.isBackedUpStore($0) })
        #expect(JSONValue.parse(Data("not json".utf8)) == nil)
    }
}
