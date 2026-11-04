import Foundation

/// Today's strain goal from the weekly plan, recovery and the last few days,
/// so a rest day aims for rest, a missed session moves instead of vanishing,
/// and a rest day that turned into a hard one is followed by an easy day.
///
/// - **Rest days stay light.** The range is 0-25%: about an hour's brisk walk
///   (≈ 20% in `StrainCalculator`'s calibration). Light movement is still good
///   for health (WHO guidelines, Bull et al., Br J Sports Med 2020); hard
///   training is what the plan's rest day is there to space out.
/// - **Plan first, then recovery.** A planned day trains as planned unless
///   recovery is low or the 7-day HRV is below normal, which makes it an easy
///   day: the rule of HRV-guided training (Kiviniemi 2007; Vesterinen 2016;
///   Javaloyes 2019; see `StrainCalculator.targetStrain`).
/// - **A missed session moves to the next free day.** For a given weekly
///   volume, how the sessions fall across the week makes little difference to
///   muscle growth (Schoenfeld, Grgic & Krieger, J Sports Sci 2019,
///   volume-equated meta-analysis), so the session is moved, not lost, and
///   never doubled up on a day that already has one. Only the last two days
///   are looked at: older misses are left alone rather than piled up. One
///   missed session costs little: strength and muscle take weeks without
///   training to fall off (Mujika & Padilla, Sports Med 2000; from memory).
/// - **Hard on a rest day → easy next day.** Rest days lower training
///   monotony, and high load with little variation went with illness in
///   Foster's athletes (Med Sci Sports Exerc 1998); large jumps in load are
///   the risk to avoid (Gabbett, Br J Sports Med 2016). So after an unplanned
///   hard day, the next day is a rest day, or an easy version of a planned
///   session when recovery is fine. The thresholds are app choices.
public enum TrainingDayPlanner {
    public enum Kind: String, Sendable, Equatable {
        /// A planned session, recovery fine.
        case training
        /// A planned session, but easy (low recovery, HRV below normal, or after an extra hard day).
        case easyTraining
        /// A rest day in the plan.
        case rest
        /// A rest day taking a session missed in the last two days.
        case makeUp
        /// Rest after a rest day that turned into a hard one.
        case recovery
    }

    /// One finished day before today.
    public struct PastDay: Sendable, Equatable {
        public var date: Date
        /// What the plan had on that day; nil on a rest day.
        public var plannedFocus: WorkoutFocus?
        public var strain: Double

        public init(date: Date, plannedFocus: WorkoutFocus?, strain: Double) {
            self.date = date
            self.plannedFocus = plannedFocus
            self.strain = strain
        }
    }

    public struct Guidance: Sendable, Equatable {
        public var kind: Kind
        public var strainRange: ClosedRange<Double>
        /// "Rest day", "Training day", "Make-up day"…
        public var title: String
        /// One or two sentences on why.
        public var reason: String
        /// The session for today, if there is one (planned or moved here).
        public var focus: WorkoutFocus?
        /// The missed day a make-up session comes from.
        public var movedFrom: Date?

        public var isRestDay: Bool { kind == .rest || kind == .recovery }
    }

    /// Light movement only: about an hour's brisk walk is ≈ 20%.
    public static let restDayRange: ClosedRange<Double> = 0...25
    /// A day at or above this strain counted as a training day (as `recentTrainingDays`).
    public static let trainingDayStrain = 25.0

    /// Strain that makes a rest day count as a hard training day: the bottom
    /// of your normal training range (`StrainCalculator.targetStrain`), at least 40%.
    public static func hardDayStrain(usualTrainingStrain: Double?) -> Double {
        max(40, StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: usualTrainingStrain).lowerBound)
    }

    /// - Parameters:
    ///   - plannedToday: today's session in the plan, or nil on a rest day.
    ///   - past: finished days before today, oldest first (the last week is plenty).
    ///   - lowRecovery: recovery under 34, or the 7-day HRV below normal.
    public static func guidance(
        plannedToday: WorkoutFocus?,
        past: [PastDay],
        lowRecovery: Bool,
        usualTrainingStrain: Double?,
        calendar: Calendar = .current
    ) -> Guidance {
        let training = StrainCalculator.targetStrain(forRecovery: 50, usualTrainingStrain: usualTrainingStrain)
        let easy = StrainCalculator.targetStrain(forRecovery: 0, usualTrainingStrain: usualTrainingStrain)
        let hard = hardDayStrain(usualTrainingStrain: usualTrainingStrain)
        let days = past.sorted { $0.date < $1.date }

        // Yesterday was a rest day in the plan and ended up a hard training day.
        if let yesterday = days.last, yesterday.plannedFocus == nil, yesterday.strain >= hard {
            if let planned = plannedToday, !lowRecovery {
                return Guidance(
                    kind: .easyTraining, strainRange: easy, title: "Easy day",
                    reason: "Yesterday was a rest day that turned into a hard one, so keep today's \(planned.shortTitle) session short and easy, or move it to your next free day.",
                    focus: planned
                )
            }
            let moved = plannedToday.map { " Your \($0.shortTitle) session can move to your next free day." } ?? ""
            return Guidance(
                kind: .recovery, strainRange: restDayRange, title: "Recovery day",
                reason: "Yesterday was meant to be a rest day and ended up hard, so today is the rest day instead: a walk is plenty, and sleep does the rest.\(moved)"
            )
        }

        if let planned = plannedToday {
            if lowRecovery {
                return Guidance(
                    kind: .easyTraining, strainRange: easy, title: "Easy day",
                    reason: "\(planned.title) is planned, but recovery is low, so the short version or an easy session suits today.",
                    focus: planned
                )
            }
            return Guidance(kind: .training, strainRange: training, title: "Training day",
                            reason: "\(planned.title) is planned today.", focus: planned)
        }

        // A rest day: does it take a session missed in the last two days?
        if let missed = days.suffix(2).last(where: { $0.plannedFocus != nil && $0.strain < trainingDayStrain }),
           let focus = missed.plannedFocus,
           !days.contains(where: { $0.date > missed.date && $0.strain >= trainingDayStrain }) {
            let weekday = missed.date.formatted(.dateTime.weekday(.wide))
            if lowRecovery {
                return Guidance(
                    kind: .rest, strainRange: restDayRange, title: "Rest day",
                    reason: "\(weekday)'s \(focus.shortTitle) session didn't happen, and with recovery low it can wait for a better day. Missing one session costs very little.",
                    movedFrom: missed.date
                )
            }
            return Guidance(
                kind: .makeUp, strainRange: training, title: "Make-up day",
                reason: "\(weekday)'s \(focus.shortTitle) session didn't happen, so today can take it. What builds muscle is the week's total, not the exact day.",
                focus: focus, movedFrom: missed.date
            )
        }

        return Guidance(
            kind: .rest, strainRange: restDayRange, title: "Rest day",
            reason: "Rest day in your plan. Light movement like a walk is good; save hard training for your next session so you come to it recovered."
        )
    }
}
