import Foundation

/// What common medications do to the things this app measures (heart rate,
/// HRV, sleep, muscle, recovery), and how the app should adjust. Drawn from
/// published research and drug labels; each class lists its sources.
///
/// This is training guidance, not medical advice. The app never suggests
/// changing a dose; it says "talk to your doctor" instead.
public enum MedicationKnowledge {
    /// Things the app does differently for a medication class.
    public enum Adjustment: String, Sendable, Codable, CaseIterable {
        /// Lowers resting and max heart rate: heart-rate zones and HR-based strain read low.
        case bluntsHeartRate
        /// Raises resting heart rate / lowers HRV: recovery may read low.
        case raisesHeartRate
        /// Changes sleep length or stages.
        case affectsSleep
        /// Weight loss with muscle loss risk: raise protein, keep lifting.
        case raiseProtein
        /// Higher tendon injury risk: avoid sudden jumps in load and plyometrics.
        case tendonCaution
        /// Fluid/electrolyte loss: hydrate around training.
        case hydration
        /// May blunt muscle or fitness gains.
        case bluntsAdaptation
        /// Dizziness on standing: care with fast position changes.
        case dizziness
    }

    public enum Metric: String, Sendable, CaseIterable {
        case heartRate = "Heart rate"
        case hrv = "HRV"
        case sleep = "Sleep"
        case muscle = "Muscle & strength"
        case fitness = "Fitness gains"
        case weight = "Weight & appetite"
        case tendons = "Tendons"
        case hydration = "Hydration"
        case bloodPressure = "Blood pressure"
        case energy = "Energy"
    }

    public struct Effect: Sendable, Equatable {
        public var metric: Metric
        public var text: String
    }

    public struct DrugClass: Sendable, Identifiable, Equatable {
        public var id: String
        public var name: String
        /// Lowercased generic and brand names that identify the class.
        public var names: [String]
        public var effects: [Effect]
        public var recommendations: [String]
        public var adjustments: Set<Adjustment>
        public var sources: [String]
    }

