import Foundation

/// What the research says about common sports and health supplements: what
/// each is for, how strong the evidence is, the dose and timing the trials
/// used, what to expect, cautions, and how it shows up in the app's own data.
///
/// Evidence grades follow the IOC consensus on dietary supplements (Maughan
/// et al., Br J Sports Med 2018;52:439-55) and the ISSN position stands:
/// `strong` = several good trials and meta-analyses agree; `moderate` = a
/// consistent but small or population-specific effect; `weak` = a few small
/// trials, mixed results or industry-funded only; `none` = no benefit shown in
/// people who aren't deficient. Each entry lists its sources.
///
/// Information, not advice: the app never says "take X". The UI shows every
/// grade next to its claim. Shape mirrors `MedicationKnowledge` so
/// `MedicationsModel` can match the user's list the same way.
public enum SupplementKnowledge {
    public enum Evidence: String, Sendable, Codable, CaseIterable, Comparable {
        case none, weak, moderate, strong

        public var label: String {
            switch self {
            case .strong: "Strong evidence"
            case .moderate: "Moderate evidence"
            case .weak: "Weak evidence"
            case .none: "No benefit shown"
            }
        }

        private var rank: Int {
            switch self {
            case .none: 0
            case .weak: 1
            case .moderate: 2
            case .strong: 3
            }
        }

        public static func < (lhs: Evidence, rhs: Evidence) -> Bool { lhs.rank < rhs.rank }
    }

    /// The goal a supplement is browsed under.
    public enum Category: String, Sendable, CaseIterable, Identifiable {
        case strengthAndMuscle = "Strength & muscle"
        case endurance = "Endurance"
        case sleepAndStress = "Sleep & stress"
        case recovery = "Recovery"
        case health = "Health"

        public var id: String { rawValue }
    }

    /// One thing a supplement is taken for, with its own grade: ashwagandha is
    /// moderate for stress and weak for strength, so one grade would mislead.
    public struct Claim: Sendable, Equatable, Identifiable {
        public var purpose: String
        public var evidence: Evidence
        public var summary: String
        public var id: String { purpose }
    }

    public struct Entry: Sendable, Identifiable, Equatable {
        public var id: String
        public var name: String
        /// Lowercased names, brands and aliases that identify it. Single words
        /// match whole words; phrases match in order ("tart cherry").
        public var names: [String]
        public var category: Category
        public var claims: [Claim]
        /// Typical dose in trials, e.g. "3-5 g a day".
        public var dose: String
        /// When to take it and whether timing matters.
        public var timing: String
        /// What to expect and when.
        public var expect: String
        public var cautions: [String]
        /// How it shows up in this app's data (weight trend, caffeine cut-off, sleep).
        public var dataNotes: [String]
        public var sources: [String]

        /// The best-supported claim's grade; shown on browse rows.
        public var evidence: Evidence { claims.map(\.evidence).max() ?? Evidence.none }
        /// "5 g creatine daily; timing doesn't matter much".
        public var doseLine: String { "\(dose); \(timing)" }
    }

    /// The entry a logged name belongs to, matched on generic or brand name.
    /// Keeps short tokens so "KSM-66", "D3" and "ZMA" match.
    public static func match(_ name: String) -> Entry? {
        let tokens = name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        let joined = " " + tokens.joined(separator: " ") + " "
        return entries.first { entry in
            entry.names.contains { alias in
                alias.contains(" ") ? joined.contains(" \(alias) ") : tokens.contains(alias)
            }
        }
    }

    public static func entries(in category: Category) -> [Entry] {
        entries.filter { $0.category == category }
    }

    private static func c(_ purpose: String, _ evidence: Evidence, _ summary: String) -> Claim {
        Claim(purpose: purpose, evidence: evidence, summary: summary)
    }

    static let ioc = "Maughan R.J. et al. Br J Sports Med 2018;52:439-55 (IOC consensus statement on dietary supplements and the high-performance athlete)."

    public static let entries: [Entry] = strengthEntries + enduranceEntries + sleepEntries + recoveryEntries + healthEntries

    // MARK: Strength & muscle

