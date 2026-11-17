import SwiftUI
import PhotosUI
import AppCore

/// What the entry sheet opens with: a day, and the screenshot's reading when
/// the numbers come from one (nil when they're typed).
nonisolated struct AppleScoresEntry: Identifiable {
    let id = UUID()
    var day: Date
    var reading: AppleScoreScreenReader.Result?
}

/// Health › Records › Apple's scores: Apple's own Readiness, Sleep score and
/// Health Age, kept beside Tensile's recovery, sleep score and body age.
///
/// Apple shares none of the three with other apps
/// (docs/research/apple-scores-2026-11.md), so they come in from a screenshot
/// read on the phone, by typing, or from the "Log Apple scores" Shortcuts
/// action. The page never says which number is right: Apple's and Tensile's
/// are worked out differently, and Apple hasn't published its formulas.
struct AppleScoresView: View {
    static let title = "Apple's scores"

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals
    @State private var pickedScreenshot: PhotosPickerItem?
    @State private var isReading = false
    @State private var readingNote: String?
    @State private var entry: AppleScoresEntry?

    private var store: AppleScoresStore { .shared }

    var body: some View {
        HealthDetailPage(title: Self.title) {
            todayCard
            addCard
            ForEach(AppleScoreKind.allCases) { kind in
                AppleScoreComparisonCard(kind: kind, log: store.log)
            }
            recentDaysCard
            aboutCard
        }
        .sheet(item: $entry) { entry in
            AppleScoresEntrySheet(entry: entry)
        }
        .onChange(of: pickedScreenshot) { _, item in
            guard let item else { return }
            Task { await read(item) }
        }
        .task { keepAppValues() }
    }

