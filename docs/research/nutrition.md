# Nutrition and calorie tracking: what Tensile can do, and what it should say

Research round, November 2026. Code looked at: `Packages/AppCore/Sources/AppCore/Nutrition.swift`,
`Micronutrients.swift`, `Goals.swift`, `EnergyBalance.swift`, `Wellbeing.swift` (hydration),
`Habits.swift` (caffeine, alcohol), `CheckIn.swift` (last meal) and the dietary reads in
`App/Services/HealthKitClient.swift`.

Method note: web fetches to vendor and journal sites were blocked by the sandbox, so facts below
come from search results and abstracts, and the search budget ran out before every item was
verified. Anything marked **(unverified)** was not confirmed this round and should be checked
before it goes into app copy. No study is cited that was not found in a search result.

## Summary

**Can I do calorie tracking through this app?** Yes, and you already are: Tensile reads what
Cronometer writes to Apple Health (calories, protein, carbs, fat, fibre, water, caffeine and
twelve vitamins and minerals), shows energy balance against estimated burn, works out your real
maintenance calories from intake and weight trend (the same idea as MacroFactor's expenditure
algorithm), sets calorie and protein targets from your goal, and flags low micronutrients. What
it does not have is its own food logger: you cannot search a food, scan a barcode or snap a
plate inside Tensile. That is buildable (see option B below), but for one person who already
logs in Cronometer it is a lot of work for little gain.

**Can it access food databases from other apps such as Cronometer?** Not directly. Cronometer
has no public developer API (only unofficial clients that mimic its web app and need your
password), and neither do MyFitnessPal (closed to new developers), Lose It, Carb Manager,
MacroFactor, Yazio or Lifesum. What every one of them offers is a write to Apple Health, and
that is the legitimate channel: Tensile reads the samples, not the app's database. Apple Health
gives per-sample amounts and times, and optionally a food name when the writer uses a food
correlation with `HKMetadataKeyFoodType`; whether Cronometer writes per-meal times or
midnight-stamped day totals is something to check on your phone (older forum answers from
Cronometer staff say midnight; a later user report says Gold timestamps sync). If you ever want
Tensile's own logger, the databases you *can* use legally and cheaply are USDA FoodData Central
(public domain) and Open Food Facts (ODbL, barcodes, attribution and share-alike rules), with
barcode scanning from Apple's VisionKit and an optional AI photo estimate through your Supabase
function.

**Recommendation:** keep Cronometer as the logger (option A), make Tensile read per-meal
samples and food names where they exist, and add the nutrition coaching in section 2 (protein
per meal, carbs by training day, fat floor, fibre, energy availability, weekly target adjustment,
diet breaks, late-eating check through the pattern analysis). Add an in-app "quick estimate"
(barcode + FoodData Central search + AI photo) only as a fallback for meals you would otherwise
not log, written to Apple Health under Tensile's own source so nothing is counted twice.

## 1. Food data sources

### Decision table

