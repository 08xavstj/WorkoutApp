import SwiftUI
import WidgetKit

/// Watch face complications: recovery + strain, and the next planned session.
/// The Watch app writes `WatchFaceData` to the App Group when the phone sends
/// it; these only read it.
@main
struct TensileComplications: WidgetBundle {
    var body: some Widget {
        RecoveryStrainComplication()
        NextSessionComplication()
    }
}

nonisolated struct FaceEntry: TimelineEntry {
    let date: Date
    /// nil until the phone has sent anything.
    let data: WatchFaceData?
    /// The latest workout end (phone log or Watch): today's session is done.
    let doneAt: Date?
}

/// Shared by both complications: entries now and whenever the face should
/// change on its own (midnight, a session's start and end of its window), so
/// "next session" rolls forward without the phone.
nonisolated struct FaceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FaceEntry {
        FaceEntry(date: .now, data: WatchFaceData.sample(), doneAt: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FaceEntry) -> Void) {
        // The face editor shows sample data until the phone has sent real data.
        let data = WatchFaceStore.load()
        if context.isPreview && data == nil {
            completion(placeholder(in: context))
        } else {
            completion(FaceEntry(date: .now, data: data, doneAt: WatchFaceStore.lastWorkoutEnd(data)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FaceEntry>) -> Void) {
        let now = Date.now
        let data = WatchFaceStore.load()
        let doneAt = WatchFaceStore.lastWorkoutEnd(data)
        var dates = [now]
        dates += data?.changeDates(after: now) ?? [Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)]
        let entries = dates.map { FaceEntry(date: $0, data: data, doneAt: doneAt) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

/// The app's score colours (dark variants from `App/Design/Theme.swift` and
/// `RecoveryWording`), copied here because `Theme` needs UIKit.
nonisolated enum FacePalette {
    static let strain = color(0xFF8E3C)
    static let lifting = color(0xFF6B97)
    /// "Easy day" band (`Theme.oxygen`).
    static let easy = color(0x5C9DFF)
    /// "Normal" band (`Theme.recoveryModerate`).
    static let normal = color(0xFFC53D)
    /// "Recovered" band (`Theme.recoveryHigh`).
    static let recovered = color(0x3EDB84)
    static let track = Color.white.opacity(0.18)

    static func band(_ band: String?) -> Color {
        switch band {
        case "low": easy
        case "moderate": normal
        case "high": recovered
        default: .secondary
        }
    }

    static func color(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// e.g. "34%" (whole numbers; never crashes on NaN).
nonisolated func facePercent(_ value: Double) -> String {
    "\(faceWhole(value))%"
}

nonisolated func faceWhole(_ value: Double) -> Int {
    value.isFinite ? Int(value.rounded()) : 0
}

/// A 0-100 score as a 0-1 fraction for rings and bars.
nonisolated func faceFraction(_ value: Double) -> Double {
    value.isFinite ? min(max(value / 100, 0), 1) : 0
}

/// e.g. "50–70%".
nonisolated func faceRange(_ range: ClosedRange<Double>) -> String {
    "\(faceWhole(range.lowerBound))–\(faceWhole(range.upperBound))%"
}
