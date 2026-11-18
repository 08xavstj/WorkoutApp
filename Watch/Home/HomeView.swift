import SwiftUI
#if canImport(AppCore)
import AppCore
#endif

/// The first screen (docs/research/watch-app-redesign-2026-11.md §4.3), one
/// column the crown scrolls: today's recovery and strain, today's plan with
/// Start, quick-start tiles for lifting and the last cardio, more activities,
/// the last workout, and settings. The glance and plan use the complications'
/// own rules (`GlanceFreshness`, `PlanGlance`), so Home and the face always
/// agree, and a stale reading shows "--". A scrolling page, so no double-tap
/// action here (HIG Gestures).
struct HomeView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio
    @State private var feed = FaceFeed.shared
    @State private var showingPicker = false
    @State private var showingToday = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TimelineView(.everyMinute) { context in
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                showingToday = true
                            } label: {
                                GlanceHeader(data: feed.data, now: context.date)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Shows today's scores")
                            PlanCard(data: feed.data, doneAt: feed.lastWorkoutEnd, now: context.date)
                        }
                    }
                    QuickStartTiles(showingPicker: $showingPicker)
                    if let session = cardio.weeklyIntervals,
                       let activity = CardioActivity(rawValue: session.modality.watchActivity) {
                        HardCardioCard(session: session, activity: activity)
                    }
                    NavigationLink {
                        ActivityPickerView()
                    } label: {
                        Label("More activities", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("watch-start-cardio")
                    if let last = WatchHistoryStore.last {
                        NavigationLink {
                            LastActivityView(record: last)
                        } label: {
                            LastActivityRow(record: last)
                        }
                    }
                    status
                    footer
                }
            }
            .navigationTitle("Tensile")
            .navigationDestination(isPresented: $showingPicker) {
                ActivityPickerView()
            }
            .background(alignment: .top) {
                // A faint wash of the lifting colour at the top (the iPhone app's look);
                // never on the workout pages (HIG Color).
                LinearGradient(colors: [WatchPalette.lifting.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 140)
                    .ignoresSafeArea()
                    .hiddenWhenLuminanceReduced()
            }
            .sheet(isPresented: $showingToday) {
                TodayDetailView(data: feed.data)
            }
        }
        .onAppear { feed.reload() }
        // "Start cardio in Tensile" (`StartCardioIntent`) opens the list.
        .onChange(of: cardio.pickerRequested, initial: true) {
            guard cardio.pickerRequested else { return }
            cardio.pickerRequested = false
            showingPicker = true
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.phase == .starting || cardio.phase == .starting {
            ProgressView("Starting…")
        }
        if let problem = model.problem ?? cardio.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(WatchPalette.heart)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            NavigationLink {
                WatchSettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            // When the complications last got scores from the iPhone, so a "--" says why.
            Text(phoneDataLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("watch-phone-data")
        }
        .padding(.top, 4)
    }

    private var phoneDataLine: String {
        guard let updated = feed.data?.updated else {
            return "No scores from your iPhone yet. Open Tensile on your iPhone."
        }
        return "Scores from iPhone " + updated.formatted(date: Calendar.current.isDateInToday(updated) ? .omitted : .abbreviated, time: .shortened)
    }
}

// MARK: Glance

/// Recovery as a ten-segment ring with its band word, and strain as a bar
/// with today's target outlined, by the complications' freshness rules.
private struct GlanceHeader: View {
    let data: WatchFaceData?
    let now: Date

    /// Today's numbers only: yesterday's would read as today's after midnight.
    private var today: WatchFaceData? {
        guard let data, data.scoresAreCurrent(at: now) else { return nil }
        return data
    }

    private var strain: Double? {
        guard let today, GlanceFreshness.strainIsCurrent(updated: today.updated, at: now) else { return nil }
        return today.strain.flatMap { $0.isFinite ? $0 : nil }
    }