    // MARK: Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: "From Apple")
                .padding(.bottom, 6)
            AppleScoreTodayRow(
                title: "Readiness",
                value: store.reading(.readiness, on: store.now).map { "\($0.value)" },
                unit: "of 10",
                detail: todayDetail(.readiness, tensile: tensileRecovery.map { "Tensile recovery \($0)%" })
            )
            Divider()
            AppleScoreTodayRow(
                title: "Sleep score",
                value: store.reading(.sleepScore, on: store.now).map { "\($0.value)" },
                unit: "",
                detail: todayDetail(.sleepScore, tensile: metrics.sleep.map { "Tensile sleep score \($0.score)" })
            )
            Divider()
            AppleScoreTodayRow(
                title: "Health Age",
                value: store.latest(.healthAge).map { "\($0.reading.value)" },
                unit: "years",
                detail: healthAgeDetail
            )
        }
        .card()
    }

    /// Today's recovery; nil while the score on Today is still yesterday's.
    private var tensileRecovery: Int? {
        metrics.recoveryIsFromYesterday ? nil : metrics.recovery?.score
    }

    /// "Ready · Tensile recovery 62%", or that today's number isn't in.
    private func todayDetail(_ kind: AppleScoreKind, tensile: String?) -> String {
        guard let reading = store.reading(kind, on: store.now) else {
            return kind == .readiness ? "Not added today" : "Last night's not added"
        }
        return [kind.levelLabel(for: reading.value), tensile].compactMap { $0 }.joined(separator: " · ")
    }

    private var healthAgeDetail: String {
        guard let latest = store.latest(.healthAge) else { return "Not added" }
        var parts = ["Added \(Self.dayText(latest.day))"]
        if let range = vitals.bodyAge?.range { parts.append("Tensile body age \(range.lowerBound)–\(range.upperBound)") }
        return parts.joined(separator: " · ")
    }

    // MARK: Adding

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Add numbers")
            if !store.missingToday.isEmpty {
                Text(missingText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PhotosPicker(selection: $pickedScreenshot, matching: .screenshots) {
                Label("Read a screenshot", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isReading)
            .accessibilityIdentifier("apple-scores-screenshot")
            Button {
                readingNote = nil
                entry = AppleScoresEntry(day: store.now, reading: nil)
            } label: {
                Label("Type them in", systemImage: "keyboard")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("apple-scores-type")
            if isReading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Reading the screenshot…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if let readingNote {
                Text(readingNote)
                    .font(.subheadline)
                    .foregroundStyle(Theme.recoveryModerateText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Screenshot the Readiness, Sleep or Health screen, then pick it here. It's read on this iPhone and not kept, and you check the numbers before they're saved. In Shortcuts, the action is \u{201C}Log Apple scores\u{201D}.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var missingText: String {
        let names = store.missingToday.map { $0 == .readiness ? "Readiness" : "last night's Sleep score" }
        return "Today's " + names.joined(separator: " and ") + (names.count == 1 ? " isn't in yet." : " aren't in yet.")
    }

    /// Reads the picked screenshot on the phone and opens the entry sheet
    /// with what was found, for the owner to check.
    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        readingNote = nil
        defer {
            isReading = false
            pickedScreenshot = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                readingNote = "That picture couldn't be opened. You can type the numbers in."
                return
            }
            let lines = try await ScreenshotTextReader.lines(in: data)
            let result = AppleScoreScreenReader.read(lines)
            guard !result.isEmpty else {
                readingNote = "No Readiness, Sleep score or Health Age found in that picture. You can type the numbers in."
                return
            }
            let calendar = Calendar.current
            let day = result.dayHint == .yesterday ? calendar.date(byAdding: .day, value: -1, to: store.now) ?? store.now : store.now
            entry = AppleScoresEntry(day: day, reading: result)
        } catch {
            readingNote = "That picture couldn't be read. You can type the numbers in."
        }
    }

    // MARK: Recent days

    @ViewBuilder
    private var recentDaysCard: some View {
        // The newest 14 days with a number, newest first.
        let days: [String] = Array(store.log.days.keys.sorted().suffix(14).reversed())
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardLabel(text: "Recent days")
                    .padding(.bottom, 6)
                ForEach(days, id: \.self) { key in
                    if key != days.first { Divider() }
                    Button {
                        // Noon on that day, but never later than now (the day picker stops at now).
                        let noon = AppleScoreLog.date(forKey: key) ?? store.now
                        entry = AppleScoresEntry(day: min(noon, store.now), reading: nil)
                    } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(Self.dayText(key).capitalizedFirst)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text(dayDetail(key))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 8)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the day to change or remove its numbers")
                }
            }
            .card()
        }
    }

    /// "Readiness 7 (recovery 62%) · Sleep score 82 (78)".
    private func dayDetail(_ key: String) -> String {
        guard let day = store.log.days[key] else { return "" }
        var parts: [String] = []
        if let readiness = day.readiness {
            parts.append("Readiness \(readiness.value)" + (day.appRecovery.map { " (Tensile recovery \($0)%)" } ?? ""))
        }
        if let sleep = day.sleepScore {
            parts.append("Sleep score \(sleep.value)" + (day.appSleepScore.map { " (Tensile \($0))" } ?? ""))
        }
        if let age = day.healthAge {
            parts.append("Health Age \(age.value)" + (day.appBodyAge.map { " (Tensile body age \($0))" } ?? ""))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple's numbers and Tensile's are worked out differently, so they won't always match. Neither is the measure of the other.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: Self.about, title: "About Apple's numbers")
        }
        .card()
    }

    /// What Apple has said about each number, and why they're added by hand.
    private static let about = [
        "Readiness is a 0 to 10 score on Apple Watch Series 12 and Ultra 4, from recent activity, vitals and the sleep score. Apple's words for it: Recover (0–1), Pace Yourself (2–4), Ready (5–7), Go For It (8–10). It changes through the day; Tensile keeps the last one you add (Apple Support, \u{201C}Understand your readiness score on Apple Watch\u{201D}).",
        "The Sleep score is out of 100: sleep duration 50 points, bedtime consistency 30, interruptions 20 (Apple Watch User Guide).",
        "Health Age is in the Health app's Longevity tab, from VO₂ max, resting heart rate, sleep and HRV (Apple, 3 November 2026).",
        "Apple hasn't published the formula for any of the three, and doesn't share the numbers with other apps (checked 17 November 2026). That's why they're added here by screenshot, typing or Shortcuts.",
    ]

    // MARK: Helpers

    /// "today", "yesterday" or "12 Nov" for a day key.
    static func dayText(_ key: String) -> String {
        guard let date = AppleScoreLog.date(forKey: key) else { return key }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// Tensile's own numbers go beside Apple's for the days they belong to.
    private func keepAppValues() {
        store.reloadIfUnavailable()
        store.keepAppValues(recovery: metrics.recovery?.score, recoveryIsFromYesterday: metrics.recoveryIsFromYesterday,
                            bodyAge: vitals.bodyAge?.years)
    }
}

/// One of the three rows at the top: Apple's name for the number, the value,
/// and a line with Apple's word for it and Tensile's own number.
private struct AppleScoreTodayRow: View {
    let title: String
    let value: String?
    let unit: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(Theme.Typography.context)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(Theme.Typography.rowNumber)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("–")
                    .font(Theme.Typography.rowNumber)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}

private extension String {
    /// "today" → "Today"; leaves "12 Nov" alone.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
