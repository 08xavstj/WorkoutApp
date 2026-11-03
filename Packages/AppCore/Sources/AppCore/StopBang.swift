import Foundation

/// STOP-Bang: eight yes/no questions that screen for obstructive sleep apnoea
/// (Chung et al., Chest 2016, "STOP-Bang questionnaire: a practical approach
/// to screen for obstructive sleep apnea"). Score 0-2 low risk, 3-4
/// intermediate, 5-8 high. At 3 or more it finds about 85-95% of people with
/// moderate-to-severe apnoea but wrongly flags many without it (specificity
/// about 30-47%; Chung group meta-analyses: Pivetta et al. 2021, Hu/Saripella
/// et al., BMC Anesthesiol 2022), so it's good at ruling out and poor at
/// ruling in. A screen, never a diagnosis: the next step is a sleep study.
/// Lifters with big necks, snorers and anyone with morning headaches or
/// stubborn blood pressure are the people it's for.
public enum StopBang {
    public struct Question: Sendable, Equatable, Identifiable {
        public var id: String
        /// The letter it stands for ("S" of STOP-Bang).
        public var letter: String
        public var text: String
        /// Filled in from the profile (age, sex, BMI) when known.
        public var fromProfile: Bool

        public init(id: String, letter: String, text: String, fromProfile: Bool = false) {
            self.id = id
            self.letter = letter
            self.text = text
            self.fromProfile = fromProfile
        }
    }

    /// Wording from the questionnaire, shortened. Neck: over 40 cm (about 16 in)
    /// in the original; the 2016 update uses 17 in for men and 16 in for women.
    public static let questions: [Question] = [
        Question(id: "snoring", letter: "S", text: "Do you snore loudly (louder than talking, or heard through a closed door)?"),
        Question(id: "tired", letter: "T", text: "Do you often feel tired, fatigued or sleepy during the day?"),
        Question(id: "observed", letter: "O", text: "Has anyone seen you stop breathing or choke/gasp during sleep?"),
        Question(id: "pressure", letter: "P", text: "Do you have, or are you being treated for, high blood pressure?"),
        Question(id: "bmi", letter: "B", text: "Is your BMI more than 35?", fromProfile: true),
        Question(id: "age", letter: "A", text: "Are you older than 50?", fromProfile: true),
        Question(id: "neck", letter: "N", text: "Is your neck bigger than 43 cm (17 in) if male, or 41 cm (16 in) if female?"),
        Question(id: "gender", letter: "G", text: "Are you male?", fromProfile: true),
    ]

    public enum Risk: String, Sendable, Equatable {
        case low = "Low risk"
        case intermediate = "Intermediate risk"
        case high = "High risk"
    }

    /// Number of "yes" answers.
    public static func score(_ answers: [String: Bool]) -> Int {
        questions.filter { answers[$0.id] == true }.count
    }

    /// Chung 2016 bands: 0-2 low, 3-4 intermediate, 5-8 high.
    public static func risk(score: Int) -> Risk {
        if score >= 5 { return .high }
        if score >= 3 { return .intermediate }
        return .low
    }

    /// "Talk to a doctor about a sleep study" from intermediate up; a screen, not a diagnosis.
    public static func advice(_ risk: Risk) -> String {
        switch risk {
        case .low:
            return "Low risk on this screen. It rules apnoea out fairly well but not completely; redo it in a year or if you start snoring, wake unrefreshed or your blood pressure climbs."
        case .intermediate:
            return "Intermediate risk. Worth talking to a doctor about a sleep study: the screen catches most moderate-to-severe apnoea but also flags many people who don't have it, so only a study can tell. Untreated apnoea pushes up blood pressure and ruins recovery."
        case .high:
            return "High risk. Talk to a doctor about a sleep study soon. This is a screen, not a diagnosis, but at this score apnoea is likely enough that testing is the sensible next step; treating it improves sleep, blood pressure and daytime energy."
        }
    }

    /// Profile answers the app can fill in: BMI over 35, age over 50, male.
    public static func profileAnswers(age: Int, sex: BiologicalSex, bmi: Double?) -> [String: Bool] {
        var answers: [String: Bool] = ["age": age > 50, "gender": sex == .male]
        if let bmi, bmi > 10 { answers["bmi"] = bmi > 35 }
        return answers
    }

    // MARK: Cadence

    /// Re-ask yearly, or sooner when home blood pressure turns elevated
    /// (docs/research/health-metrics.md, section 5: "re-asked yearly or when
    /// BP becomes elevated").
    public static let intervalDays = 365

    public static func nextDue(lastAnswered: Date?, calendar: Calendar = .current) -> Date? {
        guard let lastAnswered else { return nil }
        return calendar.date(byAdding: .day, value: intervalDays, to: calendar.startOfDay(for: lastAnswered))
    }

    /// True with no answers yet, after a year, or when blood pressure is now
    /// elevated and the last answer to the pressure question was "no".
    public static func isDue(lastAnswered: Date?, lastAnswers: [String: Bool] = [:], bloodPressureElevated: Bool = false,
                             now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let due = nextDue(lastAnswered: lastAnswered, calendar: calendar) else { return true }
        if bloodPressureElevated && lastAnswers["pressure"] != true { return true }
        return calendar.startOfDay(for: now) >= due
    }
}