    /// "Recovered", "Normal", "Easy day", "Calibrating".
    private var bandText: String? {
        guard let today, today.recovery != nil else { return nil }
        if today.calibrating { return "Calibrating" }
        if today.easyDay { return "Easy day" }
        return today.bandLabel
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                SegmentedRing(fraction: today?.recovery.map { Double($0) / 100 }, color: WatchPalette.band(today?.band), width: 6)
                Text(today?.recovery.map { "\($0)" } ?? "--")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(bandText ?? (today == nil ? "Open Tensile on iPhone" : "Recovery"))
                    .font(.headline)
                    .foregroundStyle(today == nil ? .secondary : WatchPalette.band(today?.band))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                HStack(spacing: 4) {
                    Text("Strain")
                        .foregroundStyle(.secondary)
                    Text(strain.map { "\(Int($0.rounded()))%" } ?? "--")
                        .monospacedDigit()
                        .foregroundStyle(WatchPalette.strain)
                }
                .font(.footnote.weight(.semibold))
                StrainBar(strain: strain, target: today?.target, color: WatchPalette.strain)
                    .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        guard let today else { return "No scores for today. Open Tensile on your iPhone." }
        var parts = ["Recovery " + (today.recovery.map { "\($0) percent" } ?? "not scored yet")]
        if let bandText { parts.append(bandText) }
        parts.append("Strain " + (strain.map { "\(Int($0.rounded())) percent" } ?? "not current"))
        if let target = today.target {
            parts.append("target \(Int(target.lowerBound.rounded())) to \(Int(target.upperBound.rounded())) percent")
        }
        return parts.joined(separator: ", ")
    }
}

