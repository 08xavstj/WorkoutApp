import AppCore
import SwiftUI

/// "Share last week" under the review's numbers.
struct WeeklyShareButton: View {
    let weekStart: Date
    let trainingDays: Int
    let floors: HealthFloors.Week
    @State private var sharing = false

    var body: some View {
        Button("Share last week", systemImage: "square.and.arrow.up") { sharing = true }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .sheet(isPresented: $sharing) {
                WeeklyShareSheet(weekStart: weekStart, trainingDays: trainingDays, floors: floors)
            }
    }
}

/// The weekly summary image (spec B4): training days, cardio, active minutes
/// against WHO's 150–300 and strength days against its 2 a week (Bull et
/// al., Br J Sports Med 2020). Sleep regularity is health data, so it is off
/// until switched on (spec §6 rule 2).
struct WeeklyShareSheet: View {
    let weekStart: Date
    let trainingDays: Int
    let floors: HealthFloors.Week

    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle.light
    @State private var showSleep = false
    @State private var cardio: (sessions: Int, minutes: Int)?
    @State private var image: RenderedShareImage?

    private struct Options: Equatable {
        var style: ShareCardStyle
        var showSleep: Bool
        var cardioLoaded: Bool
    }

    private var summary: WeeklyShareSummary {
        WeeklyShareSummary(weekStart: weekStart, trainingDays: trainingDays, cardioSessions: cardio?.sessions ?? 0,
                           cardioMinutes: cardio?.minutes ?? 0, moderateMinutes: floors.moderateMinutes,
                           vigorousMinutes: floors.vigorousMinutes, strengthDays: floors.strengthDays,
                           sleepRegularity: showSleep ? floors.sleepRegularity : nil)
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
                    ShareImagePreview(image: image, style: style, subject: "My week")
                        .listRowBackground(Color.clear)
                }
                if floors.sleepRegularity != nil {
                    Section {
                        Toggle("Show sleep regularity", isOn: $showSleep)
                    } footer: {
                        Text("Sleep is health data, so it stays off the image unless you add it.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Share last week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadCardio() }
            .task(id: Options(style: style, showSleep: showSleep, cardioLoaded: cardio != nil)) {
                // Until cardio is in, the card would read "0 cardio": no image, no Share button.
                guard cardio != nil else {
                    image = nil
                    return
                }
                image = ShareRenderer.image(WeeklyShareCard(summary: summary, style: style),
                                            size: ShareRenderer.cardSize, style: style)
            }
        }
    }

    /// Cardio and sports from Apple Health in the week (strength left out:
    /// it counts as training days).
    private func loadCardio() async {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        let workouts = (try? await health?.externalWorkouts(from: weekStart, to: end)) ?? []
        let inWeek = workouts.filter { !$0.isStrength && $0.start >= weekStart && $0.start < end }
        cardio = (inWeek.count, inWeek.reduce(0) { $0 + $1.minutes })
    }
}

/// The card itself.
struct WeeklyShareCard: View {
    let summary: WeeklyShareSummary
    let style: ShareCardStyle

    private var weekText: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: summary.weekStart) ?? summary.weekStart
        return "\(summary.weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    var body: some View {
        ShareCardFrame(style: style, wash: [Theme.Wash.lime, Theme.Wash.mint],
                       footnote: "Targets: WHO 2020 guidelines (150–300 active minutes, vigorous counted double; strength 2 days a week).") {
            VStack(alignment: .leading, spacing: 2) {
                Text("My week")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text(weekText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(alignment: .top, spacing: 8) {
                ShareStat(label: "Training days", value: "\(summary.trainingDays)")
                ShareStat(label: summary.cardioSessions == 1 ? "Cardio session" : "Cardio sessions", value: "\(summary.cardioSessions)")
                ShareStat(label: "Cardio time", value: "\(summary.cardioMinutes) min")
            }
            if let line = summary.activeLine, let fraction = summary.activeFraction {
                target(title: "Active minutes", line: line, fraction: fraction,
                       band: (Double(WeeklyActivityBand.floorMinutes), Double(WeeklyActivityBand.bestMinutes)),
                       scale: Double(WeeklyActivityBand.scaleMinutes), met: summary.activeBand != .below)
            }
            if let line = summary.strengthLine, let days = summary.strengthDays {
                target(title: "Strength", line: line, fraction: min(1, Double(days) / 4),
                       band: (Double(StrengthDays.weeklyTarget), Double(StrengthDays.weeklyTarget)), scale: 4,
                       met: summary.strengthMet == true)
            }
            if let line = summary.sleepLine {
                Text(line)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A bar with the target marked: a band for active minutes, a tick for strength days.
    private func target(title: String, line: String, fraction: Double, band: (Double, Double), scale: Double, met: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Image(systemName: met ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(met ? Theme.recoveryHigh : Theme.secondaryText)
            }
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    // The target, behind the fill.
                    Rectangle()
                        .fill(Theme.recoveryHigh.opacity(0.25))
                        .frame(width: max(2, width * (band.1 - band.0) / scale))
                        .offset(x: width * band.0 / scale)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.recoveryHighLight, Theme.recoveryHigh], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, width * fraction))
                }
            }
            .frame(height: 8)
            .clipShape(.capsule)
            Text(line)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
    }
}