| Source | Public API | Cost | Licence / attribution | Coverage | Quality | OK for an iOS app? | Verdict for Tensile |
|---|---|---|---|---|---|---|---|
| **Cronometer** | No. Unofficial GWT-RPC clients (`cronometer-mcp`, Go module) mimic the web app and store your password; they break on each release and sit outside the terms of service | Free; Gold (~$50-60/yr) for timestamps, reports beyond 7 days, photo logging | CSV export of diary, nutrition summaries, biometrics on the free tier (one source says Gold required; verify in your account) | Its own curated database (NCCDB, USDA, branded) | High; best micronutrient coverage of any consumer app | Only via Apple Health (what it writes) or manual CSV import | **Keep as the logger.** Read Apple Health samples; do not use unofficial clients |
| **MyFitnessPal** | Closed to new partners; "contact us" only | n/a | n/a | 14M+ foods (vendor claim) | Crowdsourced, noisy | Only via Apple Health | Not available |
| **Lose It, Carb Manager, MacroFactor, Yazio, Lifesum** | None official. MacroFactor and Yazio have reverse-engineered clients (Firestore / private backend) | n/a | n/a | n/a | n/a | Only via Apple Health | Not available |
| **USDA FoodData Central** | Yes, REST, API key | Free; 1,000 requests/hour per key (DEMO_KEY 30/h); higher on request | Public domain (CC0 1.0 / US Government work); USDA asks to be credited as the source. Keys must not ship in the app (exposed keys are deactivated), so proxy through the Supabase edge function | Foundation, SR Legacy, FNDDS (survey foods and portions), Branded (US products via GS1/label data; hundreds of thousands) | Lab-analysed for Foundation; Branded is label data | Yes | **First choice** for generic foods and US branded items |
| **Open Food Facts** | Yes, free REST; bulk dumps recommended for heavy use; custom User-Agent required | Free | Database under **ODbL**: visible credit in the app (product/search screens or About) with links to OFF and the ODbL; **share-alike** applies if you publish an adapted database (so keep OFF data in its own table, do not merge it into a proprietary food database; the FAQ warns combining can require releasing the result as open data); product images CC BY-SA; contributions should flow back via the API | Millions of barcoded products worldwide, strongest outside the US | Crowdsourced; variable, missing fields common | Yes, with the attribution and share-alike discipline above | **First choice for barcodes**, especially non-US products |
| **Nutritionix** | Yes | Starter $499/mo, MVP $999/mo, billed annually; free tier is a 2-user business trial; free/freemium apps and >100k MAU go to custom quotes | Attribution required except on the top tier | ~1M foods incl. restaurant menus (vendor claim) | Good branded/restaurant data | Yes, if you pay | Too expensive for a personal app |
| **Edamam Food Database** | Yes | Free "basic" plan for developers/startups/non-profits; a third party says the free tier is non-commercial; paid from ~$69/mo (third-party figure) | Attribution badge + link required on all plans; you may cache only the four macros, food ID, label and image | Generic + branded + UPC lookup | Good | Yes, on the free developer plan for a personal app (confirm terms) | Possible, but FDC + OFF cover the same ground without caching limits |
| **FatSecret Platform** | Yes (OAuth) | Basic free, 5,000 calls/day; Premier Free for startups/students/non-profits; Premier paid, quoted | Attribution required on Basic and Premier Free; not on paid Premier | Multi-country branded database | Good | Yes | Good alternative to Edamam; attribution is easy |
| **Spoonacular** | Yes | Free tier; Cook $29/mo, Culinarian $79, Chef $149; points per request | Attribution on free tiers | Recipe- and ingredient-focused | Fine for recipes | Yes | Not needed |
| **Passio Nutrition-AI SDK** | iOS SDK (Swift Package) with photo recognition, barcode, nutrition-label OCR, 2.5M-food search, voice | Token-based: Starter $99/mo (1M tokens), Growth $599, Pro $2,999; one photo costs ~20-30k tokens | Commercial licence | Large | Good, purpose-built | Yes | Only if photo logging becomes the main way you log; otherwise Claude via Supabase is cheaper |
| **CalorieNinjas** | Being retired; now API Ninjas | Free tier non-commercial; premium for commercial | — | ~100k foods | OK | — | Skip |
| **Apple HealthKit** | Framework, not a database: ~40 dietary quantity types, `HKCorrelationType(.food)` groups a meal's samples, `HKMetadataKeyFoodType` carries the food name; per-sample `startDate` and `sourceRevision` | Free | Apple developer terms; HealthKit data may not be sold or used for advertising | Whatever other apps write | Depends on writer | Yes | **Already used.** Extend to per-sample times, sources and food correlations |

### Cronometer and Apple Health, in detail

- Tensile already asks for and reads `dietaryEnergyConsumed`, protein, carbohydrates, fat, fibre,
  water, caffeine and vitamin C, D, A, B12, folate, zinc, iron, magnesium, potassium, sodium,
  calcium and selenium (`HealthKitClient.swift` lines 45-65). Cronometer's own blog describes
  its Apple Health export as a set of metrics ("13 nutrients" in one snippet); third-party guides
  say it writes most micronutrient fields. The exact list was **(unverified)** this round: open
  Health → Browse → Nutrition and see which items show Cronometer as a source. Anything missing
  (e.g. sugar, saturated fat, cholesterol, B vitamins, vitamin E/K, copper, manganese) can be
  added to the read list in a line each.
- **Daily totals vs meals.** HealthKit stores each write as its own sample with a start and end
  time. If Cronometer writes one sample per food entry with the entry's time, Tensile's existing
  `timedSamples()` already returns a per-meal series, and protein-per-meal, pre/post-workout
  timing and last-meal-before-bed can be computed. If Cronometer writes day totals stamped at
  midnight (what Cronometer staff said in older forum threads), none of that is possible from
  HealthKit and the evening check-in's "last meal" time stays the source. Check: Health →
  Protein → Show All Data → look at the times and the number of entries per day.
- **Food names.** A writer can wrap a meal's samples in an `HKCorrelation` of type `.food` with
  `HKMetadataKeyFoodType: "Chicken Caesar salad"`. Whether Cronometer does this is
  **(unverified)**; a one-off `HKCorrelationQuery` in debug will tell you. If it does, the coach
  can see what you ate, not just the totals.
- **Export.** Cronometer's CSV export (diary entries with food names and per-entry nutrients) is
  the only legitimate way to get meal-level, named data if Apple Health has none. A "Import
  Cronometer CSV" screen (Files picker → parse → store in SwiftData) is a medium-sized job and
  gives the coach named meals and NOVA-like grouping if you want it. Timestamps need Gold.
- **Unofficial API clients.** Do not build on them: they require a Gold login, keep a full-access
  password, and Cronometer can break or block them at any time.

### Other loggers

MyFitnessPal's developer programme is closed to new applicants (a vendor blog says the public
API was shut in 2019; treat the date as unverified). Lose It, Carb Manager, MacroFactor, Yazio
and Lifesum publish no developer API; the only "integrations" are reverse-engineered clients.
All of them write to Apple Health in some form, so the HealthKit path above is the portable
answer whichever logger you use.