/// Today's scores in full, from the glance.
private struct TodayDetailView: View {
    let data: WatchFaceData?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today")
                    .font(.headline)
                if let data, data.scoresAreCurrent(at: .now) {
                    SummaryRow(label: "Recovery", value: data.recovery.map { "\($0)%" } ?? "--")
                    if let band = data.calibrating ? "Calibrating" : data.bandLabel {
                        SummaryRow(label: "Band", value: band)
                    }
                    let strainCurrent = GlanceFreshness.strainIsCurrent(updated: data.updated, at: .now)
                    SummaryRow(label: "Strain", value: strainCurrent ? (data.strain.map { "\(Int($0.rounded()))%" } ?? "--") : "--")
                    if let target = data.target {
                        SummaryRow(label: "Target", value: "\(Int(target.lowerBound.rounded()))–\(Int(target.upperBound.rounded()))%")
                    }
                    if data.easyDay {
                        // The phone's own guidance (heart-rate-variability guided), not new advice.
                        Text("Easy day: your iPhone suggests keeping training light today.")
                            .font(.footnote)
                            .foregroundStyle(WatchPalette.easy)
                    }
                    Text("From your iPhone at \(data.updated.formatted(date: .omitted, time: .shortened)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No scores for today yet. Open Tensile on your iPhone to update them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Plan

/// Today's plan in the complication's words (`PlanGlance`), with the phone's
/// live session to join when there is one.
private struct PlanCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    let data: WatchFaceData?
    let doneAt: Date?
    let now: Date

    var body: some View {
        let lines = PlanGlance.lines(for: PlanGlance.state(of: data?.plan, at: now, alsoDoneAt: doneAt),
                                     at: now, onWatch: true)
        VStack(alignment: .leading, spacing: 4) {
            if let live = model.snapshot, !live.isFinished {
                // The phone's session is running: join it here.
                Label("On your iPhone", systemImage: "iphone")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.lifting)
                Text("\(live.name) · \(live.completedSets) of \(live.totalSets) sets")
                    .font(.headline)
                    .lineLimit(2)
                NavigationLink {
                    SessionPreviewView(session: live)
                } label: {
                    Label("Join", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(WatchPalette.onTint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(WatchPalette.recovery, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Join \(live.name)")
            } else if let plan = model.plannedSession, model.offersPlan(plan, at: now) {
                // Sent ahead by the phone: runs on the Watch alone.
                Label(lines.eyebrow, systemImage: lines.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.lifting)
                Text(plan.name)
                    .font(.headline)
                    .lineLimit(2)
                if let detail = lines.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    SessionPreviewView(session: plan, isPlan: true, minutes: plan.plannedMinutes)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(WatchPalette.onTint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(WatchPalette.recovery, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(plan.name)")
            } else {
                Label(lines.eyebrow, systemImage: lines.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.lifting)
                Text(lines.title)
                    .font(.headline)
                    .lineLimit(2)
                if let detail = lines.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if let data, data.scoresAreCurrent(at: now), data.easyDay {
                Text("Easy day: keep the plan light")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchPalette.easy)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: Quick start

/// Two 64 pt tiles: Lift, and the last cardio activity (one tap starts it
/// with its stored target).
private struct QuickStartTiles: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio
    @Binding var showingPicker: Bool
    @AppStorage(WatchCardioModel.lastActivityKey) private var lastRaw = CardioActivity.outdoorRun.rawValue
    @AppStorage(WatchCardioModel.targetKey) private var targetRaw = CardioTarget.off.storage

    private var last: CardioActivity { CardioActivity(rawValue: lastRaw) ?? .outdoorRun }
    private var isStarting: Bool { model.phase == .starting || cardio.phase == .starting }

    /// Tile height (app's choice, above the 44 pt minimum).
    private static let height: CGFloat = 64

    var body: some View {
        HStack(spacing: 8) {
            if let live = model.snapshot, !live.isFinished {
                NavigationLink {
                    SessionPreviewView(session: live)
                } label: {
                    tile("Lift", systemImage: "dumbbell.fill", tint: WatchPalette.lifting)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lift: \(live.name)")
            } else if let plan = model.plannedSession, model.offersPlan(plan) {
                NavigationLink {
                    SessionPreviewView(session: plan, isPlan: true, minutes: plan.plannedMinutes)
                } label: {
                    tile("Lift", systemImage: "dumbbell.fill", tint: WatchPalette.lifting)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lift: \(plan.name)")
            } else {
                NavigationLink {
                    QuickLiftView()
                } label: {
                    tile("Lift", systemImage: "dumbbell.fill", tint: WatchPalette.lifting)
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityLabel("Quick lift")
            }
            Button {
                let target = CardioTarget(storage: targetRaw)
                let activity = last
                Task { await cardio.start(activity, target: target) }
            } label: {
                tile(last.title, systemImage: last.systemImage, tint: WatchPalette.strain)
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
            .accessibilityLabel("Start \(last.title)")
        }
    }

    private func tile(_ title: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(WatchPalette.onTint)
        .frame(maxWidth: .infinity, minHeight: Self.height)
        .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: Hard cardio

/// This week's hard cardio session from the phone ("4 × 4 min · Bike"),
/// started in cardio mode and run step by step (Helgerud 2007, Wen 2019:
/// `IntervalSession`).
private struct HardCardioCard: View {
    @Environment(WatchCardioModel.self) private var cardio
    @Environment(WatchWorkoutModel.self) private var model
    let session: IntervalSession
    let activity: CardioActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Hard cardio this week", systemImage: "bolt.heart.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(WatchPalette.heart)
            Text(session.title)
                .font(.headline)
            Text("\(session.totalMinutes) min · \(session.hardMinutes) hard")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                let session = session
                let activity = activity
                Task { await cardio.start(activity, target: .off, interval: session) }
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(WatchPalette.onTint)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(WatchPalette.heart, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.phase == .starting || cardio.phase == .starting)
            .accessibilityLabel("Start \(session.title)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: Last activity

private struct LastActivityRow: View {
    let record: WatchActivityRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Last activity")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(record.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(record.start.formatted(.dateTime.weekday(.abbreviated))) · \(record.minutes) min · \(record.detail)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The last workout's numbers, as stored on the Watch.
private struct LastActivityView: View {
    let record: WatchActivityRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(record.title)
                    .font(.headline)
                Text(record.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SummaryRow(label: "Time", value: "\(record.minutes) min")
                SummaryRow(label: record.kind == .lift ? "Sets" : "Distance", value: record.detail)
                if let average = record.averageBpm {
                    SummaryRow(label: "Avg HR", value: "\(average) bpm")
                }
                if let maximum = record.maximumBpm {
                    SummaryRow(label: "Max HR", value: "\(maximum) bpm")
                }
                if !record.saved {
                    Text("Not saved to Apple Health.")
                        .font(.footnote)
                        .foregroundStyle(WatchPalette.strain)
                }
                OpenOnPhoneRow(text: "The full workout is in Tensile on your iPhone")
            }
        }
        .navigationTitle("Last activity")
    }
}
