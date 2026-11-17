import SwiftUI
import AppCore

/// One quiet line with Apple's number for a day, for the recovery and sleep
/// detail sheets: shown only when the owner added that number for that day.
/// It sits under Tensile's own score and says the two are worked out
/// differently, without ranking them.
struct AppleScoreLine: View {
    let kind: AppleScoreKind
    /// The day Tensile's score on the sheet is for.
    let day: Date

    var body: some View {
        if let reading = AppleScoresStore.shared.reading(kind, on: day) {
            Text(Self.text(kind, value: reading.value, day: day))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("apple-score-line-\(kind.rawValue)")
        }
    }

    static func text(_ kind: AppleScoreKind, value: Int, day: Date) -> String {
        let level = kind.levelLabel(for: value).map { ", \($0)" } ?? ""
        let calendar = Calendar.current
        let when = calendar.isDateInToday(day) ? "" : calendar.isDateInYesterday(day) ? " yesterday" : " that day"
        switch kind {
        case .readiness:
            return "Apple's Readiness\(when): \(value) of 10\(level). Apple works it out differently, so the two needn't match."
        case .sleepScore:
            return "Apple's Sleep score\(when): \(value)\(level). Apple works it out differently, so the two needn't match."
        case .healthAge:
            return "Apple's Health Age: \(value). Apple works it out differently, so the two needn't match."
        }
    }
}

/// The Records row on the Health tab that opens `AppleScoresView`.
struct AppleScoresRecordsRow: View {
    var body: some View {
        HealthNavigationRow(title: AppleScoresView.title, detail: detail, icon: "applewatch") {
            AppleScoresView()
        }
    }

    /// The latest numbers, or what the page is for.
    private var detail: String {
        let store = AppleScoresStore.shared
        var parts: [String] = []
        if let readiness = store.reading(.readiness, on: store.now) { parts.append("Readiness \(readiness.value)") }
        if let sleep = store.reading(.sleepScore, on: store.now) { parts.append("Sleep score \(sleep.value)") }
        if !parts.isEmpty { return parts.joined(separator: " · ") + " · today" }
        if store.log.isEmpty { return "Readiness, Sleep score and Health Age from your Watch" }
        return "Add today's Readiness and Sleep score"
    }
}
