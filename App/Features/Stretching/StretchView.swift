import SwiftUI
import SwiftData
import UIKit
import AppCore

/// A stretch's photo, bundled with the app (public-domain free-exercise-db),
/// so it shows without a connection. Nothing when the file is missing.
struct StretchPhoto: View {
    let name: String
    var height: CGFloat = 200

    private var image: UIImage? {
        Bundle.main.url(forResource: name, withExtension: "jpg").flatMap { UIImage(contentsOfFile: $0.path) }
    }

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .clipShape(.rect(cornerRadius: 12))
                .accessibilityHidden(true)
        }
    }
}

/// "5-minute stretch" in Today's Up next until it's done for the day: today's
/// areas and the week's minutes, opening the guided session (`Stretching`).
struct StretchOfferRow: View {
    @State private var store = StretchStore.shared
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var showing = false

    /// Whether the row shows today, so lists (Up next) can count it.
    static var isOffered: Bool { !StretchStore.shared.stretchedToday }

    var body: some View {
        if !store.stretchedToday {
            let routine = store.routine(lifts: StretchStore.lifts(from: sessions))
            let week = store.weekMinutes
            Button { showing = true } label: {
                HStack(spacing: 10) {
                    IconBadge(systemName: "figure.flexibility", color: Theme.recoveryHigh, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(Stretching.sessionMinutes)-minute stretch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("\(areaList(routine)) · \(week.done) of \(week.goal) min this week")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a guided stretch session")
            .sheet(isPresented: $showing) { StretchView() }
        }
    }

    /// "Calves, chest, lats +2".
    private func areaList(_ routine: Stretching.Routine) -> String {
        let names = routine.items.map(\.stretch.area.name)
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) +\(names.count - 3)" : shown
    }
}

/// The guided session: today's five stretches, each a short change of
/// position and two 30-second holds (one a side for one-sided stretches),
/// with the week's minutes by area and the evidence underneath.
struct StretchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StretchStore.shared
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    /// Fixed when the sheet opens, so logging a hold doesn't reshuffle it.
    @State private var routine: Stretching.Routine?
    @State private var steps: [Stretching.Step] = []
    @State private var stepIndex: Int?
    @State private var stepStart = Date.now
    @State private var paused: TimeInterval?
    @State private var completedHolds: [Int: Int] = [:]
    @State private var finished = false
    @State private var showingReachCheck = false
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var thumbnail: CGFloat = 64

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if finished {
                        summary
                    } else if let stepIndex, let routine, steps.indices.contains(stepIndex) {
                        running(steps[stepIndex], routine: routine)
                    } else if let routine {
                        intro(routine)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.mint, Theme.Wash.lime, Theme.Wash.sky], height: 300)
            }
            .background(Theme.background)
            .navigationTitle("Stretch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(stepIndex == nil || finished ? "Done" : "Stop") {
                        if stepIndex != nil, !finished {
                            finish()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear {
                guard routine == nil else { return }
                let today = store.routine(lifts: StretchStore.lifts(from: sessions))
                routine = today
                steps = Stretching.steps(for: today)
            }
            .task(id: timerKey) { await runStep() }
            .sensoryFeedback(.impact(weight: .medium), trigger: stepIndex)
        }
    }

    // MARK: Intro

    private func intro(_ routine: Stretching.Routine) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "Today's \(routine.minutes) minutes", color: Theme.recoveryHighText)
                    Spacer()
                    let week = store.weekMinutes
                    Chip(text: "\(week.done) of \(week.goal) min this week", color: Theme.recoveryHigh)
                }
                ForEach(routine.items) { item in
                    HStack(spacing: 12) {
                        StretchPhoto(name: item.stretch.imageName, height: thumbnail)
                            .frame(width: thumbnail * 1.4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.stretch.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primaryText)
                            Text("\(item.stretch.area.name) · \(item.stretch.perSide ? "30 s each side" : "2 × 30 s")")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(routine.reason)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    begin()
                } label: {
                    Text("Start \(routine.minutes) minutes")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.recoveryHighText, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .card(tint: Theme.recoveryHigh)

            Text("Ease in until the muscle feels tight, not painful, and breathe normally. Not just before lifting: long holds lower strength for a while.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            progressCard
            weekCard
            focusCard
            EvidenceDisclosure(points: Stretching.evidence, title: "What stretching does and doesn't do")
        }
    }

    /// Whether it's working: how each area's stretch has felt over the weeks
    /// (`Stretching.progress`) and the four-weekly reach check.
    private var progressCard: some View {
        let progress = store.progress
        let reach = Stretching.reachSummary(store.checks)
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Progress")
            if progress.isEmpty {
                Text("After each session, tap how every stretch felt. With four ratings over two weeks, each area shows here whether it's getting easier.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(progress) { entry in
                    HStack {
                        Text(entry.area.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Label(entry.text, systemImage: entry.change > 0.4 ? "arrow.up.right" : (entry.change < -0.4 ? "arrow.down.right" : "arrow.right"))
                            .font(.caption)
                            .foregroundStyle(entry.change > 0.4 ? Theme.recoveryHighText : Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Since \((progress.map(\.since).min() ?? .now).formatted(date: .abbreviated, time: .omitted)). Your own rating, so a trend for you, not a measurement.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(Theme.separator)
            ForEach(reach, id: \.self) { line in
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            }
            Button { showingReachCheck = true } label: {
                Label(store.reachCheckDue ? "Do the reach check · 1 min" : "Reach check done; next in about a month",
                      systemImage: "ruler")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.recoveryHighText)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the toe-touch and knee-to-wall check")
        }
        .card()
        .sheet(isPresented: $showingReachCheck) { ReachCheckView() }
    }

    /// The last 7 days by area: minutes stretched, plus the credit for lifting.
    private var weekCard: some View {
        let week = store.week(lifts: StretchStore.lifts(from: sessions))
        return VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Last 7 days")
            ForEach(week) { entry in
                HStack {
                    Text(entry.area.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Spacer()
                    Text(weekText(entry))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(entry.remaining < 0.01 ? Theme.recoveryHighText : Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    /// "4 of 5 min" or "3 + 2 lifting of 5 min".
    private func weekText(_ entry: Stretching.AreaWeek) -> String {
        func minutes(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
        let lifted = entry.lifted > 0 ? " + \(minutes(entry.lifted)) lifting" : ""
        return "\(minutes(entry.stretched))\(lifted) of \(minutes(entry.target)) min"
    }

    private var focusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Focus areas")
            Text("Pick the areas that feel tight: they get about 8 minutes a week and the rest about 3. With none picked, every area gets 5.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(StretchArea.allCases) { area in
                Toggle(area.name, isOn: Binding(
                    get: { store.focus.contains(area) },
                    set: { store.setFocus(area, on: $0) }
                ))
                .font(.subheadline)
            }
        }
        .card()
    }

    // MARK: Running

    private func running(_ step: Stretching.Step, routine: Stretching.Routine) -> some View {
        let item = routine.items[step.item]
        return VStack(spacing: 18) {
            Text("\(step.item + 1) of \(routine.items.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(item.stretch.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            StretchPhoto(name: item.stretch.imageName, height: 190)
            Text(step.label)
                .font(.headline)
                .foregroundStyle(step.kind == .hold ? Theme.recoveryHighText : Theme.secondaryText)
            TimelineView(.periodic(from: stepStart, by: 0.5)) { context in
                let left = remaining(of: step, at: context.date)
                Text("\(Int(left.rounded(.up)))")
                    .font(.system(size: timerSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(Int(left.rounded(.up))) seconds left")
            }
            Text(item.stretch.cue)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(paused == nil ? "Pause" : "Resume") { togglePause() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                Button("Skip") { advance(countingHold: false) }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .card(tint: Theme.recoveryHigh)
    }

    private var summary: some View {
        let seconds = completedHolds.values.reduce(0, +) * Stretching.holdSeconds
        let week = store.weekMinutes
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: seconds > 0 ? "Stretch done" : "Nothing logged", color: Theme.recoveryHighText)
                Spacer()
                if seconds > 0 {
                    Chip(text: seconds >= 60 ? "\(seconds / 60) min" : "\(seconds) s", color: Theme.recoveryHigh)
                }
            }
            Text("\(week.done) of \(week.goal) minutes this week. The weekly total is what builds flexibility, so a missed day is easy to make up.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if seconds > 0, let routine {
                Divider().overlay(Theme.separator)
                Text("How did each one feel?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Optional. The same stretch feeling easier over the weeks is the progress.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                ForEach(Array(routine.items.enumerated()), id: \.element.id) { index, item in
                    if (completedHolds[index] ?? 0) > 0 {
                        FeelRow(stretch: item.stretch, selection: store.feelToday(item.stretch.area)) { feel in
                            store.rate(item.stretch.area, feel)
                        }
                    }
                }
            }
            Button { dismiss() } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.recoveryHighText, in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .card(tint: Theme.recoveryHigh)
    }

    // MARK: Timer

    /// Restarts the step's wait whenever the step or the pause changes.
    private var timerKey: String {
        "\(stepIndex ?? -1)|\(paused == nil ? "run" : "paused")|\(stepStart.timeIntervalSince1970)"
    }

    private func remaining(of step: Stretching.Step, at date: Date) -> TimeInterval {
        let elapsed = paused ?? date.timeIntervalSince(stepStart)
        return max(0, Double(step.seconds) - elapsed)
    }

    private func begin() {
        completedHolds = [:]
        stepStart = .now
        paused = nil
        stepIndex = 0
    }

    private func togglePause() {
        if let elapsed = paused {
            stepStart = Date.now.addingTimeInterval(-elapsed)
            paused = nil
        } else {
            paused = Date.now.timeIntervalSince(stepStart)
        }
    }

    /// Waits out the current step, then moves on.
    private func runStep() async {
        guard let stepIndex, steps.indices.contains(stepIndex), paused == nil, !finished else { return }
        let left = remaining(of: steps[stepIndex], at: .now)
        try? await Task.sleep(for: .seconds(left))
        guard !Task.isCancelled else { return }
        advance(countingHold: true)
    }

    private func advance(countingHold: Bool) {
        guard let index = stepIndex, steps.indices.contains(index) else { return }
        let step = steps[index]
        if countingHold, step.kind == .hold { completedHolds[step.item, default: 0] += 1 }
        if index + 1 < steps.count {
            stepStart = .now
            paused = nil
            stepIndex = index + 1
        } else {
            finish()
        }
    }

    /// Logs the holds done (a stopped session keeps what was held).
    private func finish() {
        guard !finished else { return }
        finished = true
        if let routine {
            let entries = Stretching.log(routine: routine, completedHolds: completedHolds, at: .now)
            store.log(entries)
            if !entries.isEmpty { Reminders.cancelTodaysStretchReminder() }
        }
    }
}

/// "How did it feel?" for one stretch: four taps from very tight to easy.
private struct FeelRow: View {
    let stretch: Stretch
    let selection: Stretching.Feel?
    let onPick: (Stretching.Feel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(stretch.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 6) {
                ForEach(Stretching.Feel.allCases) { feel in
                    let picked = selection == feel
                    Button { onPick(feel) } label: {
                        Text(feel.title)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(picked ? Color.white : Theme.recoveryHighText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.horizontal, 2)
                            .background(picked ? Theme.recoveryHighText : Theme.recoveryHigh.opacity(0.14), in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stretch.area.name): \(feel.title)")
                    .accessibilityAddTraits(picked ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The four-weekly reach check: a standing toe touch and the knee-to-wall
/// distance (`Stretching.ReachCheck`). Rough markers for your own trend.
struct ReachCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StretchStore.shared
    @State private var toeTouch: Stretching.ToeTouch?
    @State private var measuresWall = false
    @State private var kneeToWall = 8.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    StretchPhoto(name: "stretch-reach-toe-touch", height: 170)
                        .listRowInsets(EdgeInsets())
                    Picker("Fingertips reach", selection: $toeTouch) {
                        Text("Not checked").tag(Stretching.ToeTouch?.none)
                        ForEach(Stretching.ToeTouch.allCases) { level in
                            Text(level.title).tag(Stretching.ToeTouch?.some(level))
                        }
                    }
                } header: {
                    Text("Toe touch")
                } footer: {
                    Text("Stand with your knees straight and reach down slowly, without bouncing. Do it at the same time of day each time, before stretching.")
                }
                Section {
                    Toggle("Measure knee to wall", isOn: $measuresWall)
                    if measuresWall {
                        Stepper(value: $kneeToWall, in: 0...25, step: 0.5) {
                            LabeledContent("Distance", value: "\(kneeToWall.formatted(.number.precision(.fractionLength(0...1)))) cm")
                        }
                    }
                } header: {
                    Text("Knee to wall (ankles and calves)")
                } footer: {
                    Text("Face a wall with one foot back from it. Find the furthest spot where your knee still touches the wall with the heel down, and measure from the big toe to the wall. Use the tighter side.")
                }
                Section {
                    ForEach(Stretching.reachSummary(store.checks), id: \.self) { line in
                        Text(line)
                    }
                } header: {
                    Text("So far")
                } footer: {
                    Text("Check about every four weeks: range changes over weeks, not days.")
                }
            }
            .navigationTitle("Reach check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.add(Stretching.ReachCheck(date: .now, toeTouch: toeTouch, kneeToWallCm: measuresWall ? kneeToWall : nil))
                        dismiss()
                    }
                    .disabled(toeTouch == nil && !measuresWall)
                }
            }
            .onAppear {
                if let last = store.checks.last?.kneeToWallCm { kneeToWall = last }
            }
        }
    }
}
