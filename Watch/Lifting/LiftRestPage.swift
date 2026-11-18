import SwiftUI
import WatchKit

/// The rest between sets, on one page that doesn't scroll
/// (docs/research/watch-app-redesign-2026-11.md §4.4.3):
/// - just after a working set, "Reps left?" with 0-4+ chips (one tap logs
///   RPE = 10 − reps left, Zourdos et al., J Strength Cond Res 2016) and Skip;
///   it folds away after 15 s;
/// - then the countdown ring, −15 / +15, the next set and Next set (double
///   tap starts it early);
/// - when the rest runs out, "Go" with the next set.
///
/// The ring and digits are a `Text` timer and a ring drawn once a second, so
/// Always On keeps them current without sub-second updates; the ring's
/// track hides and its arc dims there.
struct LiftRestPage: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let isFront: Bool
    @Binding var page: LiftPage

    private var scrolls: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if scrolls {
                ScrollView { content }
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let pending = model.pendingRating {
            RepsLeftPrompt(set: pending)
        } else if let ends = model.restEndsAt {
            RestRunning(ends: ends, isFront: isFront && !scrolls, page: $page)
        } else if model.restEndedAt != nil {
            GoCard(isFront: isFront && !scrolls, page: $page)
        } else {
            NoRestCard(isFront: isFront && !scrolls, page: $page)
        }
    }
}

/// "Reps left?" for the set just logged, as 0 / 1 / 2 / 3 / 4+ and Skip, with
/// the rest's time in a small ring beside the question.
private struct RepsLeftPrompt: View {
    @Environment(WatchWorkoutModel.self) private var model
    let set: PendingSet

    /// Reps left 0-4 (4 means "4 or more"), then Skip.
    private static let skipID = -1
    private var chips: [WatchChip] {
        (0...4).map { left in
            WatchChip(id: left, label: left >= 4 ? "4+" : "\(left)",
                      spoken: left >= 4 ? "4 or more reps left" : (left == 1 ? "1 rep left" : "\(left) reps left"))
        } + [WatchChip(id: Self.skipID, label: "Skip", spoken: "Skip the rating")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Reps left?")
                    .font(.headline)
                Spacer(minLength: 4)
                if let ends = model.restEndsAt {
                    MiniRestRing(ends: ends, start: model.restStartedAt, length: model.restLength)
                }
            }
            Spacer(minLength: 0)
            // No "plan" marker: the lifter works to the rep goal, not a reps-left target.
            ChipGrid(chips: chips, perRow: 3, height: 52, tint: WatchPalette.lifting) { id in
                if id == Self.skipID {
                    model.skipRating()
                } else {
                    model.rateSet(set, rpe: Double(10 - id))
                }
            }
        }
    }
}

/// A 44 pt ring with the seconds left inside.
private struct MiniRestRing: View {
    let ends: Date
    let start: Date
    let length: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                RestRingShape(fraction: RestCues.fractionLeft(endsAt: ends, length: length, now: context.date), lineWidth: 4)
                Text(timerInterval: min(start, ends)...ends, countsDown: true)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.9)
            }
            .frame(width: 44, height: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest")
        .accessibilityValue(Text(timerInterval: min(start, ends)...ends, countsDown: true))
    }
}

/// Track and arc; in Always On the track hides and the arc dims to 60 %.
private struct RestRingShape: View {
    let fraction: Double
    var lineWidth: CGFloat = 8
    @Environment(\.isLuminanceReduced) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let width = contrast == .increased ? lineWidth + 2 : lineWidth
        ZStack {
            if !reduced {
                Circle()
                    .stroke(WatchPalette.track, lineWidth: width)
            }
            RingArc(fraction: fraction)
                .stroke(LinearGradient(colors: WatchPalette.liftingColors, startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .opacity(reduced ? 0.6 : 1)
        }
        .padding(width / 2)
    }
}

/// The rest counting down: ring with the digits, −15 / +15, the next set and Next set.
private struct RestRunning: View {
    @Environment(WatchWorkoutModel.self) private var model
    let ends: Date
    let isFront: Bool
    @Binding var page: LiftPage

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                CircleButton(title: "15 seconds less", systemImage: "minus", tint: WatchPalette.lifting, size: 48, showsTitle: false) {
                    model.adjustRest(by: -RestCues.stepSeconds)
                }
                .layoutPriority(1)
                ring
                CircleButton(title: "15 seconds more", systemImage: "plus", tint: WatchPalette.lifting, size: 48, showsTitle: false) {
                    model.adjustRest(by: RestCues.stepSeconds)
                }
                .layoutPriority(1)
            }
            if let next = model.nextSetLine {
                Button {
                    page = .set
                } label: {
                    Text("Next: \(next)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the set, to change it")
            }
            Spacer(minLength: 0)
            PrimaryWideButton(title: "Next set", systemImage: "forward.fill", tint: WatchPalette.recovery,
                              primaryAction: isFront, accessibilityLabel: "Skip the rest and start the next set") {
                model.skipRest()
                page = .set
            }
        }
    }

    private var ring: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                RestRingShape(fraction: RestCues.fractionLeft(endsAt: ends, length: model.restLength, now: context.date))
                VStack(spacing: -2) {
                    Text("Rest")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(timerInterval: min(model.restStartedAt, ends)...ends, countsDown: true)
                        .numeral(.tertiary)
                        .alwaysOnPrimary(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 8)
            }
        }
        // 92 pt on the 46 mm; smaller on the 42 mm so the ±15 circles keep their 48 pt.
        .frame(maxWidth: 92, maxHeight: 92)
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest left")
        .accessibilityValue(Text(timerInterval: min(model.restStartedAt, ends)...ends, countsDown: true))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

/// The rest ran out: "Go" and the next set big.
private struct GoCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    let isFront: Bool
    @Binding var page: LiftPage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Go")
                .numeral(.primary)
                .alwaysOnPrimary(WatchPalette.recovery)
            if let next = model.nextSetLine {
                Text(next)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            PrimaryWideButton(title: "Next set", systemImage: "forward.fill", tint: WatchPalette.recovery,
                              primaryAction: isFront) {
                model.clearRestEnded()
                page = .set
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// No rest running.
private struct NoRestCard: View {
    @Environment(WatchWorkoutModel.self) private var model
    let isFront: Bool
    @Binding var page: LiftPage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No rest running")
                .font(.headline)
            Text("Rest starts when you log a set.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let next = model.nextSetLine {
                Text("Next: \(next)")
                    .font(.footnote)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if model.currentPendingSet != nil {
                PrimaryWideButton(title: "To the set", systemImage: "arrow.right", tint: WatchPalette.lifting,
                                  primaryAction: isFront) {
                    page = .set
                }
            }
        }
    }
}