    static let strengthEntries: [Entry] = [
        Entry(
            id: "creatine", name: "Creatine monohydrate",
            names: ["creatine", "creapure", "monohydrate"],
            category: .strengthAndMuscle,
            claims: [
                c("Strength and lean mass", .strong, "The best-studied sports supplement: a few percent more strength and about 1 kg more lean mass over a training block, in hundreds of trials (ISSN 2017; Delpino 2022 meta-analysis)."),
                c("Repeated sprints and high-intensity work", .strong, "More work in repeated short efforts; little effect on long steady endurance (ISSN 2017)."),
            ],
            dose: "3-5 g a day, rest days included",
            timing: "timing doesn't matter much; no loading phase needed (3-5 g a day fills muscles in 3-4 weeks)",
            expect: "Scale weight up 0.5-2 kg in the first weeks (water in muscle, not fat); strength gains build over 4-8 weeks of training.",
            cautions: [
                "Safe in healthy adults at these doses in long-term trials; ask your doctor first if you have kidney disease.",
                "Raises creatinine on blood tests without harming healthy kidneys; tell your doctor before a kidney test.",
            ],
            dataNotes: [
                "Your weight trend already allows for creatine's water weight when the entry is in your list (the first 4 weeks).",
                "Judge fat loss by waist and photos for the first month.",
            ],
            sources: [
                "Kreider R.B. et al. J Int Soc Sports Nutr 2017;14:18 (ISSN position stand on creatine).",
                "Antonio J. et al. J Int Soc Sports Nutr 2021;18:13 (common questions and misconceptions about creatine).",
                "Delpino F.M. et al. Nutrition 2022;103-104:111791 (creatine and lean mass with resistance training, meta-analysis).",
                ioc,
            ]
        ),
        Entry(
            id: "protein", name: "Protein powder (whey, casein, plant)",
            names: ["whey", "casein", "protein", "pea protein", "soy protein", "protein powder", "protein shake"],
            category: .strengthAndMuscle,
            claims: [
                c("Muscle and strength with training", .strong, "Protein supplements add to muscle and strength gains when total protein would otherwise fall short of about 1.6 g/kg a day; above that, more doesn't help (Morton 2018 meta-analysis; ISSN 2017)."),
            ],
            dose: "20-40 g a serving, to reach 1.6-2.2 g/kg a day in total",
            timing: "spread over 3-4 meals; the post-workout window matters less than the daily total",
            expect: "It's food, not a drug: gains come from training, and a shake only fills the gap your meals leave.",
            cautions: ["Whey is dairy; use a plant blend if lactose bothers you. Check for third-party testing (Informed Sport, NSF) for contaminants."],
            dataNotes: ["Your protein target already accounts for your goal and any medication that raises it; a shake counts toward it in your food log."],
            sources: [
                "Jäger R. et al. J Int Soc Sports Nutr 2017;14:20 (ISSN position stand on protein and exercise).",
                "Morton R.W. et al. Br J Sports Med 2018;52:376-84 (protein supplementation and resistance training, meta-analysis of 49 trials).",
                ioc,
            ]
        ),
        Entry(
            id: "hmb", name: "HMB",
            names: ["hmb", "hydroxymethylbutyrate"],
            category: .strengthAndMuscle,
            claims: [
                c("Muscle and strength in trained lifters", .weak, "Small effects in beginners and older adults; in trained young adults a meta-analysis found no gain in lean mass or strength (Jakubowski 2020)."),
            ],
            dose: "3 g a day in trials",
            timing: "with meals; 1-2 weeks to build up",
            expect: "Little or nothing if you already lift and eat enough protein.",
            cautions: ["Appears safe at 3 g a day; the extreme gains in a few early trials have not been repeated."],
            dataNotes: ["Nothing in your data changes with HMB."],
            sources: [
                "Wilson J.M. et al. J Int Soc Sports Nutr 2013;10:6 (ISSN position stand on HMB).",
                "Jakubowski J.S. et al. Nutrients 2020;12:1523 (HMB and resistance training in young adults, meta-analysis).",
            ]
        ),
        Entry(
            id: "bcaa", name: "BCAAs",
            names: ["bcaa", "bcaas", "branched chain", "leucine"],
            category: .strengthAndMuscle,
            claims: [
                c("Muscle growth", .none, "No human trial shows BCAAs alone build muscle when protein intake is adequate; a full protein does the job (Wolfe 2017)."),
                c("Soreness", .weak, "Small, inconsistent effects on soreness in a few trials."),
            ],
            dose: "5-10 g is typical",
            timing: "around training",
            expect: "Nothing you wouldn't get from a protein-rich meal or shake.",
            cautions: ["Safe, but money better spent on protein."],
            dataNotes: ["Counts for almost no protein in your food log (a BCAA scoop is not a serving of protein)."],
            sources: [
                "Wolfe R.R. J Int Soc Sports Nutr 2017;14:30 (BCAAs and muscle protein synthesis in humans: myth or reality?).",
                "Jäger R. et al. J Int Soc Sports Nutr 2017;14:20 (ISSN protein position stand).",
            ]
        ),
        Entry(
            id: "testosteroneBooster", name: "Testosterone boosters (tribulus, fenugreek)",
            names: ["tribulus", "fenugreek", "testofen", "test booster", "testosterone booster", "t booster", "d aspartic acid", "daa"],
            category: .strengthAndMuscle,
            claims: [
                c("Testosterone and muscle", .none, "Tribulus does not raise testosterone in men (Qureshi 2014; 2025 systematic review). Fenugreek extracts show a small rise in total testosterone (SMD about 0.3) with no proven effect on muscle or strength (Isenmann 2023 meta-analysis). Multi-ingredient boosters have no good trials."),
            ],
            dose: "varies by product",
            timing: "n/a",
            expect: "No measurable change in strength or body composition in the trials.",
            cautions: ["Proprietary blends hide doses; some products have been found contaminated with banned substances. Fenugreek can lower blood sugar and interact with warfarin."],
            dataNotes: ["Nothing in your data changes."],
            sources: [
                "Qureshi A. et al. J Diet Suppl 2014;11:64-79 (Tribulus terrestris and testosterone, systematic review).",
                "Isenmann E. et al. Int J Sports Med 2023 (fenugreek and testosterone, meta-analysis of 7 trials).",
                "Clemesha C.G. et al. World J Mens Health 2020;38:115-22 (ingredients of 'T boosters' vs the evidence).",
                ioc,
            ]
        ),
        Entry(
            id: "ecdysterone", name: "Turkesterone and ecdysterone",
            names: ["turkesterone", "ecdysterone", "ecdysteroids", "ajuga", "ajuga turkestanica"],
            category: .strengthAndMuscle,
            claims: [
                c("Muscle and strength", .weak, "One 10-week trial (Isenmann 2019) found more strength and lean mass, but the product tested held a fraction of its labelled ecdysterone and the result hasn't been repeated. Turkesterone has no human trials at all."),
            ],
            dose: "trials used about 12 mg a day of ecdysterone from spinach extract; products claim far more",
            timing: "n/a",
            expect: "Unknown; treat any gains as training.",
            cautions: [
                "Label accuracy is poor: analyses found most products hold a small fraction of the labelled dose, and some ecdysterone products contained a banned anabolic steroid.",
                "WADA has ecdysterone on its monitoring list.",
            ],
            dataNotes: ["Nothing in your data changes."],
            sources: [
                "Isenmann E. et al. Arch Toxicol 2019;93:1807-16 (ecdysterone supplementation in humans, 10-week trial; underdosed product).",
                "Ambrosio G. et al. (2021) and later HPLC analyses of ecdysterone supplements: contents well below label, a fifth with anabolic steroids.",
                ioc,
            ]
        ),
    ]

