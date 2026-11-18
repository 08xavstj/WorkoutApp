import SwiftUI
import AppCore

/// Breathing training for blood pressure (inspiratory muscle strength
/// training, `InspiratoryTraining`; docs/research/next-features-2026-11.md,
/// W12), in the blood-pressure section. Shown only when the newest reliable
/// 7-day home systolic average is 120 or more: nobody in the trials started
/// below that, so nobody starts there or without a home average; someone
/// already training keeps it (`InspiratoryTraining.eligibility`).
struct InspiratoryTrainingCard: View {
    let readings: [HomeBloodPressure.Reading]
    @State private var store = InspiratoryTrainingStore.shared

    var body: some View {
        let eligibility = InspiratoryTraining.eligibility(readings, sessions: store.sessions)
        switch eligibility {
        case .offered, .continuing:
            offer(eligibility)
        case .belowThreshold:
            // Not offered. Someone who trained earlier is told why it has gone; the log is kept.
            if !store.sessions.isEmpty {
                Text("Breathing training: your latest home average is under \(Int(InspiratoryTraining.systolicThreshold)) systolic, below where the trials started, so it's no longer suggested. Your \(InspiratoryTraining.fullDays(store.sessions)) logged days are kept.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .noAverage:
            EmptyView()
        }
    }

    private func offer(_ eligibility: InspiratoryTraining.Eligibility) -> some View {
        let week = InspiratoryTraining.fullDaysThisWeek(store.sessions)
        let done = InspiratoryTraining.doneToday(store.sessions)
        let average = eligibility.average
        let lead = average.map { "Your home average is \(Int($0.systolic.rounded())) systolic." } ?? "You're training."
        return VStack(alignment: .leading, spacing: 10) {
            Label("Breathing training", systemImage: "wind")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            // Stage 2 or very high: the doctor comes before any trainer.
            if eligibility.seeDoctorFirst, let category = average?.category {
                Text("\(HomeBloodPressure.advice(category)) Ask them before adding breathing training; it can add to their plan, not replace it.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .continuing = eligibility {
                Text("Keep going while you train: a lower average may be the training working, and in the main trial about a quarter of the effect was gone 6 weeks after people stopped (Craighead 2021).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(lead) In small trials, 30 hard breaths a day in through a handheld breathing trainer lowered systolic pressure by \(InspiratoryTraining.metaAnalysisSystolicDrop.formatted()) mmHg on average (\(InspiratoryTraining.metaAnalysisTrials) trials, \(InspiratoryTraining.metaAnalysisParticipants) people; Li 2023). In the main trial it fell from 135 to 126 in 6 weeks (36 people aged 50-79; Craighead 2021).")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("The trials were small and mostly in people over 50, so the evidence is moderate. It adds to exercise, salt, alcohol and your doctor's plan; it doesn't replace them.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("You'd need a handheld inspiratory muscle trainer with adjustable resistance. Set it hard enough that the last few of 30 breaths are a real effort (the trial used 75% of each person's maximum, measured in a lab). \(InspiratoryTraining.sessionsPerWeek) days a week.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !store.sessions.isEmpty {
                Text("This week: \(week) of \(InspiratoryTraining.sessionsPerWeek) days\(done ? " · today done" : "")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
            }
            NavigationLink {
                InspiratoryTrainingSessionView()
            } label: {
                Text(done ? "Open the log" : "Start today's \(InspiratoryTraining.breathsPerSession) breaths")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.heart)
            .accessibilityIdentifier("imst-start")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }
}

/// One session: tap after each of 30 breaths. It saves itself at 30;
/// "Finish early" keeps a shorter one. Below, the daily log.
struct InspiratoryTrainingSessionView: View {
    @State private var store = InspiratoryTrainingStore.shared
    @State private var count = 0
    @State private var saved = false

    private let target = InspiratoryTraining.breathsPerSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                howTo
                counter
                log
                Text("Stop if you feel dizzy or light-headed. Ask a doctor before starting if you've had a collapsed lung or a burst eardrum, recent ear, eye or chest surgery, or have asthma, COPD or a heart condition (the app's precautions; the trial found it safe and well tolerated in healthy midlife and older adults).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle("Breathing training")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: savePartial)
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardLabel(text: "How", color: Theme.heart)
            Text("Breathe out fully, seal your lips around the mouthpiece, then breathe in as hard and fast as you can. Breathe out gently. Tap once after each breath, and rest a few seconds between breaths when you need to.")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var counter: some View {
        VStack(spacing: 14) {
            Text("\(count) of \(target)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .accessibilityIdentifier("imst-count")
            ProgressView(value: Double(count), total: Double(target))
                .tint(Theme.heart)
            if saved {
                Label("Done for today", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.recoveryHighText)
            } else {
                Button {
                    count = min(target, count + 1)
                    if count == target { finish() }
                } label: {
                    Text("Breath done")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 88)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.heart)
                .sensoryFeedback(.increase, trigger: count)
                .accessibilityIdentifier("imst-breath")
                HStack {
                    Button("Undo") { count = max(0, count - 1) }
                        .disabled(count == 0)
                    Spacer()
                    Button("Finish early") { finish() }
                        .disabled(count == 0)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var log: some View {
        let recent = Array(store.history.prefix(14))
        return VStack(alignment: .leading, spacing: 6) {
            CardLabel(text: "Log", color: Theme.heart)
            Text("This week: \(InspiratoryTraining.fullDaysThisWeek(store.sessions)) of \(InspiratoryTraining.sessionsPerWeek) days · \(InspiratoryTraining.fullDays(store.sessions)) days in all (the trial ran \(InspiratoryTraining.trialWeeks * InspiratoryTraining.sessionsPerWeek) over \(InspiratoryTraining.trialWeeks) weeks)")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(recent) { session in
                HStack {
                    Text(session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    Spacer()
                    Text("\(session.breaths) breaths")
                        .monospacedDigit()
                        .foregroundStyle(session.isComplete ? Theme.primaryText : Theme.secondaryText)
                }
                .font(.subheadline)
                .frame(minHeight: 32)
            }
            if recent.isEmpty {
                Text("Nothing logged yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func finish() {
        guard !saved, count > 0 else { return }
        store.add(breaths: count)
        saved = true
    }

    /// Leaving mid-session keeps what was done.
    private func savePartial() {
        finish()
    }
}