### Photo, AI and barcode logging: how accurate

| Method | Evidence | Verdict |
|---|---|---|
| Image-based records (person photographs meals, dietitian or app codes them) | Ho et al., Clin Nutr 2020 meta-analysis of 13 studies: energy intake from images did not differ from weighed records or 24-h recalls (MD −55 kcal/day, 95% CI −119 to 9, n.s.), but, like all self-report, underestimates against doubly labelled water; no controlled-feeding validation | Moderate. As good as the food diary you already keep |
| GPT-4V on food photos | Systematic analysis (arXiv 2312.08592): 87.5% food identification; portion MAE 54.6 g vs 43.6 g for humans | Moderate for "what is it", weak for "how much" |
| ChatGPT-4 on 114 weighed meal photos | O'Hara et al., Nutrients 2025: errors >10% for 13 of 16 nutrients, mostly underestimates; poor on medium and large portions; energy and protein comparable to dietitians, carbohydrate worse | Weak to moderate |
| ChatGPT-4o, simple vs complex meals | Pilot (ScienceDirect, 2025): energy error up to 54% and fat 77% on complex meals; extra context (ingredients, portion) improved every macro | Weak without context |
| ChatGPT-5, image + escalating context | Nutrients 2025: MAE 123 kcal and 7.9 g protein image-only; better with text context; worse with no image | Moderate with context |
| Customised GPT-4o vs weighed records (Taiwan, dietetic trainees) | Am J Clin Nutr 2025 abstract: portion estimates within ±10-15%; fat least consistent (CV 24%) | Moderate |
| Barcode scanning | Apple VisionKit `DataScannerViewController` (iOS 16+, A12+) reads EAN-13/UPC and more; no licence beyond the SDK | Strong; the label is the label |

Practical reading: AI photo estimates are good enough for a restaurant meal you would otherwise
skip, and bad enough that they should not feed the maintenance-calorie calculation unweighted.
If added, store them with an "estimate" flag and a ±25% band, exclude or down-weight such days in
`AdaptiveTDEE`, and always ask for one line of context ("grilled chicken, about 200 g, with rice").
Claude through your Supabase function does this at a fraction of Passio's price; the key stays
server-side as now.

### Three paths and their cost

| Option | What it is | Effort | When it makes sense |
|---|---|---|---|
| **A. Cronometer stays the logger; Tensile reads more** | Read per-sample times, source and `HKCorrelation(.food)` names; add missing nutrient types; show meals on the Today page; feed protein-per-meal and timing | Small (1-2 days) if Cronometer writes timed samples; nothing more if it writes midnight totals | Now |
| **B. In-app logger** | Barcode (VisionKit) → Open Food Facts; text search → FoodData Central via Supabase; manual entry; optional Claude photo estimate; recent/favourite foods; write to HealthKit under Tensile's source; attribution screens; ODbL-separated storage | Large (3-5 weeks for something you would actually use daily; the hard part is the food-search UX, portions and recents, not the API calls) | If you stop using Cronometer, or want logging for someone without it |
| **C. Both: quick estimate as fallback** | B's barcode and photo pieces only, used for meals you would not log in Cronometer; written to HealthKit as `Tensile` samples; Tensile's reads merge sources by time so nothing double-counts; the coach reminds you to fix it in Cronometer later | Medium (1-2 weeks) | Most useful compromise if partly-logged days are your main data problem (they are what `AdaptiveTDEE` has to throw away) |

Double counting: Tensile's `dailySum` uses `HKStatisticsQuery` which sums all sources. If Tensile
writes its own samples, either exclude Cronometer-duplicated time windows or make Tensile's
quick-log entries explicitly "replace when Cronometer later logs the same meal" (delete Tensile's
sample when a Cronometer sample lands in the same hour).

## 2. What the app should compute and recommend, per goal

Effort: small = under a day in `AppCore` + a card; medium = a few days; large = a week or more.
Evidence: strong = meta-analysis/position stand with consistent RCTs; moderate = position stand
or RCTs with caveats; weak = observational or mechanistic; mixed = trials disagree.