    // MARK: Endurance

    static let enduranceEntries: [Entry] = [
        Entry(
            id: "caffeine", name: "Caffeine",
            names: ["caffeine", "coffee", "caffeine pills", "energy drink"],
            category: .endurance,
            claims: [
                c("Endurance, strength and power", .strong, "3-6 mg/kg about an hour before improves endurance (2-4%), sprint, strength and power in dozens of trials (ISSN 2021; IOC 2018). Lower doses (around 2 mg/kg or a coffee) help too."),
            ],
            dose: "3-6 mg/kg (about 200-400 mg for most people); 1-3 mg/kg helps and sits easier",
            timing: "30-60 minutes before training; skip within your caffeine cut-off before bed",
            expect: "Effort feels easier the same day; more jittery with higher doses. Regular users still benefit, slightly less.",
            cautions: [
                "Above about 9 mg/kg: nausea, racing heart, no extra benefit. Avoid in pregnancy beyond 200 mg a day.",
                "Cuts sleep by about 45 minutes when taken within 8-9 hours of bed, more with bigger doses (Gardiner 2023).",
            ],
            dataNotes: [
                "Your caffeine cut-off in Habits already moves with your bedtime and dose; a pre-workout dose counts toward it.",
                "Raises heart rate and lowers HRV for hours, so an evening dose can read as poorer recovery.",
            ],
            sources: [
                "Guest N.S. et al. J Int Soc Sports Nutr 2021;18:1 (ISSN position stand on caffeine and exercise).",
                "Gardiner C. et al. Sleep Med Rev 2023;69:101764 (caffeine and sleep, meta-analysis).",
                ioc,
            ]
        ),
        Entry(
            id: "betaAlanine", name: "Beta-alanine",
            names: ["beta alanine", "carnosyn", "betaalanine"],
            category: .endurance,
            claims: [
                c("Efforts of 1-10 minutes", .moderate, "Buffers muscle acid; a small overall effect (ES 0.18) in 40 trials, largest in 0.5-10 minute efforts and with sodium bicarbonate (Saunders 2017; ISSN 2015)."),
                c("Long endurance or single lifts", .none, "No effect on efforts under a minute or over 10 minutes."),
            ],
            dose: "3.2-6.4 g a day, split into 0.8-1.6 g doses",
            timing: "any time of day; takes 2-4 weeks to load, and timing around training doesn't matter",
            expect: "Tingling skin (paraesthesia) with doses above about 800 mg at once; harmless. Benefit shows after 4 weeks.",
            cautions: ["The tingle is the only common side effect; split doses or a slow-release form avoid it."],
            dataNotes: ["Nothing in your data changes."],
            sources: [
                "Trexler E.T. et al. J Int Soc Sports Nutr 2015;12:30 (ISSN position stand on beta-alanine).",
                "Saunders B. et al. Br J Sports Med 2017;51:658-69 (beta-alanine and exercise capacity, meta-analysis of 40 studies).",
                ioc,
            ]
        ),
        Entry(
            id: "citrulline", name: "Citrulline malate",
            names: ["citrulline", "citrulline malate", "l citrulline"],
            category: .endurance,
            claims: [
                c("Reps to failure and strength endurance", .weak, "A few more reps in some trials, none in others; pooled effects are small and some reviews find publication bias (Trexler 2019; Vårvik 2021)."),
                c("Endurance performance", .weak, "Mixed results; not enough to count on."),
            ],
            dose: "6-8 g citrulline malate (about 3-4 g citrulline)",
            timing: "about 60 minutes before training",
            expect: "At most an extra rep or two late in a session.",
            cautions: ["Well tolerated; stomach upset in a few people."],
            dataNotes: ["Nothing in your data changes."],
            sources: [
                "Trexler E.T. et al. Sports Med 2019;49:707-18 (acute citrulline and high-intensity strength and power, meta-analysis).",
                "Vårvik F.T. et al. Int J Sport Nutr Exerc Metab 2021;31:350-8 (citrulline malate and repetitions to failure, meta-analysis).",
                "Gough L.A. et al. Eur J Sport Sci 2021 (critical review of citrulline malate).",
            ]
        ),
        Entry(
            id: "nitrate", name: "Beetroot juice (nitrate)",
            names: ["beetroot", "beet juice", "beet", "nitrate", "beet it"],
            category: .endurance,
            claims: [
                c("Endurance and time to exhaustion", .moderate, "A small gain (d about 0.17) across 80 studies, clearest in less-trained people and efforts of 3-30 minutes; well-trained athletes gain less (Senefeld 2020; IOC 2018)."),
            ],
            dose: "6-8 mmol nitrate (about 300-500 mg; one or two 70 ml beetroot shots)",
            timing: "2-3 hours before; several days in a row works better",
            expect: "Pink urine. A small edge in hard efforts of a few minutes to half an hour.",
            cautions: ["Don't use antibacterial mouthwash the same day (it blocks the conversion). Fine from vegetables too: spinach, rocket, beetroot."],
            dataNotes: ["Lowers blood pressure a few mmHg, so cuff readings may read lower on beetroot days."],
            sources: [
                "Senefeld J.W. et al. Med Sci Sports Exerc 2020;52:2250-61 (nitrate and exercise performance, meta-analysis of 80 studies).",
                "McMahon N.F. et al. Sports Med 2017;47:735-56 (nitrate and endurance, meta-analysis).",
                ioc,
            ]
        ),
        Entry(
            id: "preWorkout", name: "Pre-workout blends",
            names: ["pre workout", "preworkout", "pre wo", "c4", "pre jym"],
            category: .endurance,
            claims: [
                c("Energy and a few more reps", .moderate, "The benefit is the caffeine, with beta-alanine and citrulline adding a little; each part has the same evidence as on its own (Harty 2018)."),
            ],
            dose: "check the caffeine: most hold 150-350 mg a scoop",
            timing: "30-60 minutes before; never inside your caffeine cut-off",
            expect: "Alertness and a tingle; strength gains are from training.",
            cautions: [
                "Proprietary blends hide doses; some products have contained banned or unlisted stimulants.",
                "Safety trials are short (under 8 weeks). Avoid stacking with other caffeine.",
            ],
            dataNotes: ["The caffeine counts toward your cut-off and can keep heart rate up and HRV down into the evening."],
            sources: [
                "Harty P.S. et al. J Int Soc Sports Nutr 2018;15:41 (multi-ingredient pre-workout supplements: safety and performance, review).",
                "Guest N.S. et al. J Int Soc Sports Nutr 2021;18:1 (ISSN caffeine position stand).",
            ]
        ),
        Entry(
            id: "electrolytes", name: "Electrolytes",
            names: ["electrolytes", "electrolyte", "lmnt", "liquid iv", "hydration tabs", "salt tabs", "nuun"],
            category: .endurance,
            claims: [
                c("Long or hot sessions", .moderate, "Sodium with fluid helps you keep drinking and holds plasma volume in sessions over about 2 hours or with heavy sweating; cramps are not reliably prevented (ACSM 2007; Baker 2017)."),
                c("Everyday or short sessions", .none, "Normal meals replace what a short workout loses."),
            ],
            dose: "300-600 mg sodium per hour of heavy sweating, with fluid",
            timing: "during and after long or hot sessions only",
            expect: "Less dizziness and better drinking in long hot sessions; nothing for a 45-minute lift.",
            cautions: ["Daily use adds to sodium already above most people's target; skip on rest days."],
            dataNotes: ["Sodium from electrolyte drinks shows up in your food log if you log them; your vitamins and minerals page flags days over 2,300 mg."],
            sources: [
                "Sawka M.N. et al. Med Sci Sports Exerc 2007;39:377-90 (ACSM position stand on exercise and fluid replacement).",
                "Baker L.B. Sports Med 2017;47(Suppl 1):111-28 (sweat sodium losses in athletes).",
            ]
        ),
    ]

