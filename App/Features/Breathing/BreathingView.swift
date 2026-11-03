import SwiftUI
import AppCore

// MARK: - Local log

/// Finished breathing sessions with the heart rate before and after, as a
/// JSON file in Application Support (like `CheckInStore`).
@Observable
final class BreathingLog {
    private(set) var sessions: [BreathingSession] = []

    @ObservationIgnored private let fileURL: URL = {
        let folder = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "breathing.json")
    }()

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([BreathingSession].self, from: data) {
            sessions = decoded
        }
    }

    func add(_ session: BreathingSession) {
        sessions.append(session)
        // Keep a year.
        let cutoff = Date.now.addingTimeInterval(-365 * 86_400)
        sessions.removeAll { $0.end < cutoff }
        if let data = try? JSONEncoder().encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    var latest: BreathingSession? { sessions.max { $0.end < $1.end } }
}

// MARK: - Offer on the Home strain card

/// One row offering a 5-minute session on easy (HRV-below-normal) days and
/// after a stressful day in the evening check-in (`PacedBreathing.isOffered`;
/// competitors.md item 6).
struct BreathingOfferRow: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns
    @State private var showing = false

    var body: some View {
        if PacedBreathing.isOffered(easyDay: metrics.trainEasyToday, eveningStress: checkIns.evening()?.stress) {
            Button { showing = true } label: {
                HStack(spacing: 10) {
                    IconBadge(systemName: "wind", color: Theme.oxygen, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("5 minutes of slow breathing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text(metrics.trainEasyToday ? "Fits an easy day: it raises HRV right after." : "After a stressful day: it lowers anxiety right after.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a guided breathing session")
            .sheet(isPresented: $showing) { BreathingView() }
        }
    }
}

// MARK: - The session

/// A 5-minute paced-breathing session at about 6 breaths a minute, with the
/// heart rate before and after from Apple Health when the watch recorded
/// any, logged as mindful minutes (`PacedBreathing`; Laborde 2022; Zaccaro 2018).
struct BreathingView: View {
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var log = BreathingLog()
    @State private var start: Date?
    @State private var finished: BreathingSession?
    @State private var phase: PacedBreathing.Phase = .inhale
    @State private var heartRateBefore: Double?
    @State private var savedToHealth = false
    @State private var isFinishing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let finished {
                        summary(finished)
                    } else if let start {
                        running(since: start)
                    } else {
                        intro
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.sky, Theme.Wash.mint, Theme.Wash.lavender], height: 300)
            }
            .background(Theme.background)
            .navigationTitle("Slow breathing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(start == nil || finished != nil ? "Done" : "Stop") {
                        if start != nil, finished == nil {
                            start = nil
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .task(id: start) { await runSession() }
            .sensoryFeedback(.impact(weight: .light), trigger: phase)
        }
    }

    // MARK: Screens

    private var intro: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Breathe in for 5½ seconds, out for 5½ seconds, following the circle, for 5 minutes. That's about 6 breaths a minute.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(PacedBreathing.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your heart rate from the minute before and the last minute of the session is shown afterwards when your watch recorded it. The session is saved to Apple Health as mindful minutes.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                start = .now
            } label: {
                Text("Start 5 minutes")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient(colors: Theme.oxygenColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .card(tint: Theme.oxygen)
    }

    private func running(since start: Date) -> some View {
        VStack(spacing: 24) {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let elapsed = context.date.timeIntervalSince(start)
                BreathingCircle(scale: reduceMotion ? 0.8 : PacedBreathing.scale(at: elapsed))
                    .frame(width: 260, height: 260)
                Text(timeText(PacedBreathing.remaining(at: elapsed)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .accessibilityLabel("\(Int(PacedBreathing.remaining(at: elapsed) / 60)) minutes left")
            }
            Text(phase.rawValue)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.oxygen)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: phase)
            Text("Through the nose if you can; let the out-breath be soft.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .contain)
    }

    private func summary(_ session: BreathingSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Session done", color: Theme.oxygen)
                Spacer()
                Chip(text: "\(session.minutes) min", color: Theme.oxygen)
            }
            Text(PacedBreathing.heartRateText(before: session.heartRateBefore, after: session.heartRateAfter))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(savedToHealth ? "Saved to Apple Health as mindful minutes." : "Couldn't save to Apple Health; the session is kept in the app.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(PacedBreathing.evidenceNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if log.sessions.count > 1 {
                Text("\(log.sessions.count) sessions logged.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.oxygen)
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded(.up))
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    // MARK: Running the session

    /// Reads the heart rate before, flips the phase label every half-breath
    /// (with a light tap), and finishes after 5 minutes.
    private func runSession() async {
        guard let start, finished == nil else { return }
        isFinishing = false
        heartRateBefore = await averageHeartRate(ending: start)
        var next = start
        while !Task.isCancelled {
            let (current, _) = PacedBreathing.phase(at: Date.now.timeIntervalSince(start))
            if current != phase { phase = current }
            next = next.addingTimeInterval(current == .inhale ? PacedBreathing.inhaleSeconds : PacedBreathing.exhaleSeconds)
            let wait = next.timeIntervalSinceNow
            if PacedBreathing.isComplete(at: Date.now.timeIntervalSince(start)) { break }
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            if Task.isCancelled { return }
        }
        guard !Task.isCancelled, !isFinishing else { return }
        isFinishing = true
        await finish(start: start)
    }

    private func finish(start: Date) async {
        let end = Date.now
        let after = await averageHeartRate(ending: end)
        let session = BreathingSession(start: start, end: end, heartRateBefore: heartRateBefore, heartRateAfter: after)
        log.add(session)
        if let health {
            do {
                try await health.saveMindfulSession(start: start, end: end)
                savedToHealth = true
            } catch {
                savedToHealth = false
            }
        }
        finished = session
        self.start = nil
    }

    /// Mean heart rate over the 60 s before `date`, or nil without samples.
    private func averageHeartRate(ending date: Date) async -> Double? {
        guard let health else { return nil }
        let window = DateInterval(start: date.addingTimeInterval(-PacedBreathing.heartRateWindowSeconds), end: date)
        let samples = (try? await health.heartRateSamples(from: window.start, to: window.end)) ?? []
        return PacedBreathing.averageHeartRate(samples, in: window)
    }
}

/// The guide: a soft disc that grows on the in-breath and shrinks on the
/// out-breath. Scaled shapes only (no Canvas), so it's safe to draw off the
/// main actor.
private struct BreathingCircle: View {
    let scale: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.oxygen.opacity(0.12))
            Circle()
                .fill(LinearGradient(colors: Theme.oxygenColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(scale)
                .shadow(color: Theme.oxygen.opacity(0.35), radius: 18)
        }
        .accessibilityHidden(true)
    }
}