| What | Why (evidence) | Strength | Goal tailoring | Effort | Status |
|---|---|---|---|---|---|
| Calorie target and rate (0.5-1%/wk loss, 0.25-0.5%/wk gain), floor 1,200/1,500 | Helms 2014; Garthe 2011; Iraki 2019 (already in `GoalPlanner`) | Moderate | Already by goal | — | **Done** |
| **Weekly auto-adjust** of the calorie target from measured maintenance and actual weekly change, with a guard above 1%/wk loss | Self-monitoring with feedback is what predicts loss (Burke, Wang & Sevick, J Am Diet Assoc 2011 review; Berry et al., Obes Rev 2021 meta-analysis of digital self-monitoring); MacroFactor's whole product is this loop | Moderate | Lose: tighten if >1%/wk; gain: cut surplus if >0.5%/wk; maintain: nudge ±100 kcal | Small (the numbers exist in `AdaptiveTDEE` and `WeightTrend`) | Review item 11, still open |
| Daily protein 1.6 g/kg (2.2 in a deficit; 2.3-3.1 g/kg lean mass) | Morton 2018; Helms 2014 (already) | Strong | Done by goal | — | **Done** |
| **Protein per meal**: ~0.4 g/kg per meal, 4 meals (range 0.25-0.55), every 3-4 h; 20-40 g per dose | Schoenfeld & Aragon, JISSN 2018; Moore et al. 2015 (0.24 g/kg young, 0.40 g/kg older per dose); Kerksick et al., ISSN nutrient timing 2017 (20-40 g, 0.25-0.40 g/kg, every 3-4 h) | Moderate (mechanistic MPS data strong; long-term body-composition trials few) | Muscle/strength: show "meals ≥0.4 g/kg today: 2 of 4"; endurance/health: 3 meals ≥0.3 g/kg; older (>60): 0.4 g/kg floor | Small, **only if HealthKit has meal times** (check first) | Review item 10 |
| **Carbohydrate by training day** | Burke et al., J Sports Sci 2011: 3-5 g/kg light/skill days, 5-7 g/kg ~1 h/day moderate, 6-10 g/kg 1-3 h/day, 8-12 g/kg 4-5 h/day; Kerksick 2017: 8-12 g/kg to max glycogen; 1.2 g/kg/h for <4 h refuel | Strong for endurance; for lifters carbs are simply what is left after protein and fat (Helms 2014) | Endurance focus: g/kg from planned session hours (the planner knows them); muscle/strength: "remaining calories"; lose: keep carbs around training, lower on rest days; show a rest-day vs training-day target pair | Small-medium | New |
| Fat floor 20-30% of calories (15% only short-term in contest prep) | Helms, Aragon & Fitschen, JISSN 2014 (15-30%); ISSN diets & body composition 2017: any split from low-fat to low-carb works for composition | Moderate | All goals: warn when 7-day fat <20% of calories or <0.5 g/kg | Small | New |
| Fibre 25-29 g/day, benefit continues >30 g | Reynolds et al., Lancet 2019 (moderate-certainty evidence; lower mortality, CHD, T2D, colorectal cancer) | Strong (observational, large) | Same for all; the app's target table already has 25/38 g | — | **Done** (keep; add the "25-29 g" line to the copy) |
| Sodium 1,500 mg AI / 2,300 mg limit, more on heavy-sweat days; potassium 3,400/2,600 mg | NASEM DRIs (already); sweat sodium losses vary several-fold between people (typical ranges **(unverified this round)**) | Moderate | Hot days / long sessions: relax the "high sodium" flag; low potassium: suggest fruit/veg | — | **Done**, tweak copy |
| Hydration target with exercise and heat | Already from NASEM/ACSM | Moderate | Done | — | **Done** |
| **Energy availability** = (intake − exercise energy) / fat-free mass; flag <30 kcal/kg FFM/day sustained, aim ~45 | 2023 IOC consensus on REDs (Mountjoy et al., BJSM 2023): LEA ≤30 kcal/kg FFM/day is the zone with health effects, ~45 for maintenance; the cut-off is a simplification, not a diagnosis | Moderate | Lose: this is the guard-rail that keeps a deficit from becoming REDs (low HRV, RHR up, poor sleep, libido, injury); endurance: most at risk; combine with the illness/HRV signals already computed | Small (needs body fat % or lean mass, which Biology has) | New |
| Creatine 3-5 g/day (or 0.3 g/kg/day 5-7 days then 3-5 g) | Kreider et al., ISSN 2017 | Strong | Muscle/strength: suggest; endurance/health: optional; already handled in weight trend | Small (card + medication entry exists) | Mostly done |
| Caffeine 3-6 mg/kg ~60 min pre-session (as low as 2 mg/kg works); respect the bedtime cut-off | Guest et al., ISSN 2021; Gardiner 2023 (cut-off, already) | Strong | Strength/endurance sessions: show dose from body mass; skip on low-recovery or late sessions; cap daily total | Small | Partly done |
| Vitamin D: not ergogenic but a requirement; indoor/winter athletes often low; test 25(OH)D | Owens, Allison & Close, Sports Med 2018 | Moderate | All; link the intake flag to the lab marker and daylight data the app already has | Small | Partly done |
| Omega-3 (EPA+DHA): athletes often insufficient; supports endurance and cardiovascular function | Jäger et al., ISSN position stand, JISSN 2025 | Moderate | Endurance/health: suggest fatty fish 2×/wk or a supplement; dose from the stand **(unverified)** | Small (copy only) | New |
| Pre/post-workout timing: no narrow "anabolic window"; a protein-containing meal within ~2 h after (or 3-4 h before) is enough | Aragon & Schoenfeld, JISSN 2013; Kerksick 2017 | Strong | Show only when meal times exist; otherwise one line in the coach | Small | New (needs meal times) |
| Late eating / fasting windows | Observational studies link eating close to bed with worse sleep, largely via what is eaten (Soares, J Hum Nutr Diet 2025; scoping review Sleep Med Rev 2024); RCT secondary analysis of time-restricted eating found no difference in objective sleep (JAMA Netw Open 2025) | Mixed | Keep the personal t-test on "ate after 9 pm" (already); do not push fasting windows; mention a 2-3 h gap only if *your* data shows it | — | **Done** (the personal-pattern approach is the right one) |
| Alcohol | Done | — | — | — | **Done** |
| Ultra-processed share (NOVA) | Hall et al., Cell Metab 2019 inpatient RCT (n=20): +508 kcal/day ad libitum on UPF diet, matched for presented macros | Moderate (small, short, but tightly controlled) | Lose: the single best lever for passive calorie control | Not computable from HealthKit; needs food names (Cronometer CSV import or in-app logger) | Later |
| Diet quality index (HEI-2020, 13 components, density per 1,000 kcal) | USDA/NCI HEI-2020 | Moderate | Needs food-group amounts, not nutrients; a partial proxy (fibre, sodium, saturated fat, added sugar if exported) is possible | Medium | Later |
| Weighing frequency | Zheng et al., Obesity 2015 review: regular self-weighing linked to more loss, no psychological harm; Madigan et al., IJBNPA 2015 meta-analysis: daily vs weekly no different, accountability matters | Moderate | Lose/gain: ask for ≥3-4 weigh-ins/week (the trend line needs ≥4 over 10 days anyway); maintain: weekly | Small (nudge when weigh-ins drop) | New |
| Flexible, not rigid, targets | Conlin et al., JISSN 2021 RCT: same fat loss, flexible group kept more fat-free mass afterwards (+1.7 vs −0.7 kg); Smith et al., Appetite 1999: rigid restraint linked with overeating, higher BMI, anxiety | Moderate | Show weekly averages and a ±10% band, not a daily red number; never "over budget" red | Small (copy and card design) | New |
| Diet breaks / refeeds | Byrne et al., Int J Obes 2018 (MATADOR, 51 men with obesity): 2 wk on / 2 wk off beat continuous dieting for fat loss; Peos et al., MSSE 2021 (ICECAP, resistance-trained): no composition difference, but a 1-week break improved leg endurance, alertness and appetite | Mixed (adherence and training benefit, metabolism unclear) | Lose, after 6-8 weeks or when training load or mood drops: offer a 1-week maintenance break; not needed for gain | Small | New |
| Adherence: the logging method that lasts | Burke 2011 review (consistency of self-monitoring predicts loss); Berry 2021 Obes Rev (digital self-monitoring works); Turner-McGrievy 2013 and other app-vs-paper trials **(unverified this round)** | Moderate | Reward *consistency* (days logged) not accuracy; make partly-logged days visible (the app already detects them) | Small | New |