    /// The class a medication belongs to, matched on generic or brand name.
    public static func match(_ medicationName: String) -> DrugClass? {
        let words = medicationName.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 2 }
        guard !words.isEmpty else { return nil }
        let joined = words.joined(separator: " ")
        return classes.first { drug in
            drug.names.contains { name in
                name.contains(" ") ? joined.contains(name) : words.contains(name)
            }
        }
    }

    private static func e(_ metric: Metric, _ text: String) -> Effect { Effect(metric: metric, text: text) }

    public static let classes: [DrugClass] = [
        DrugClass(
            id: "betaBlocker", name: "Beta-blocker",
            names: ["metoprolol", "lopressor", "toprol", "atenolol", "tenormin", "propranolol", "inderal", "bisoprolol",
                    "carvedilol", "coreg", "nebivolol", "bystolic", "nadolol", "labetalol", "sotalol", "acebutolol"],
            effects: [
                e(.heartRate, "Lowers resting and maximum heart rate, often by 20-30%. Heart-rate zones based on age overestimate your max."),
                e(.hrv, "Usually raises HRV, so a jump after starting is the drug, not better fitness."),
                e(.energy, "Can make hard efforts feel harder and cause tiredness, especially early on."),
            ],
            recommendations: [
                "Judge cardio effort by how hard it feels (RPE) rather than heart-rate zones; the app already counts gym sessions by RPE.",
                "If you know your max heart rate on the medication (from a test), enter it in Settings so strain is accurate.",
                "Your recovery baseline takes 2-4 weeks to settle after starting or changing the dose.",
            ],
            adjustments: [.bluntsHeartRate],
            sources: [
                "ACSM's Guidelines for Exercise Testing and Prescription, 11th ed. (2021): use RPE for people on beta-blockers.",
                "Wonisch M. et al. Eur J Cardiovasc Prev Rehabil 2003;10:296-301 (beta-blockers and heart-rate-based exercise prescription).",
            ]
        ),
        DrugClass(
            id: "rateLimitingCCB", name: "Heart-rate-lowering calcium channel blocker",
            names: ["verapamil", "calan", "isoptin", "diltiazem", "cardizem", "tiazac"],
            effects: [
                e(.heartRate, "Lowers resting heart rate and the rise in heart rate during exercise."),
                e(.bloodPressure, "Lowers blood pressure; dizziness can happen after hard sets."),
            ],
            recommendations: [
                "Use RPE as well as heart rate to judge effort.",
                "Stand up slowly after floor exercises and long sets.",
            ],
            adjustments: [.bluntsHeartRate, .dizziness],
            sources: ["FDA prescribing information for verapamil and diltiazem (bradycardia, hypotension)."]
        ),
        DrugClass(
            id: "stimulant", name: "Stimulant (ADHD)",
            names: ["methylphenidate", "ritalin", "concerta", "focalin", "dexmethylphenidate", "amphetamine", "adderall",
                    "lisdexamfetamine", "vyvanse", "dextroamphetamine", "dexedrine", "mydayis"],
            effects: [
                e(.heartRate, "Raises resting heart rate by a few beats per minute and blood pressure slightly."),
                e(.hrv, "Tends to lower daytime HRV, so recovery can read lower on dosing days."),
                e(.sleep, "Can delay falling asleep and shorten sleep, especially with later doses."),
                e(.weight, "Lowers appetite, which makes hitting protein and calories harder."),
            ],
            recommendations: [
                "Compare recovery with other dosing days, not with days off the medication.",
                "Plan a protein-rich meal before the dose takes effect or in the evening.",
                "Ask your prescriber about timing if sleep is suffering.",
            ],
            adjustments: [.raisesHeartRate, .affectsSleep],
            sources: [
                "Liang E.F. et al. Neuropsychiatr Dis Treat 2018;14:2389-2406 (cardiovascular effects of ADHD medication, meta-analysis).",
                "Kidwell K.M. et al. Pediatrics 2015;136:1144-53 (stimulants and sleep, meta-analysis).",
            ]
        ),
        DrugClass(
            id: "ssri", name: "SSRI antidepressant",
            names: ["sertraline", "zoloft", "fluoxetine", "prozac", "escitalopram", "lexapro", "citalopram", "celexa",
                    "paroxetine", "paxil", "fluvoxamine"],
            effects: [
                e(.hrv, "Little effect on HRV in most studies."),
                e(.sleep, "Reduces REM sleep and can cause vivid dreams or broken sleep; sleep stages from your watch may look different."),
                e(.energy, "Some people feel tired or restless in the first weeks."),
            ],
            recommendations: [
                "Judge sleep by how rested you feel as well as the sleep score, since REM changes are expected.",
                "Talk to your prescriber about dose timing if sleep is disrupted.",
            ],
            adjustments: [.affectsSleep],
            sources: [
                "Kemp A.H. et al. Biol Psychiatry 2010;67:1067-74 (antidepressants and HRV, meta-analysis).",
                "Wichniak A. et al. Curr Psychiatry Rep 2017;19:63 (antidepressants and sleep).",
            ]
        ),
        DrugClass(
            id: "snriTca", name: "SNRI / tricyclic antidepressant",
            names: ["venlafaxine", "effexor", "desvenlafaxine", "pristiq", "duloxetine", "cymbalta", "amitriptyline",
                    "nortriptyline", "imipramine", "clomipramine", "doxepin"],
            effects: [
                e(.heartRate, "Can raise resting heart rate."),
                e(.hrv, "Lowers HRV (stronger with tricyclics), so your recovery baseline will sit lower."),
                e(.sleep, "Reduces REM sleep; tricyclics can make you drowsy."),
            ],
            recommendations: [
                "Let the recovery baseline settle for 2-4 weeks after starting or changing dose.",
                "Compare HRV with your own baseline on the medication, not with population norms.",
            ],
            adjustments: [.raisesHeartRate, .affectsSleep],
            sources: ["Kemp A.H. et al. Biol Psychiatry 2010;67:1067-74 (tricyclics reduce HRV; SNRIs raise heart rate)."]
        ),
        DrugClass(
            id: "glp1", name: "GLP-1 medication (weight loss / diabetes)",
            names: ["semaglutide", "ozempic", "wegovy", "rybelsus", "tirzepatide", "mounjaro", "zepbound", "liraglutide",
                    "saxenda", "victoza", "dulaglutide", "trulicity"],
            effects: [
                e(.weight, "Strongly lowers appetite. In trials up to about 40% of the weight lost was lean (muscle and other non-fat) mass."),
                e(.heartRate, "Raises resting heart rate by about 2-4 bpm on average."),
                e(.muscle, "Lifting and enough protein are the main ways to keep muscle while losing weight."),
            ],
            recommendations: [
                "Protein target is raised to 2.0 g per kg (the app does this for you). Spread it across meals.",
                "Keep at least 2-3 strength sessions a week.",
                "Expect resting heart rate to sit a little higher; recovery adjusts after a few weeks.",
            ],
            adjustments: [.raiseProtein, .raisesHeartRate],
            sources: [
                "Wilding J.P.H. et al. NEJM 2021;384:989-1002 (STEP 1; DXA substudy: ~39% of weight lost was lean mass).",
                "Jäger R. et al. J Int Soc Sports Nutr 2017;14:20 (ISSN position: 1.4-2.0+ g/kg protein, more in a deficit).",
            ]
        ),
        DrugClass(
            id: "metformin", name: "Metformin",
            names: ["metformin", "glucophage", "glumetza", "fortamet", "riomet"],
            effects: [
                e(.fitness, "In healthy older adults, metformin blunted gains in aerobic fitness and muscle from training."),
                e(.energy, "Stomach upset is common at first; take with food."),
            ],
            recommendations: [
                "Don't change your dose for training. If progress stalls, mention these studies to your doctor.",
                "Track lifts over months; the effect in studies was smaller gains, not losses.",
            ],
            adjustments: [.bluntsAdaptation],
            sources: [
                "Konopka A.R. et al. Aging Cell 2019;18:e12880 (metformin blunted VO2 max gains).",
                "Walton R.G. et al. Aging Cell 2019;18:e13039 (MASTERS trial: blunted hypertrophy).",
            ]
        ),
        DrugClass(
            id: "statin", name: "Statin",
            names: ["atorvastatin", "lipitor", "rosuvastatin", "crestor", "simvastatin", "zocor", "pravastatin",
                    "lovastatin", "pitavastatin", "fluvastatin"],
            effects: [
                e(.muscle, "Muscle aches are reported often, but in blinded trials most aches weren't caused by the statin (about 1 in 15 were)."),
            ],
            recommendations: [
                "Normal soreness after training is expected. Unusual, unexplained muscle pain or weakness, or dark urine, needs a doctor.",
                "Don't stop a statin because of soreness without talking to your doctor.",
            ],
            adjustments: [],
            sources: ["Cholesterol Treatment Trialists' Collaboration. Lancet 2022;400:832-45 (statins and muscle symptoms)."]
        ),
        DrugClass(
            id: "nsaid", name: "NSAID pain reliever",
            names: ["ibuprofen", "advil", "motrin", "naproxen", "aleve", "naprosyn", "diclofenac", "voltaren",
                    "celecoxib", "celebrex", "meloxicam", "mobic", "ketorolac"],
            effects: [
                e(.muscle, "High daily doses taken for weeks blunted muscle growth from training in young adults; occasional use is unlikely to matter."),
                e(.bloodPressure, "Regular use can raise blood pressure."),
            ],
            recommendations: [
                "Avoid taking NSAIDs routinely just to train through soreness.",
                "Occasional doses for pain are fine for training purposes.",
            ],
            adjustments: [.bluntsAdaptation],
            sources: ["Lilja M. et al. Acta Physiol 2018;222:e12948 (1,200 mg/day ibuprofen for 8 weeks blunted hypertrophy)."]
        ),
        DrugClass(
            id: "fluoroquinolone", name: "Fluoroquinolone antibiotic",
            names: ["ciprofloxacin", "cipro", "levofloxacin", "levaquin", "moxifloxacin", "avelox", "ofloxacin"],
            effects: [
                e(.tendons, "Raises the risk of tendon inflammation and rupture (FDA boxed warning), most often the Achilles, during and for months after."),
            ],
            recommendations: [
                "While taking it and for a few weeks after: avoid jumps, sprints, max lifts and sudden jumps in load.",
                "Stop the exercise and contact your doctor if a tendon hurts or swells.",
            ],
            adjustments: [.tendonCaution],
            sources: ["FDA Drug Safety Communication, 2016 (fluoroquinolone boxed warning: tendinitis and tendon rupture)."]
        ),
        DrugClass(
            id: "corticosteroid", name: "Oral corticosteroid",
            names: ["prednisone", "prednisolone", "methylprednisolone", "medrol", "dexamethasone", "decadron", "hydrocortisone"],
            effects: [
                e(.sleep, "Often causes poor sleep, especially with evening doses."),
                e(.muscle, "Long courses can cause muscle loss and weaker tendons."),
                e(.weight, "Raises appetite and blood sugar."),
            ],
            recommendations: [
                "Morning dosing helps sleep (ask your prescriber).",
                "On long courses, keep lifting and protein up to protect muscle.",
            ],
            adjustments: [.affectsSleep, .raiseProtein],
            sources: ["FDA prescribing information for prednisone (insomnia, myopathy, hyperglycemia)."]
        ),
        DrugClass(
            id: "sedatingAntihistamine", name: "Sedating antihistamine / sleep aid",
            names: ["diphenhydramine", "benadryl", "doxylamine", "unisom", "hydroxyzine", "promethazine", "chlorpheniramine",
                    "zzzquil", "nyquil"],
            effects: [
                e(.sleep, "Helps you fall asleep but can leave you groggy the next morning."),
                e(.heartRate, "Can raise heart rate slightly."),
            ],
            recommendations: ["Avoid heavy or technical lifts the morning after a dose if you feel groggy."],
            adjustments: [.affectsSleep],
            sources: ["FDA drug labels for diphenhydramine and doxylamine (next-day drowsiness)."]
        ),
        DrugClass(
            id: "benzoZ", name: "Benzodiazepine / Z-drug",
            names: ["alprazolam", "xanax", "lorazepam", "ativan", "clonazepam", "klonopin", "diazepam", "valium",
                    "temazepam", "zolpidem", "ambien", "eszopiclone", "lunesta", "zaleplon"],
            effects: [
                e(.sleep, "Lengthens sleep but reduces deep sleep, so your watch may show less deep sleep."),
                e(.energy, "Can slow reaction time the next day."),
            ],
            recommendations: ["Be careful with heavy or balance-demanding lifts the morning after."],
            adjustments: [.affectsSleep],
            sources: ["FDA prescribing information (next-day impairment); Roehrs T. & Roth T. Sleep Med Rev 2012;16:333-9 (hypnotics and sleep stages)."]
        ),
        DrugClass(
            id: "diuretic", name: "Diuretic",
            names: ["hydrochlorothiazide", "hctz", "chlorthalidone", "furosemide", "lasix", "torsemide", "bumetanide",
                    "spironolactone", "indapamide"],
            effects: [
                e(.hydration, "Increases fluid and electrolyte loss; cramps and dizziness are more likely in hot or long sessions."),
            ],
            recommendations: ["Drink before and during training, and ask your doctor how much salt and fluid is right for you."],
            adjustments: [.hydration, .dizziness],
            sources: ["FDA prescribing information for thiazide and loop diuretics."]
        ),
        DrugClass(
            id: "alphaBlocker", name: "Alpha-blocker",
            names: ["tamsulosin", "flomax", "doxazosin", "cardura", "terazosin", "prazosin", "alfuzosin"],
            effects: [e(.bloodPressure, "Can drop blood pressure when you stand up quickly.")],
            recommendations: ["Stand up slowly after floor work, and sit down if you feel light-headed."],
            adjustments: [.dizziness],
            sources: ["FDA prescribing information (orthostatic hypotension)."]
        ),
        DrugClass(
            id: "alpha2", name: "Clonidine / guanfacine",
            names: ["clonidine", "catapres", "kapvay", "guanfacine", "intuniv", "tenex"],
            effects: [
                e(.heartRate, "Lowers resting heart rate and blood pressure."),
                e(.energy, "Can cause drowsiness."),
            ],
            recommendations: ["Use RPE as well as heart rate to judge effort."],
            adjustments: [.bluntsHeartRate, .dizziness],
            sources: ["FDA prescribing information for clonidine and guanfacine."]
        ),
        DrugClass(
            id: "thyroid", name: "Thyroid hormone",
            names: ["levothyroxine", "synthroid", "levoxyl", "euthyrox", "liothyronine", "cytomel", "armour"],
            effects: [e(.heartRate, "At the right dose, little effect. A rising resting heart rate can be a sign the dose is too high.")],
            recommendations: [
                "Take it on an empty stomach, apart from protein shakes, coffee and calcium or iron supplements.",
                "Mention a steady rise in resting heart rate to your doctor.",
            ],
            adjustments: [],
            sources: ["FDA prescribing information for levothyroxine (administration; overtreatment causes tachycardia)."]
        ),
        DrugClass(
            id: "isotretinoin", name: "Isotretinoin",
            names: ["isotretinoin", "accutane", "absorica", "claravis", "amnesteem"],
            effects: [e(.muscle, "Muscle and joint aches are common, and very hard training can raise muscle enzymes (CK) a lot.")],
            recommendations: ["Keep training moderate and avoid extreme new workouts while on it."],
            adjustments: [.tendonCaution],
            sources: ["FDA prescribing information for isotretinoin (musculoskeletal symptoms, CK elevation)."]
        ),
        DrugClass(
            id: "betaAgonist", name: "Asthma reliever inhaler",
            names: ["albuterol", "salbutamol", "ventolin", "proair", "levalbuterol", "xopenex"],
            effects: [e(.heartRate, "Raises heart rate for a few hours after use.")],
            recommendations: ["Heart rate may read high in workouts right after using it; that's the inhaler, not extra effort."],
            adjustments: [.raisesHeartRate],
            sources: ["FDA prescribing information for albuterol (tachycardia)."]
        ),
        DrugClass(
            id: "antipsychotic", name: "Antipsychotic",
            names: ["quetiapine", "seroquel", "olanzapine", "zyprexa", "risperidone", "risperdal", "aripiprazole",
                    "abilify", "lurasidone", "latuda"],
            effects: [
                e(.weight, "Several (especially olanzapine and quetiapine) increase appetite and weight."),
                e(.sleep, "Can lengthen sleep and cause morning grogginess."),
                e(.heartRate, "Some raise resting heart rate."),
            ],
            recommendations: ["Regular training and protein-rich meals help limit weight gain."],
            adjustments: [.affectsSleep, .raisesHeartRate],
            sources: ["Pillinger T. et al. Lancet Psychiatry 2020;7:64-77 (metabolic effects of antipsychotics, network meta-analysis)."]
        ),
        DrugClass(
            id: "gabapentinoid", name: "Gabapentin / pregabalin",
            names: ["gabapentin", "neurontin", "pregabalin", "lyrica"],
            effects: [
                e(.sleep, "Increases deep sleep, which can raise your sleep score."),
                e(.energy, "Dizziness and drowsiness are common."),
            ],
            recommendations: ["Take extra care with balance-heavy lifts if you feel dizzy."],
            adjustments: [.affectsSleep, .dizziness],
            sources: ["FDA prescribing information; Foldvary-Schaefer N. et al. Epilepsia 2002;43:1493-7 (gabapentin increases slow-wave sleep)."]
        ),
        DrugClass(
            id: "melatonin", name: "Melatonin",
            names: ["melatonin"],
            effects: [e(.sleep, "Helps you fall asleep a little faster (about 7 minutes on average) and helps with jet lag.")],
            recommendations: ["Take it 1-2 hours before your target bedtime at the same time each night."],
            adjustments: [.affectsSleep],
            sources: ["Ferracioli-Oda E. et al. PLoS One 2013;8:e63773 (melatonin for primary sleep disorders, meta-analysis)."]
        ),
        DrugClass(
            id: "creatine", name: "Creatine (supplement)",
            names: ["creatine", "creapure"],
            effects: [
                e(.muscle, "With lifting, adds more strength and muscle than training alone (on average about 1 kg more lean mass over a few months)."),
                e(.weight, "Holds extra water in muscle, so scale weight often rises 0.5-2 kg in the first 1-4 weeks. That's water, not fat."),
                e(.hydration, "Doesn't cause dehydration or cramps in studies; drink normally."),
                e(.energy, "Raises creatinine on blood tests without harming healthy kidneys."),
            ],
            recommendations: [
                "Take 3-5 g every day, rest days included. The time of day matters far less than not missing days.",
                "No loading phase needed: 3-5 g a day fills your muscles in about 3-4 weeks (loading 20 g a day for 5-7 days just gets there sooner).",
                "Expect the scale to jump at first; judge fat loss by your waist and photos for the first month.",
                "Tell your doctor you take it before kidney blood tests, and ask first if you have kidney disease.",
            ],
            adjustments: [],
            sources: [
                "Kreider R.B. et al. J Int Soc Sports Nutr 2017;14:18 (ISSN position stand on creatine).",
                "Antonio J. et al. J Int Soc Sports Nutr 2021;18:13 (common questions and misconceptions about creatine).",
                "Delpino F.M. et al. Nutrition 2022;103-104:111791 (creatine and lean mass with resistance training, meta-analysis).",
                "Hultman E. et al. J Appl Physiol 1996;81:232-7 (loading vs 3 g/day reach the same muscle levels).",
            ]
        ),
        DrugClass(
            id: "testosterone", name: "Testosterone",
            names: ["testosterone", "androgel", "testim", "depo testosterone", "xyosted"],
            effects: [
                e(.muscle, "Increases muscle and strength gains from training."),
                e(.heartRate, "Raises red blood cell count (hematocrit), which needs regular blood tests."),
            ],
            recommendations: ["Keep up the blood tests your doctor orders; progress lifts gradually since tendons adapt more slowly than muscle."],
            adjustments: [.tendonCaution],
            sources: ["Bhasin S. et al. J Clin Endocrinol Metab 2018;103:1715-44 (Endocrine Society guideline)."]
        ),
    ]
}

extension MedicationKnowledge.DrugClass {
    /// Protein per kg body weight the app should aim for with this class, if it changes it.
    public var proteinGramsPerKg: Double? {
        adjustments.contains(.raiseProtein) ? 2.0 : nil
    }
}