    // MARK: Sleep & stress

    static let sleepEntries: [Entry] = [
        Entry(
            id: "ashwagandha", name: "Ashwagandha",
            names: ["ashwagandha", "withania", "ksm", "ksm 66", "ksm66", "sensoril", "shoden", "ashwaganda"],
            category: .sleepAndStress,
            claims: [
                c("Stress and anxiety", .moderate, "Pooled RCTs show lower perceived stress and anxiety and lower cortisol, but the trials are small, short (6-12 weeks) and often funded by extract makers; certainty was rated low (Akhgarjand 2022; Chandrasekhar 2012)."),
                c("Sleep", .moderate, "A modest improvement in sleep quality (SMD about -0.6), clearer with 600 mg a day for 8 weeks or more and in people with insomnia (Cheah 2021)."),
                c("Strength and muscle", .weak, "Two 8-12 week RCTs in men who lift found more bench-press strength (Wankhede 2015, 600 mg KSM-66; Ziegenfuss 2018, 500 mg Sensoril); both were small and extract-maker funded. A Bayesian meta-analysis pooled gains in performance (Bonilla 2021) but called for better trials."),
            ],
            dose: "300-600 mg a day of a root extract (KSM-66) or 250-500 mg (Sensoril, root and leaf)",
            timing: "evening if for sleep; morning or split if for stress; effects build over 4-8 weeks",
            expect: "Calmer and better sleep within a few weeks if it works for you; any strength change is small and slow.",
            cautions: [
                "Liver injury has been reported: case series rated probable causality (Björnsson 2020; Philips 2023), and in 2023-2025 the Dutch (Lareb), German (BfR) and WHO (VigiBase) pharmacovigilance systems recorded signals. Rare, but stop and see a doctor if you get dark urine, yellow skin or eyes, or stomach pain.",
                "Not for pregnancy or breastfeeding (Denmark bans it), thyroid conditions (it can raise thyroid hormones), or with sedatives and immunosuppressants. Some people feel drowsy or get an upset stomach.",
                "Trial extracts were standardised; many products aren't, so dose on the label may not match.",
            ],
            dataNotes: [
                "If you take it for sleep, watch your sleep score and HRV over 4 weeks rather than night by night.",
                "Lower cortisol does not change your recovery score directly.",
            ],
            sources: [
                "Akhgarjand C. et al. Phytother Res 2022;36:4115-24 (ashwagandha for anxiety and stress, meta-analysis of 12 RCTs; low certainty).",
                "Cheah K.L. et al. PLoS One 2021;16:e0257843 (ashwagandha and sleep, meta-analysis).",
                "Bonilla D.A. et al. J Funct Morphol Kinesiol 2021;6:20 (ashwagandha and physical performance, Bayesian meta-analysis).",
                "Wankhede S. et al. J Int Soc Sports Nutr 2015;12:43 (KSM-66 and resistance training, RCT); Ziegenfuss T.N. et al. Nutrients 2018;10:1807 (Sensoril STAR trial).",
                "Chandrasekhar K. et al. Indian J Psychol Med 2012;34:255-62 (KSM-66 600 mg, stress and cortisol, RCT).",
                "Björnsson H.K. et al. Liver Int 2020;40:825-9 (ashwagandha-induced liver injury, case series); Philips C.A. et al. Pharmaceuticals 2023 (RUCAM-assessed cases); Lareb (Netherlands) 2023-2025 and BfR (Germany) 2024 pharmacovigilance notices.",
            ]
        ),
        Entry(
            id: "melatonin", name: "Melatonin",
            names: ["melatonin", "circadin"],
            category: .sleepAndStress,
            claims: [
                c("Falling asleep sooner", .moderate, "Falls asleep about 7 minutes sooner and sleeps about 8 minutes longer on average, with slightly better sleep quality; small but consistent (Ferracioli-Oda 2013). Most useful for jet lag and shifted bedtimes."),
            ],
            dose: "0.5-3 mg; more isn't better",
            timing: "30-60 minutes before the bedtime you want; earlier (afternoon) for shifting your clock",
            expect: "A small nudge toward sleep, not a sleeping pill. Grogginess next morning with higher doses.",
            cautions: [
                "Over-the-counter products vary widely from the label (one analysis found 83% less to nearly five times the stated dose). A prescription in the UK/EU; check interactions with blood thinners, blood pressure and diabetes medicines.",
                "Not well studied in pregnancy or for long-term use in children.",
            ],
            dataNotes: ["Your bedtime window and sleep onset in the sleep score are the thing to watch; give it a week."],
            sources: [
                "Ferracioli-Oda E. et al. PLoS One 2013;8:e63773 (melatonin for primary sleep disorders, meta-analysis).",
                "Erland L.A. & Saxena P.K. J Clin Sleep Med 2017;13:275-81 (melatonin supplement content vs label).",
            ]
        ),
        Entry(
            id: "glycine", name: "Glycine",
            names: ["glycine"],
            category: .sleepAndStress,
            claims: [
                c("Sleep quality", .weak, "Three small trials (10-15 people each, run by the maker) found better subjective sleep and less daytime tiredness after 3 g at bedtime (Yamadera 2007; Bannai 2012). No large independent trial."),
            ],
            dose: "3 g",
            timing: "30-60 minutes before bed",
            expect: "Possibly deeper-feeling sleep; the evidence is thin.",
            cautions: ["Very safe (it's an amino acid in food); mild stomach upset at most."],
            dataNotes: ["Compare a week with and a week without, using your sleep score."],
            sources: [
                "Yamadera W. et al. Sleep Biol Rhythms 2007;5:126-31 (glycine and sleep quality, polysomnography).",
                "Bannai M. et al. Front Neurol 2012;3:61 (glycine during sleep restriction, crossover trial).",
            ]
        ),
        Entry(
            id: "magnesium", name: "Magnesium",
            names: ["magnesium", "magnesium glycinate", "magnesium citrate", "magnesium bisglycinate", "zma"],
            category: .sleepAndStress,
            claims: [
                c("Sleep", .weak, "Observational links between low magnesium and poor sleep; RCTs are few, small and mostly in older adults with insomnia (Arab 2023 review). No benefit shown in people with adequate intake."),
                c("Performance and cramps", .none, "No effect on performance or cramps unless you were deficient (IOC 2018)."),
            ],
            dose: "200-400 mg of elemental magnesium (glycinate or citrate are better absorbed than oxide)",
            timing: "evening, with food",
            expect: "Nothing unless your intake was low; then possibly steadier sleep over a few weeks.",
            cautions: ["Loose stools above about 350 mg from supplements (the supplement upper limit). Check with your doctor if you have kidney disease."],
            dataNotes: ["Your vitamins and minerals page shows whether your food already covers magnesium; fix food first."],
            sources: [
                "Arab A. et al. Biol Trace Elem Res 2023;201:121-8 (magnesium and sleep, systematic review).",
                "NIH Office of Dietary Supplements, Magnesium fact sheet for health professionals.",
                ioc,
            ]
        ),
    ]