## 3. Micronutrients worth tracking from Cronometer data

| Nutrient | Evidence for athletes | What the app can say from intake | What needs a blood test |
|---|---|---|---|
| **Iron** | Deficiency common in women and endurance athletes; lowers performance via haemoglobin and tiredness (Sim et al., Eur J Appl Physiol 2019; staged by ferritin, with <35 µg/L as a cut-off in the review) | "Intake has averaged X% of target"; pair plant iron with vitamin C, keep coffee/tea away from meals (Rogerson 2017) | Ferritin, haemoglobin, transferrin saturation. Never suggest supplements from intake alone (iron overload risk); the Labs module already has the markers, link them |
| **Vitamin D** | Biological requirement, not an ergogenic aid; indoor and winter training raise risk (Owens 2018) | Food rarely covers it; mention daylight minutes and season | 25(OH)D |
| **Magnesium** | Most people fall short; evidence for sleep and performance is small and inconclusive (reviews 2021-2025) | Flag low intake (already); do not promise sleep gains | Serum Mg is a poor marker; not needed |
| **Calcium** | Bone under heavy training, with vitamin D | Intake flag (already) | None routinely |
| **B12** | Essential for vegans; deficiency causes fatigue and neuropathy (Rogerson, JISSN 2017: supplement or fortified foods) | If diet is plant-based: "supplement, intake from food is zero" | B12, MMA if symptoms |
| **Zinc** | Athletes often have lower serum zinc despite similar intake; performance effect mixed | Intake flag (already); upper limit 40 mg | Not routinely |
| **Omega-3 index** | ISSN 2025: athletes often insufficient | Intake of EPA+DHA if Cronometer exports it (**check**) | Omega-3 index (dried blood spot) optional |
| **Sodium/potassium** | Sweat losses; blood pressure | Already | None |

General rule from the micronutrient reviews found: supplementing well-nourished athletes does
not improve performance; correcting a measured deficiency does. So the app's wording "may be
low" is right, and the next step should always be "check with a blood test" for iron, vitamin D
and B12, which the Labs screen can then interpret.

## 4. Features other nutrition apps have

