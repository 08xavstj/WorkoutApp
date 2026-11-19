import SwiftUI

/// The lifting pages, left to right.
enum LiftPage: Hashable {
    case controls, set, rest, heart, exercises
}

/// A lifting workout in progress: Controls | Set | Rest | Heart | Exercises,
/// paged sideways (Apple's controls-left, metrics-middle arrangement; HIG
/// Workouts), so the Digital Crown stays free for the weight on the Set page.
/// Opens on Set. Done moves to Rest once the "Set logged" tick has shown;
/// a rest that ends, Skip or Next set moves back. A page you swiped to
/// yourself (Heart, Exercises) is never taken away: the rest end still taps
/// and the toolbar's chip says "Go". With Reduce Motion, the moves cross-fade
/// instead of sliding.
///
/// The toolbar is the same on every page: elapsed time (or Undo, or the rest
/// left while on another page) and heart rate in its zone colour.
struct LiftPagesView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reduced
    @State private var page: LiftPage = .set

    /// How long the "Set 3 logged" tick shows before the move to Rest (app's choice).
    static let tickSeconds = 0.6
    /// How long "Go" shows on the Rest page before the move back to Set (app's choice).
    static let goSeconds = 3.0

    var body: some View {
        NavigationStack {
            TabView(selection: $page) {
                LiftControlsPage(page: $page)
                    .tag(LiftPage.controls)
                LiftSetPage(isFront: page == .set)
                    .tag(LiftPage.set)
                LiftRestPage(isFront: page == .rest, page: $page)
                    .tag(LiftPage.rest)
                LiftHeartPage()
                    .tag(LiftPage.heart)
                LiftExercisesPage(page: $page)
                    .tag(LiftPage.exercises)
            }
            .tabViewStyle(.page)
            // The height a page can use, for the pages that fit themselves (`FittedPage`).
            .measuresWatchPages()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    leading
                }
                ToolbarItem(placement: .topBarTrailing) {
                    heart
                }
            }
        }
        // A set was logged: after the tick, to the Rest page when there's a rest
        // or a "Reps left?" to answer. A superset's first half has neither, so
        // the Set page stays and shows the partner (no rest between the halves).
        .onChange(of: model.logCount) {
            let count = model.logCount
            Task {
                try? await Task.sleep(for: .seconds(Self.tickSeconds))
                guard model.logCount == count, page == .set,
                      model.restEndsAt != nil || model.pendingRating != nil else { return }
                move(to: .rest)
            }
        }
        // Skipped, ended early or undone on the Rest page: back to the set.
        .onChange(of: model.restEndsAt) { old, new in
            guard old != nil, new == nil, page == .rest, model.restEndedAt == nil, model.pendingRating == nil else { return }
            move(to: .set)
        }
        // The question answered (or folded away) with no rest running: back to the set.
        .onChange(of: model.pendingRating) { old, new in
            guard old != nil, new == nil, page == .rest, model.restEndsAt == nil, model.restEndedAt == nil else { return }
            move(to: .set)
        }
        // The rest ran out: "Go" for a few seconds, then the set. In Always On
        // "Go" stays until the wrist is raised.
        .task(id: model.restEndedAt) {
            guard model.restEndedAt != nil else { return }
            try? await Task.sleep(for: .seconds(Self.goSeconds))
            guard !Task.isCancelled else { return }
            finishGo()
        }
        .onChange(of: reduced) {
            if !reduced, let ended = model.restEndedAt, Date.now.timeIntervalSince(ended) >= Self.goSeconds { finishGo() }
        }
    }

    private func finishGo() {
        guard model.restEndedAt != nil, !reduced else { return }
        if page == .rest { move(to: .set) }
        model.clearRestEnded()
    }

    private func move(to target: LiftPage) {
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { page = target }
        } else {
            withAnimation(.snappy) { page = target }
        }
    }

    /// Undo for a few seconds after Done; the rest left while on another page;
    /// else the workout clock.
    @ViewBuilder
    private var leading: some View {
        if model.canUndo {
            Button {
                model.undoLastSet()
                move(to: .set)
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .accessibilityLabel("Undo the set just logged")
        } else if page != .rest, let ends = model.restEndsAt {
            Label {
                Text(timerInterval: min(model.restStartedAt, ends)...ends, countsDown: true)
            } icon: {
                Image(systemName: "timer")
            }
            .labelStyle(.titleAndIcon)
            .statusFont()
            .foregroundStyle(WatchPalette.lifting)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Rest")
        } else if page != .rest, model.restEndedAt != nil {
            Text("Go")
                .statusFont()
                .foregroundStyle(WatchPalette.recovery)
                .accessibilityLabel("Rest over")
        } else if let start = model.clockTimerStart {
            HStack(spacing: 2) {
                if model.pausedAt != nil {
                    Image(systemName: "pause.fill")
                        .accessibilityLabel("Paused")
                }
                WorkoutClockText(start: start, pausedAt: model.pausedAt)
            }
            .statusFont()
            .foregroundStyle(model.pausedAt == nil ? WatchPalette.strain : .secondary)
            .accessibilityElement(children: .combine)
        }
    }

    private var heart: some View {
        HStack(spacing: 2) {
            Image(systemName: "heart.fill")
                .foregroundStyle(WatchPalette.heart)
            Text(model.heartRate.map { "\(Int($0.rounded()))" } ?? "--")
                .foregroundStyle(model.heartRate == nil ? Color.secondary : WatchPalette.zoneColor(model.tracker.currentZone))
        }
        .statusFont()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.heartRate.map { "Heart rate \(Int($0.rounded()))" } ?? "No heart rate yet")
    }
}