    // MARK: Recovery

    static let recoveryEntries: [Entry] = [
        Entry(
            id: "tartCherry", name: "Tart cherry",
            names: ["tart cherry", "montmorency", "cherry juice", "cherry active"],
            category: .recovery,
            claims: [
                c("Soreness and strength recovery", .moderate, "Less soreness (small effect) and faster strength recovery (moderate) after hard sessions in a meta-analysis of 14 trials, with variable results between studies (Hill 2021)."),
                c("Sleep", .weak, "Two small trials found slightly longer sleep; not enough to count on."),
            ],
            dose: "30 ml concentrate or 240 ml juice, twice a day, in the days around a hard event; about 250-300 mg anthocyanins",
            timing: "4-5 days before and 2-3 days after a hard event",
            expect: "Slightly less sore and quicker back to full strength after an unusual effort.",
            cautions: ["Juice adds 100-150 kcal of sugar a serving. Taking it every day may blunt training adaptations, as with other high-dose antioxidants."],
            dataNotes: ["Compare muscle soreness in your check-ins across event weeks with and without."],
            sources: [
                "Hill J.A. et al. Int J Sport Nutr Exerc Metab 2021;31:154-67 (tart cherry and recovery, meta-analysis).",
                "Howatson G. et al. Eur J Nutr 2012;51:909-16 (tart cherry juice and sleep, RCT).",
            ]
        ),
        Entry(
            id: "collagen", name: "Collagen or gelatin",
            names: ["collagen", "gelatin", "collagen peptides", "hydrolysed collagen", "hydrolyzed collagen"],
            category: .recovery,
            claims: [
                c("Tendons and joints", .weak, "A small crossover trial (8 people) found more collagen synthesis markers after 15 g gelatin with vitamin C before jump exercise (Shaw 2017). Reviews find some joint-pain and tendon-structure signals but small trials and surrogate markers (Khatri 2021)."),
            ],
            dose: "10-15 g with 50 mg vitamin C",
            timing: "about an hour before tendon-loading training",
            expect: "Nothing you'll feel; the hoped-for benefit is slower tendon problems over months.",
            cautions: ["Safe. It's a poor protein for muscle (low in leucine), so don't count it toward your protein target."],
            dataNotes: ["Nothing in your data changes."],
            sources: [
                "Shaw G. et al. Am J Clin Nutr 2017;105:136-43 (vitamin C-enriched gelatin and collagen synthesis, crossover trial).",
                "Khatri M. et al. Amino Acids 2021;53:1493-506 (collagen peptide supplementation, systematic review).",
            ]
        ),
        Entry(
            id: "omega3", name: "Omega-3 (fish oil)",
            names: ["omega 3", "omega3", "fish oil", "epa", "dha", "krill oil", "algae oil", "cod liver oil"],
            category: .recovery,
            claims: [
                c("Heart and general health", .moderate, "Lowers triglycerides and, at prescription doses, cardiovascular events in people at risk; many athletes have low omega-3 levels (ISSN 2025)."),
                c("Muscle soreness", .weak, "Less soreness after hard eccentric exercise in pooled trials, but below the size people notice and rated low quality (Lv 2020)."),
                c("Performance and muscle growth", .weak, "No clear effect on strength or muscle in young adults; maybe better endurance measures (ISSN 2025)."),
            ],
            dose: "1-2 g a day of EPA + DHA combined (check the label: a 1 g capsule often holds 300 mg)",
            timing: "with a meal containing fat; any time of day",
            expect: "No felt effect; it's a long-term health habit. Fishy aftertaste is common.",
            cautions: ["Above 3 g a day can thin blood; ask your doctor if you take anticoagulants. Choose a tested brand (oxidation and contaminants)."],
            dataNotes: ["Eating oily fish twice a week does the same; your food log won't show EPA/DHA separately."],
            sources: [
                "Jäger R. et al. J Int Soc Sports Nutr 2025;22:2441775 (ISSN position stand on long-chain omega-3 fatty acids).",
                "Lv Z.T. et al. Front Physiol 2020;11:188 (omega-3 and muscle soreness after eccentric exercise, meta-analysis).",
                ioc,
            ]
        ),
    ]