| App feature | Evidence | Verdict for Tensile |
|---|---|---|
| **MacroFactor expenditure algorithm + dynamic targets** | Vendor-published only: weight-change prediction r = 0.87 vs r² 0.35 for formulas; no independent peer-reviewed validation. The method (smoothed weight trend vs logged intake) is sound and is what Tensile's `AdaptiveTDEE` already does, including the partly-logged-day and creatine handling MacroFactor is criticised for lacking | **Already have.** Add the weekly target update (section 2) to close the loop |
| **Cronometer nutrient scores / targets** | Based on DRIs, same as `Micronutrients.swift` | Keep in Cronometer; Tensile adds the "why it matters for training" layer |
| **Noom colour system (green/yellow/red by calorie density)** | Chin et al., Sci Rep 2016: retrospective, 35,921 users, 78% lost some weight; a 2026 company-funded RCT (n=427) reports 4.05% loss at 68 weeks vs +1.46% control, with self-reported weights; evidence for the colour system itself is thin (one association with adherence) | **Skip.** Calorie density is a real lever (Hall 2019 UPF trial supports it) but the colours add judgement without evidence; a UPF share is the better version if food names become available |
| **MyFitnessPal meal reminders** | Consistent self-monitoring predicts weight loss (Burke 2011); evidence that reminders themselves raise logging adherence was **not verified this round** | **Small win:** one "nothing logged yet today" nudge at ~2 pm on days with no Cronometer samples, using the observer query already registered for `dietaryEnergyConsumed` |
| **Zoe: personalised responses, CGM for non-diabetics** | PREDICT 1 (Berry et al., Nat Med 2020, n=1,002): large between-person variation in post-meal glucose, triglycerides and insulin; model predicts glucose r = 0.77. Zoe METHOD RCT (n=347, 18 wk) reported modest benefits of personalised advice. For CGM in people without diabetes, no outcome evidence was found; a small 4-week trial reported modest, non-lasting diet changes | **Skip** (consistent with the October review's "glucose spike scores" verdict). If a CGM is ever added, treat it as an experiment, not a score |
| **Passio-style photo logging** | See section 1 accuracy table | Optional fallback only, via Claude on Supabase |

## References

Verified in this round (title/authors/journal/year seen in a search result):

- Schoenfeld BJ, Aragon AA. How much protein can the body use in a single meal for muscle-building? Implications for daily protein distribution. *J Int Soc Sports Nutr* 2018;15:10.
- Morton RW et al. A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength. *Br J Sports Med* 2018;52:376-384. (already cited in code)
- Moore DR et al. Ingested protein dose response of muscle and albumin protein synthesis after resistance exercise in young men. *Am J Clin Nutr* 2009;89:161-168.
- Moore DR et al. Protein ingestion to stimulate myofibrillar protein synthesis requires greater relative protein intakes in healthy older versus younger men. *J Gerontol A* 2015;70:57-62.
- Kerksick CM et al. International Society of Sports Nutrition position stand: nutrient timing. *J Int Soc Sports Nutr* 2017;14:33.
- Aragon AA, Schoenfeld BJ. Nutrient timing revisited: is there a post-exercise anabolic window? *J Int Soc Sports Nutr* 2013;10:5.
- Burke LM, Hawley JA, Wong SHS, Jeukendrup AE. Carbohydrates for training and competition. *J Sports Sci* 2011;29(S1):S17-S27.
- Helms ER, Aragon AA, Fitschen PJ. Evidence-based recommendations for natural bodybuilding contest preparation: nutrition and supplementation. *J Int Soc Sports Nutr* 2014;11:20.
- Aragon AA et al. International Society of Sports Nutrition position stand: diets and body composition. *J Int Soc Sports Nutr* 2017;14:16.
- Reynolds A et al. Carbohydrate quality and human health: a series of systematic reviews and meta-analyses. *Lancet* 2019;393:434-445.
- Kreider RB et al. International Society of Sports Nutrition position stand: safety and efficacy of creatine supplementation in exercise, sport, and medicine. *J Int Soc Sports Nutr* 2017;14:18.
- Guest NS et al. International Society of Sports Nutrition position stand: caffeine and exercise performance. *J Int Soc Sports Nutr* 2021;18:1.
- Owens DJ, Allison R, Close GL. Vitamin D and the athlete: current perspectives and new challenges. *Sports Med* 2018;48(Suppl 1):3-16.
- Sim M et al. Iron considerations for the athlete: a narrative review. *Eur J Appl Physiol* 2019;119:1463-1478.
- Rogerson D. Vegan diets: practical advice for athletes and exercisers. *J Int Soc Sports Nutr* 2017;14:36.
- Jäger R et al. International Society of Sports Nutrition position stand: long-chain omega-3 polyunsaturated fatty acids. *J Int Soc Sports Nutr* 2025;22(1):2441775.
- Mountjoy M et al. 2023 International Olympic Committee's (IOC) consensus statement on Relative Energy Deficiency in Sport (REDs). *Br J Sports Med* 2023;57:1073-1097.
- Hall KD et al. Ultra-processed diets cause excess calorie intake and weight gain: an inpatient randomized controlled trial of ad libitum food intake. *Cell Metab* 2019;30:67-77.
- Conlin LA et al. Flexible vs. rigid dieting in resistance-trained individuals seeking to optimize their physiques: a randomized controlled trial. *J Int Soc Sports Nutr* 2021;18:52.
- Smith CF, Williamson DA, Bray GA, Ryan DH. Flexible vs. rigid dieting strategies: relationship with adverse behavioral outcomes. *Appetite* 1999;32:295-305.
- Byrne NM et al. Intermittent energy restriction improves weight loss efficiency in obese men: the MATADOR study. *Int J Obes* 2018;42:129-138.
- Peos JJ et al. Continuous versus intermittent dieting for fat loss and fat-free mass retention in resistance-trained adults: the ICECAP trial. *Med Sci Sports Exerc* 2021;53:1685-1698; and the pre-specified secondary analysis, *PLoS One* 2021;16:e0247292.
- Burke LE, Wang J, Sevick MA. Self-monitoring in weight loss: a systematic review of the literature. *J Am Diet Assoc* 2011;111:92-102.
- Berry R et al. Does self-monitoring diet and physical activity behaviors using digital technology support adults with obesity or overweight to lose weight? A systematic literature review with meta-analysis. *Obes Rev* 2021;22:e13306.
- Zheng Y et al. Self-weighing in weight management: a systematic literature review. *Obesity* 2015;23:256-265.
- Madigan CD et al. Is self-weighing an effective tool for weight loss: a systematic literature review and meta-analysis. *Int J Behav Nutr Phys Act* 2015;12:104.
- Chin SO et al. Successful weight reduction and maintenance by using a smartphone application in those with overweight and obesity. *Sci Rep* 2016;6:34563.
- Berry SE et al. Human postprandial responses to food and potential for precision nutrition. *Nat Med* 2020;26:964-973.
- Ho DKN et al. Validity of image-based dietary assessment methods: a systematic review and meta-analysis. *Clin Nutr* 2020;39:2945-2959.
- O'Hara C et al. An evaluation of ChatGPT for nutrient content estimation from meal photographs. *Nutrients* 2025;17(4):607.
- Image-based dietary energy and macronutrients estimation with ChatGPT-5: cross-source evaluation across escalating context scenarios. *Nutrients* 2025 (PMC12655113).
- Image-based nutritional assessment: evaluating the performance of ChatGPT-4o on simple and complex meals. *Clin Nutr ESPEN* / ScienceDirect 2025 (S088915752501659X).
- Dietary assessment with multimodal ChatGPT: a systematic analysis. arXiv:2312.08592 (2023).
- Soares MJ et al. The interplay between evening latency and sleep-disturbing diet on sleep quality among adults. *J Hum Nutr Diet* 2025.
- Chrono-nutrition and sleep: lessons from the temporal feature of eating patterns in human studies, a systematic scoping review. *Sleep Med Rev* 2024.
- Time-restricted eating and sleep, mood, and quality of life in adults with overweight or obesity: a secondary analysis of a randomized clinical trial. *JAMA Netw Open* 2025.
- Healthy Eating Index-2020: review and update process. *J Acad Nutr Diet* 2023.

Not verified this round (do not quote in app copy until checked): Impey 2018 "fuel for the work
required" carbohydrate periodisation; Mamerow 2014 even protein distribution; Baker 2017 sweat
sodium ranges; Steinberg 2015 daily weighing; Turner-McGrievy 2013 app vs paper diaries;
Toro-Ramos 2020 Noom; a 2024-2025 review of CGM in people without diabetes; the exact ISSN
omega-3 dose; Cronometer's exact Apple Health export list and whether it stamps meal times.

Vendor and licence sources: USDA FoodData Central API guide (public domain / CC0, 1,000 req/h,
credit requested, exposed keys deactivated); Open Food Facts data and terms pages (ODbL, DbCL,
CC BY-SA images, attribution in-app, share-alike for adapted databases, User-Agent); Nutritionix
API page (Starter $499/mo, attribution, MAU pricing); FatSecret platform editions (Basic 5,000
calls/day with attribution, Premier Free, Premier quoted); Edamam developer pages (free basic
plan, attribution, caching limits); Spoonacular pricing page; Passio pricing and token docs;
CalorieNinjas retirement notice; Cronometer help centre (Timestamps, Mobile display) and forum
threads on Apple Health timestamps; Apple HealthKit documentation for `HKMetadataKeyFoodType`
and `HKCorrelationTypeIdentifierFood`; Kodeco/Apple forum material on VisionKit barcode
symbologies.

## 5. Protein and the calorie budget (November 2026)

**Problem.** The app set protein and calories independently. For a 74 kg man at about 15 % body
fat losing weight, the protein target was 2.6 g per kg of lean mass (the middle of Helms' 2.3-3.1
range) ≈ 164 g, and 2.2 g/kg of body weight without a body-fat reading ≈ 163 g. On a 1,700 kcal
target that is 650-670 kcal, about 40 % of the day. With fat held at 0.7 g/kg (52 g, 466 kcal) only
about 560 kcal were left for carbohydrate, about 140 g or 1.9 g/kg, under the 2 g/kg a lifter
needs on a rest day. The user's own words: "168 grams of protein on 1,600-1,800 calories is very
hard and almost impossible."

**What the evidence says.**

- Morton et al., *Br J Sports Med* 2018 (meta-analysis, 49 RCTs, n = 1,863): protein beyond a total
  of about **1.62 g/kg/day** (95 % CI 1.03-2.20) gave no further gain in fat-free mass with
  resistance training. The breakpoint is imprecise, but there is no evidence of benefit above the
  upper CI of 2.2 g/kg.
- Helms, Zinn, Rowlands & Brown, *IJSNEM* 2014 (systematic review of resistance-trained, lean
  people in a deficit, **six studies**): protein of **2.3-3.1 g per kg of fat-free mass**, higher
  with leanness and the depth of the deficit. Henselmans' re-analysis of the same studies argues
  the case for the top of that range is weak; the authors' own thesis puts energy balance above
  protein as the driver. A 74 kg man at 15 % fat (62.9 kg FFM) lands at 145-195 g.
- Phillips & Van Loon, *J Sports Sci* 2011: **1.8-2.0 g/kg of body weight**, "depending on the
  caloric deficit", to limit lean-mass loss while dieting (the 1.8-2.7 g/kg figure often quoted
  comes from the 2014/2015 Murphy, Hector & Phillips follow-up).
