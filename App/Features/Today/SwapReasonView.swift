import SwiftUI
import AppCore

/// What the builder does after "Why a different workout?".
enum SwapOutcome: Equatable {
    /// Start the session as built.
    case start
    /// Rebuild at this length first (the short version), then the user starts
    /// it. The answer isn't saved yet: the builder saves it when that session
    /// starts and drops it if the builder is closed (`PendingSwap`).
    case useMinutes(Int, answer: PendingSwap?)
    /// Open the pain log before starting.
    case openPainLog
}

/// A "Why a different workout?" answer that isn't saved yet.
struct PendingSwap: Equatable {
    var planned: WorkoutFocus?
    var chosen: WorkoutFocus
    var reason: AdaptiveWeek.Reason?
    var soreAreas: [AdaptiveWeek.Area]

    func record(in plans: WeeklyPlanStore) {
        plans.recordSwap(planned: planned, chosen: chosen, reason: reason, soreAreas: soreAreas)
    }
}

/// "Why a different workout?": one tap when the user picks a different
/// session than the week's next one (`AdaptiveWeek`), saved with the day
/// (`WeeklyPlanStore.recordSwap`). The answer moves the week around them:
/// sore muscles move sessions that load them later (DOMS peaks 24-72 h and
/// lowers strength while it lasts: Cheung, Hume & Maxwell, Sports Med 2003),
/// tired or short on time offers the short version, equipment busy keeps the
/// planned session for tomorrow, pain opens the pain log, and a preference just
/// swaps the order. Always optional and never a judgement (autonomy support:
/// Teixeira et al. 2012; Ntoumanis et al. 2021).
struct SwapReasonView: View {
    /// The session that was next, if any.
    let planned: WorkoutFocus?
    let chosen: WorkoutFocus
    /// Asked before starting (the builder) rather than after the session.
    var beforeStart = true
    /// The short version's length, offered for tired or short on time (before starting only).
    var shortMinutes: Int?
    let onDone: (SwapOutcome) -> Void

    @Environment(WeeklyPlanStore.self) private var plans
    @State private var step: Step = .reasons
    @State private var areas: [AdaptiveWeek.Area] = []
    /// An answer was given (the toolbar then says Done, not Skip).
    @State private var recorded = false
    /// Before starting, the answer waits here and is saved only when a session
    /// starts or the pain log opens; the short version hands it to the builder,
    /// which saves it on start. Backing out of the builder logs no swap for a
    /// session that never happened.
    @State private var pending: PendingSwap?

    private enum Step: Equatable {
        case reasons
        case soreAreas
        case shortOffer(Int)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(headline)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                switch step {
                case .reasons:
                    SwapReasonList(choose: choose)
                    // Skip in thumb reach too, not only in the toolbar.
                    Button {
                        save(nil, then: .start)
                    } label: {
                        Text(beforeStart ? "Skip and start" : "Skip")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Theme.cardRaised, in: .capsule)
                    }
                    .buttonStyle(.plain)
                case .soreAreas:
                    SoreAreaPicker(areas: $areas) { save(.sore, areas: areas, then: .start) }
                case .shortOffer(let minutes):
                    ShortVersionOffer(minutes: minutes, chosen: chosen,
                                      useShort: { useShort(minutes) }, startAsBuilt: { finish(.start) })
                }
            }
            .padding()
        }
        .lockedToScreenWidth()
        .background(Theme.background)
        .navigationTitle("Why a different workout?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(recorded ? "Done" : "Skip") {
                    if !recorded { save(nil, then: .start) } else { finish(.start) }
                }
            }
        }
    }

    private var headline: String {
        guard let planned else { return "What made you pick \(chosen.shortTitle) today? Optional, one tap." }
        if beforeStart {
            return "\(planned.shortTitle) is next in your week. What's behind \(chosen.shortTitle) today? Optional: the week moves around your answer."
        }
        return "You did \(chosen.shortTitle) and \(planned.shortTitle) was next. What made you switch? Optional: the week moves around your answer."
    }

    private func choose(_ reason: AdaptiveWeek.Reason) {
        switch reason {
        case .sore:
            // Start with the muscles the skipped session would have loaded.
            if areas.isEmpty, let planned {
                let skipped = AdaptiveWeek.loads(planned).subtracting(AdaptiveWeek.loads(chosen))
                areas = AdaptiveWeek.promptAreas.filter { skipped.contains($0) }
            }
            step = .soreAreas
        case .tired, .shortOnTime:
            if beforeStart, let shortMinutes {
                save(reason, then: nil)
                step = .shortOffer(shortMinutes)
            } else {
                save(reason, then: .start)
            }
        case .pain:
            save(reason, then: .openPainLog)
        case .equipment, .prefer:
            save(reason, then: .start)
        }
    }

    private func save(_ reason: AdaptiveWeek.Reason?, areas: [AdaptiveWeek.Area] = [], then outcome: SwapOutcome?) {
        recorded = true
        if beforeStart {
            pending = PendingSwap(planned: planned, chosen: chosen, reason: reason, soreAreas: areas)
            if let outcome { finish(outcome) }
            return
        }
        plans.recordSwap(planned: planned, chosen: chosen, reason: reason, soreAreas: areas)
        if let outcome { onDone(outcome) }
    }

    /// Goes on with the builder, saving a waiting answer first.
    private func finish(_ outcome: SwapOutcome) {
        if let pending {
            pending.record(in: plans)
            self.pending = nil
        }
        onDone(outcome)
    }

    /// The short version: nothing starts yet, so the answer goes to the
    /// builder unsaved (it saves it once the short session starts).
    private func useShort(_ minutes: Int) {
        let answer = pending
        pending = nil
        onDone(.useMinutes(minutes, answer: answer))
    }
}