    // MARK: Health

    static let healthEntries: [Entry] = [
        Entry(
            id: "vitaminD", name: "Vitamin D",
            names: ["vitamin d", "vitamin d3", "d3", "cholecalciferol", "vit d"],
            category: .health,
            claims: [
                c("If your blood level is low", .moderate, "Correcting a deficiency (25(OH)D under 50 nmol/L) supports bone and muscle; indoor and winter training make low levels common (Owens 2018; IOC 2018)."),
                c("Strength or performance when not deficient", .none, "Meta-analyses of athlete RCTs show no gain in strength or power overall (Zhang 2019; Sist 2023)."),
            ],
            dose: "1,000-2,000 IU (25-50 µg) a day is the usual maintenance dose; more only on a doctor's advice",
            timing: "with a meal containing fat; any time",
            expect: "Nothing you'll feel unless you were deficient; a blood test tells you.",
            cautions: ["The upper limit is 4,000 IU (100 µg) a day; months of high doses raise blood calcium."],
            dataNotes: ["Your Labs screen reads 25(OH)D if you add a result; the vitamins and minerals page shows that food rarely covers it."],
            sources: [
                "Owens D.J., Allison R., Close G.L. Sports Med 2018;48(Suppl 1):3-16 (vitamin D and the athlete).",
                "Zhang L. et al. PLoS One 2019;14:e0215826 (vitamin D and muscle strength in athletes, meta-analysis).",
                "Sist M. et al. J Int Soc Sports Nutr 2023;20:2243252 (vitamin D and maximal strength and power in athletes, meta-analysis).",
                ioc,
            ]
        ),
        Entry(
            id: "zinc", name: "Zinc",
            names: ["zinc", "zinc picolinate"],
            category: .health,
            claims: [
                c("Immunity and testosterone", .none, "No benefit unless intake is low; athletes' serum zinc is often slightly lower, but supplementing non-deficient people doesn't improve performance or hormones (IOC 2018)."),
                c("Colds (lozenges at the first sign)", .weak, "Zinc acetate lozenges shortened colds by about a third in small trials (Hemilä 2017)."),
            ],
            dose: "8-11 mg a day is the RDA; most diets cover it",
            timing: "with food; away from iron and calcium supplements",
            expect: "Nothing unless you were low.",
            cautions: ["Above the 40 mg upper limit for months lowers copper and immunity."],
            dataNotes: ["Your vitamins and minerals page shows zinc intake from food."],
            sources: [
                "NIH Office of Dietary Supplements, Zinc fact sheet for health professionals.",
                "Hemilä H. JRSM Open 2017;8:2054270417694291 (zinc lozenges and the common cold, meta-analysis).",
                ioc,
            ]
        ),
        Entry(
            id: "multivitamin", name: "Multivitamin",
            names: ["multivitamin", "multi vitamin", "multivitamins", "centrum", "one a day", "multi"],
            category: .health,
            claims: [
                c("Health and performance", .none, "No reduction in heart disease or cancer in the US Preventive Services Task Force review (2022), and no performance benefit in athletes who eat enough. It fills gaps only if your diet has them."),
            ],
            dose: "one a day if you take one",
            timing: "with a meal",
            expect: "Nothing you'll feel. Check your vitamins and minerals page first: it shows which nutrients your food already covers.",
            cautions: ["Avoid ones with beta-carotene if you smoke (lung cancer risk). Don't stack with other vitamin A, iron or zinc supplements."],
            dataNotes: ["Food logs don't include supplements unless you log them; your vitamins and minerals page shows the food side only."],
            sources: [
                "US Preventive Services Task Force. JAMA 2022;327:2326-33 (vitamin, mineral and multivitamin supplementation to prevent cardiovascular disease and cancer).",
                ioc,
            ]
        ),
    ]
}