- Jäger et al., ISSN position stand on protein, *JISSN* 2017: 1.4-2.0 g/kg for building and keeping
  muscle; 2.3-3.1 g/kg FFM may be needed in hypocaloric periods for resistance-trained people
  (citing Helms 2014).
- Fat: Helms, Aragon & Fitschen, *JISSN* 2014 recommend **15-30 % of calories** from fat for dieting
  lifters, carbohydrate making up the rest. Iraki et al., *Sports* 2019 give 0.5-1.5 g/kg for
  lifters at or above maintenance **(m) not re-verified this round**.
- Carbohydrate: Burke et al., *J Sports Sci* 2011 give 3-5 g/kg for light or skill-based days (the
  app's training-day lifter band); the app's rest-day band of 2-3 g/kg is an app choice under
  that. The Institute of Medicine's RDA for carbohydrate (2005) is 130 g/day for everyone. Kerksick
  et al.'s ISSN nutrient-timing stand (2017) quotes 5-12 g/kg for athletes in general and 8-12 g/kg
  to maximise glycogen; its lower bands for light training were not found in this round, so the
  floor below leans on Burke 2011 and the IOM RDA.
- No 2024 umbrella review on the dose-response in trained people was found; the closest are Morton
  2018 and a 2020 dose-response meta-analysis (Tagawa et al., *Nutr Rev*) showing small gains per
  0.1 g/kg with diminishing returns.

**Decision (`MacroSplit` in AppCore).** The calorie target stays; the macros are made to fit it.

1. Fat floor **0.7 g/kg** of body weight (app choice inside Helms' 15-30 %: 27 % of a 1,700 kcal
   day for a 74 kg man, 17 % of a 2,800 kcal day for an 80 kg man).
2. Carbohydrate floor **2.0 g/kg** when lifting (muscle or strength focus, or losing weight), and
   never under the 130 g RDA; 130 g for everyone else.
3. Protein is the goal's target (`GoalPlanner.proteinGrams`) when it fits alongside those floors.
   When it does not, it steps down to the **bottom of the deficit range**: 2.3 g/kg FFM (Helms
   2014) with a body-fat reading, else 2.0 g/kg of body weight (Phillips & Van Loon 2011; Jäger
   2017). If even that leaves no room, protein is cut to what fits but **never under 1.6 g/kg**
   (Morton 2018), and the day is flagged `tooFewCaloriesForFloors` so the UI says the calorie
   target, not protein, is the problem (pick a slower rate). A medication floor (e.g. 2.0 g/kg on
   GLP-1 drugs) is kept even when it breaks the carb floor, with the flag set.
4. Above the floors, fat sits at 25 % of calories (inside Helms' range) and carbs take the rest.

For the user's case (74 kg, 15 % fat, lose, 1,700 kcal) this gives **protein 145 g (34 % of
calories), carbs about 163 g (2.2 g/kg), fat 52 g**; at 2,800 kcal gaining nothing is capped
(128 g protein, 78 g fat, about 396 g carbs); at 1,200 kcal protein is held at 118 g (1.6 g/kg) and
the day is flagged. Honest summary for the UI: above about 1.6 g/kg more protein adds little; on a
cut 1.8-2 g/kg body weight (≈ 2.3 g/kg lean mass) keeps muscle and leaves room for carbs to train;
the evidence for the top of the range comes from a few small studies.

Sources checked this round: PubMed 24092765 (Helms 2014 IJSNEM); bjsm.bmj.com/content/52/6/376
(Morton 2018); JISSN 14:20 (Jäger 2017); PMC4033492 (Helms, Aragon & Fitschen 2014); PMC5596471
(Kerksick 2017); Phillips & Van Loon 2011 abstract (DOI 10.1080/02640414.2011.619204);
Henselmans, "Eric Helms & protein: a research review" (blog, not peer reviewed).