/// The six one-tap reasons.
private struct SwapReasonList: View {
    let choose: (AdaptiveWeek.Reason) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(AdaptiveWeek.Reason.allCases) { reason in
                Button { choose(reason) } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: reason.systemImage, color: Theme.lifting, size: 36)
                        Text(reason.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// "Which muscles?" for Sore muscles.
private struct SoreAreaPicker: View {
    @Binding var areas: [AdaptiveWeek.Area]
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which muscles?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ChipFlow(options: AdaptiveWeek.promptAreas, selection: $areas, label: \.rawValue, color: Theme.lifting)
            // Cheung, Hume & Maxwell, Sports Med 2003. How long a report counts is an app choice.
            Text("Soreness peaks 1-3 days after training. Mild soreness is fine to train through, but lifts feel weaker, so sessions that load sore muscles move later this week.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: save) {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(areas.isEmpty)
            .opacity(areas.isEmpty ? 0.5 : 1)
        }
    }
}

/// Tired or short on time, before starting: the short version or as built.
private struct ShortVersionOffer: View {
    let minutes: Int
    let chosen: WorkoutFocus
    let useShort: () -> Void
    let startAsBuilt: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The minimum version keeps the habit (docs/research/behaviour-change.md rec. 7).
            Text("A short session still counts. Want the \(minutes)-minute version?")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: useShort) {
                Text("Short version · \(minutes) min")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
            }
            .buttonStyle(.plain)
            Button(action: startAsBuilt) {
                Text("Start \(chosen.shortTitle) as built")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.cardRaised, in: .capsule)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - After the fact (Today, This week)

/// The question asked once after a session that wasn't the one suggested
/// (`WeeklyPlanStore.unansweredSwap`), for sessions started from anywhere.
struct SwapReasonSheet: View {
    let planned: WorkoutFocus
    let chosen: WorkoutFocus

    @Environment(\.dismiss) private var dismiss
    @State private var showingPainLog = false
    @State private var painLog = PainLogStore.shared

    var body: some View {
        NavigationStack {
            SwapReasonView(planned: planned, chosen: chosen, beforeStart: false) { outcome in
                if outcome == .openPainLog { showingPainLog = true } else { dismiss() }
            }
            .navigationDestination(isPresented: $showingPainLog) {
                PainLogView(current: PainGuard.active(painLog.reports, today: .now), exclusions: ExerciseExclusions.shared) { changed in
                    painLog.log(changed)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.background)
    }
}

/// "Upper instead of Lower today · Why?" opening `SwapReasonSheet`.
struct SwapQuestionButton: View {
    let planned: WorkoutFocus
    let chosen: WorkoutFocus

    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "arrow.triangle.swap", color: Theme.lifting, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chosen.shortTitle) instead of \(planned.shortTitle) today")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text("Why the switch? One tap, and the week adapts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Asks why, so the week can adapt")
        .sheet(isPresented: $showing) {
            SwapReasonSheet(planned: planned, chosen: chosen)
        }
    }
}

// MARK: - Builder gate

extension View {
    /// Pushes "Why a different workout?" inside the builder's navigation stack
    /// (never a sheet on a sheet). `onOutcome` runs once it's answered or skipped.
    func swapReasonGate(isPresented: Binding<Bool>, planned: WorkoutFocus?, chosen: WorkoutFocus, shortMinutes: Int?,
                        onOutcome: @escaping (SwapOutcome) -> Void) -> some View {
        navigationDestination(isPresented: isPresented) {
            SwapReasonView(planned: planned, chosen: chosen, beforeStart: true, shortMinutes: shortMinutes) { outcome in
                isPresented.wrappedValue = false
                onOutcome(outcome)
            }
        }
    }
}
