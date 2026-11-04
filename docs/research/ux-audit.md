# UX audit and simplification plan (November 2026)

Scope: every iPhone screen in `App/Features` and the design system in `App/Design`,
checked against Apple's current Human Interface Guidelines (iOS 26, Liquid Glass),
Nielsen Norman Group guidance, research on presenting health numbers to lay people,
and what comparable apps do. The mockups in `docs/mockups/` are the visual reference.
Nothing here changes code; section 6 is the build plan.

**How the sources were checked.** The HIG pages were downloaded from Apple's own
documentation data on 4 November 2026 (tab bars, modality, sheets, materials, layout,
typography, accessibility, buttons, charts, color, writing, onboarding, lists and
tables, toolbars, search fields), and the WWDC25 session 356 transcript was read
from developer.apple.com. Quotes marked "HIG" are verbatim. **nngroup.com is blocked
in this sandbox**, so NN/g articles were confirmed through search results (title,
URL, quoted snippets) but not read in full; claims from them are marked *(via
search)* or *(from memory, not re-read)*. Research papers were confirmed by title,
authors, journal and key numbers through search.

**Line numbers** refer to commit `b079cac`. An uncommitted calorie change being
made in parallel adds about 30 lines to `TodayView.swift` after line 941
(`CalorieDetailsSheet` notes), so `HealthMonitor` and `MonitorTile` sit roughly
28 lines lower than quoted; `CalorieDetailsSheet` also gains a third duplicated
advice block (resting-energy method, pace, cycle note). Other files are unaffected.

Evidence labels used below:

- **Research**: controlled experiments, meta-analyses, eye-tracking or usability
  studies with measured outcomes.
- **Guideline**: expert or platform guidance (HIG, NN/g heuristics) based on
  practice, not on a trial.
- **Convention**: what leading apps ship; tells you what users have learned, not
  what works best.

---

## 1. Summary

**The five biggest problems**

1. **Home is a feed of 13 to 16 cards plus 8 tiles** (`TodayView.swift` 22–45) where
   the mockup had 4 sections. Strain appears twice on Home and again on Fitness;
   sleep three times on Home; three to five filled gradient buttons compete for
   "the" action. Research on lay health displays says fewer, better-labelled
   numbers are understood better (Peters et al. 2007), and HIG says to order by
   importance and use progressive disclosure.
2. **The Add tab is a flat list of 15 identical cards that mix three different jobs**
   (start a workout, log a measurement, manage setup) with no grouping, no
   primary action, sheets and pushes that look the same, and arbitrary colours
   (`QuickAddView.swift` 22–77). It is also wired as the tab bar's *search* tab
   (`WorkoutAppApp.swift` 179), which HIG reserves for search: "Use a tab bar to
   support navigation, not to provide actions."
3. **Features have no single home.** My Gym is reachable from 4 places, the weekly
   plan from Home and Add, history from Fitness and Add, medications from Home,
   Add and Settings; the "start a workout" action has 7 entry points with 7
   different labels ("Build a workout", "Plan a workout", "Start", "Empty",
   "Start empty", "Create a workout", "Rather do your own?").
4. **Every tab hides the system navigation bar and draws its own title and glass
   buttons inside the scroll content** (`TodayView` 56, `FitnessView` 68,
   `CoachView` 75, `BiologyView` 100). That loses the iOS 26 large-title collapse,
   the scroll-edge effect and the standard toolbar glass, and puts Liquid Glass in
   the content layer, which HIG says not to do. Settings is only reachable from
   Home.
5. **Inconsistent card anatomy, type and colour.** Four header styles, hero numbers
   at 24/30/32/34/48/52/60 pt (16 of them fixed sizes that ignore Dynamic Type),
   the sleep indigo used for alcohol, labs, gym, check-in and habits, and caption
   text in accent colours below 4.5:1 contrast.

**Proposed information architecture** (section 4): four tabs, each with one job and
one primary element, plus a "+" button in every tab's navigation bar that opens a
short, grouped **Log** sheet.

| Tab | Job, in one sentence | Primary element |
|---|---|---|
| **Today** | How am I today, and what's the one thing to do next? | Scores card: three rings, one coaching line, one action |
| **Fitness** | Plan, start and see the progress of my training. | This week card with today's session and **Start** |
| **Coach** | Ask about my data and get a workout. | The conversation |
| **Health** | My long-term trends and my health records. | HRV baseline chart, then key measures as rows |

---

## 2. Principles, sources and evidence strength

### 2.1 Navigation and structure

| # | Principle | Source | Strength |
|---|---|---|---|
| P1 | **Tab bars are for navigation, not actions.** "Use a tab bar to support navigation, not to provide actions… If you need to provide controls that act on elements in the current view, use a toolbar instead." The trailing, separated tab slot is for search: "A tab bar can include a dedicated search tab at the trailing end." | HIG *Tab bars*; WWDC25 *Get to know the new design system* (356): "Tab bars should be well-structured, with a dedicated Search tab…" | Guideline |
| P2 | **Fewer tabs are easier**; avoid overflow. "It's generally easier to navigate among fewer tabs." Keep a default of "five or fewer". Don't hide or disable tabs. Single-word labels. | HIG *Tab bars* | Guideline |
| P3 | **Keep important destinations visible.** Hidden navigation was less discoverable and gave worse task metrics than visible or combined navigation on phones and desktop (179 participants). A long list of equally weighted rows is a soft version of hiding: items below the fold are found less. | Pernice & Budiu, NN/g, *Hamburger Menus and Hidden Navigation Hurt UX Metrics*, 2016 *(via search)* | Research (usability study) |
| P4 | **Tab bar accessory is for persistent features**, like Music's mini-player; "Avoid placing screen-specific actions here." A workout in progress is exactly such a persistent feature. | WWDC25 356; HIG *Tab bars* (iOS) | Guideline |
| P5 | **Modality only with a clear benefit**; keep modal tasks "simple, short, and streamlined"; avoid "a modal experience that feels like an app within your app"; "Display only one sheet at a time"; dismiss with Cancel (leading) / Done (trailing); "The Back button… isn't intended to dismiss a sheet"; full-screen for complex, multistep or immersive tasks. | HIG *Modality*, *Sheets* | Guideline |
| P6 | **Push for drilling into content, sheet for a short task.** Lists that navigate a hierarchy use the chevron; a row that opens a sheet should look different (no chevron, or a "+" / form affordance). | HIG *Lists and tables*, *Sheets* | Convention / guideline |
| P7 | **Order by importance, group, disclose progressively.** "Place the most important items near the top"; "Group related items"; "An interface with too much content and too many choices makes it harder to find information quickly… Use disclosure triangles, menus, or nested views to reduce how much content to initially display." | HIG *Layout* | Guideline |
| P8 | **Progressive disclosure** defers secondary options to a subsidiary screen; it needs "the right split between initial and secondary features" and an obvious path between levels. NN/g claims it improves learnability, efficiency and error rate; controlled studies are sparse. | Nielsen, NN/g, *Progressive Disclosure* (2006) *(via search)* | Guideline (practitioner evidence) |
| P9 | **Onboarding: postpone nonessential setup**, provide defaults, prefer context-specific tips over a setup flow. | HIG *Onboarding* | Guideline |

### 2.2 Choice, scanning and dashboards

| # | Principle | Source | Strength |
|---|---|---|---|
| P10 | **"Too many choices" is real but conditional.** A meta-analysis of 63 conditions (N = 5,036) found a mean choice-overload effect near zero with high heterogeneity; a later one (99 observations, N = 7,202) found it appears when the choice set is complex, the task is hard, preferences are uncertain and the person wants to minimise effort. Design implication: don't just delete options; reduce effort with **grouping, a recommended default and clear labels**. | Scheibehenne, Greifeneder & Todd, *J Consumer Research* 2010; Chernev, Böckenholt & Goodman, *J Consumer Psychology* 2015 | Research (meta-analyses; mixed) |
| P11 | **Hick–Hyman law**: choice reaction time rises with the log of the number of equally likely options. It comes from lab reaction-time tasks; in real menus visual search and reading dominate, and familiar, well-ordered lists are less affected. Use it as a reason to group and order, not as a hard limit on rows. | Hick 1952; Hyman 1953 *(from memory, not re-read)*; IxDF summary *(via search)* | Research (lab), weak transfer to apps |
| P12 | **Dashboards are for fast consumption**, using preattentive cues; length and position are judged more accurately than area and angle. Rings and arcs (angle) suit "one value against its goal", not comparisons between values. | NN/g, *Dashboards: Making Charts and Graphs Easier to Understand* *(via search)*; Cleveland & McGill, *JASA* 1984 *(from memory)* | Research (graphical perception) |
| P13 | **Front-load content and labels** (inverted pyramid; F-pattern scanning: people read the top and the left edge, then skim). The first words of a card title and the first line of text carry the message. | Pernice, NN/g, *F-Shaped Pattern of Reading on the Web: Misunderstood, But Still Relevant* 2017 *(from memory)* | Research (eye-tracking), web-derived |
| P14 | **The 10 usability heuristics**, especially *consistency and standards*, *recognition rather than recall*, *aesthetic and minimalist design* ("every extra unit of information competes with the relevant units") and *user control and freedom*. | Nielsen 1994, NN/g *(from memory)* | Guideline (derived from analysis of usability problems) |
| P15 | **Charts**: give each chart a title that states its main message; "don't require interaction to reveal critical information"; make every chart accessible; don't use colour alone. | HIG *Charts* | Guideline |

### 2.3 Health numbers for lay users

| # | Principle | Source | Strength |
|---|---|---|---|
| P16 | **Less is more for lay health information.** In three experiments, people given less information understood the key cost and quality data better and chose better; making only the most important measure easier to evaluate improved choices; effects were largest for less numerate people. | Peters, Dieckmann, Dixon, Hibbard & Mertz, *Med Care Res Rev* 2007;64:169 | Research (experiments, moderate) |
| P17 | **Evaluative context reduces false alarm.** Adding a "harm anchor" (where a value becomes clinically concerning) to test-result displays cut the share who wanted urgent care for near-normal values from 56% to 35% (N = 1,618) without changing responses to truly extreme values. For the app: show normal ranges and plain verdicts ("Normal", "Slightly above your usual") next to numbers, and reserve warning colours for values that matter. | Zikmund-Fisher et al., *JMIR* 2018;20(3):e98 | Research (online experiment) |
| P18 | **Visual formats help people with low numeracy**; icon arrays and simple bars improve accuracy across numeracy levels. | Zikmund-Fisher, Fagerlin et al. pictograph studies (e.g. *Med Decis Making* 2014) | Research |
| P19 | **Health data can raise anxiety and care-seeking.** In 172 patients with atrial fibrillation, wearable users used more AF care and informal contact; ~20% reported anxiety and always contacted their doctor after alerts. Observational, one population, but it fits the app's own nocebo notes (`behaviour-change.md` §454–459). Design: calm defaults, few red/amber states, no badges for normal variation. | Rosman et al., *J Am Heart Assoc* 2024 (doi 10.1161/JAHA.123.033750) | Research (observational) |
| P20 | **Industry pattern: one front page, details on demand.** Oura (Oct 2025) cut five tabs to three (Today, Vitals, My Health), with scores at the top of Today acting like a news "Top Stories" page. WHOOP (2025) puts three dials at the top of Home, each opening a deep-dive page, with a Health Monitor tile that drills in and user-reorderable tiles. Gentler Streak's iOS 26 update shows "single Today's Recommendations… more inviting and easier to act on". Apple Health's Summary shows a user-pinned list plus Highlights, with the full list one level down. | ouraring.com blog *New Oura app experience*; whoop.com *The all-new WHOOP home screen*; Gentler Streak App Store notes; Apple Support *Use the Health app* | Convention (vendor claims, no outcome data) |

### 2.4 Visual design, type and accessibility

| # | Principle | Source | Strength |
|---|---|---|---|
| P21 | **Liquid Glass is for the controls layer.** "Don't use Liquid Glass in the content layer"; "Use Liquid Glass effects sparingly." WWDC25: "Remove background colors from custom toolbars and tab bars. Rely on layout and grouping to express hierarchy rather than unnecessary decoration." | HIG *Materials*; WWDC25 356 | Guideline |
| P22 | **Use built-in text styles** so Dynamic Type works; keep the hierarchy at large sizes; support at least 200% enlargement. | HIG *Typography*, *Accessibility*; WCAG 2.2 1.4.4 | Guideline / standard |
| P23 | **Hit targets ≥ 44 × 44 pt**; ~12 pt spacing around bezelled controls, ~24 pt around unbezelled ones. | HIG *Accessibility*, *Buttons* | Guideline (backed by touch-target studies) |
| P24 | **Contrast ≥ 4.5:1** for text (3:1 for large/bold ≥ 14 pt bold or 18 pt); check light and dark. | WCAG 2.2 1.4.3; HIG *Accessibility* | Standard |
| P25 | **Colour has one meaning.** "Avoid using the same color to mean different things"; don't rely on colour alone. | HIG *Color*, *Charts* | Guideline |
| P26 | **Writing**: verbs on buttons; "Use possessive pronouns sparingly… use them consistently"; empty states give "clear next steps". | HIG *Writing* | Guideline |
| P27 | **VoiceOver grouping**: a card that is one idea should be one accessibility element with a summary label and a hint for what tapping does. | HIG *Accessibility*; Apple accessibility docs | Guideline |

---

## 3. Audit, screen by screen

Contents are listed in on-screen order. "*" marks items that show only under a
condition.

### 3.1 Home (`App/Features/Today/TodayView.swift`)

**On screen** (lines 22–45):

1. Custom header: logo, sync status, glass gear button, date, greeting (66–89)
2. Resume workout banner* (24–26, struct 151–177)
3. Apple Health access card* (27–29, 179–206)
4. Illness alert / rest mode* (`IllnessAlertCard.swift`)
5. **Scores card**: strain, recovery, sleep rings + coaching line (210–291)
6. **This week** consistency card: week dots, today's slot, Start / Short version, Review, Plan this week (`ConsistencyCard.swift` 12–120)
7. Sleep debt* with bedtime window (`SleepDebtCard.swift` 5–81)
8. Set your goals* (479–510)
9. Daily check-in: Morning / Evening gradient buttons + advice (687–731)
10. Weather, or "Add your city" (583–683)
11. **Strain range** card: 48 pt hero strain, bar, range note, breathing offer, 1–3 suggestion rows, gradient "Plan a workout" button (301–475)
12. Medications today* (736–761)
13. Calories / nutrition: ring, target, band, paragraph, macros (771–940)
14. Water, or "Log water in your food app" (514–579)
15. Daily habits: caffeine, protein, weight, weigh-in, cut × sleep, energy availability, movement (`HabitsCard.swift`)
16. Health Monitor: 8 tiles (RHR, HRV, breathing, sleep, SpO₂, HR recovery, HR above resting, steps) (1061–1206)
17. Ask your coach: 3 suggestion buttons (98–121)

**Problems**

| # | Problem | Where | Principle |
|---|---|---|---|
| H1 | **Card overload.** On a normal day with data: ~13 cards and 8 tiles, roughly 7–8 screen heights. The mockup (`01-today.png`) has 4 sections: scores, strain goal, nutrition, 4 monitor tiles. | body 22–45 | P7, P14, P16, P20 |
| H2 | **Competing primaries.** Filled gradient buttons in the strain card ("Plan a workout", 414–426), the consistency card ("Start", "Plan this week"), and both check-in buttons (715–729); a 48 pt hero number in the strain card competes with the score rings above it. | 301–475, 687–731, `ConsistencyCard` 216–234 | P7, P13 |
| H3 | **Strain twice on Home** (ring in Scores card + Strain range card) and again on Fitness (`DayStrainCard`, week strip) and in Coach chips. | 219–228, 301–385 | P14 (minimalist), P16 |
| H4 | **Sleep three times**: Sleep ring, Sleep debt card, Health Monitor sleep tile; the sleep-debt card and the ring both open `LastNightSleepSheet`. | 247–260, `SleepDebtCard`, 1190–1205 | P16 |
| H5 | **Same advice in two places**: cut × sleep debt and low energy availability appear in `HabitsCard` (48–55) and in `CalorieDetailsSheet` (976–988). | | P14 |
| H6 | **Ask-coach card duplicates the Coach tab's empty state**, which already lists the suggestions (`CoachView` 139–160). | 98–121 | P14 |
| H7 | **Empty-state pile-up.** A new user sees up to seven setup prompts at once: Set goals, Add your city, "No range yet", "No plan for this week yet" (two buttons), "Log water in your food app", "No food logged yet", eight "No data" tiles. HIG: postpone nonessential setup; one clear next step. | 313–321, 628–648, 530–537, 810–824, 1246–1250 | P9, P26 |
| H8 | **Detail that belongs one level down**: hydration formula (572), calorie paragraph (873), strain range note (377–384), weather sunrise/sunset/daylight pills (608–617). | | P8 |
| H9 | **Weather is a daily card** although it changes advice only on hot, high-UV or poor-air days. | 583–683 | P7 |
| H10 | **Health Monitor shows 8 tiles**, 4 of which (SpO₂, HR recovery, HR above resting, steps) are Biology stats, not "is something off today" signals. Mockup: 4. | 1078–1085 | P16, P20 |
| H11 | **Inconsistent card anatomy**: headers are uppercase `CardLabel` (strain, water), `Label` with gradient text (Ask coach 100–102), `SectionTitle` (Health Monitor); `MonitorTile` draws its own background at radius 22 vs `.card()` at 26 (1276–1284); six different tint glows. | | P14 (consistency), P21 |
| H12 | **Custom header with hidden nav bar** and a glass gear button inside the scroll content; Settings is only reachable here. | 56, 66–89 | P21, P3 |
| H13 | **Unclear or inconsistent labels**: "Strain range" / "Range" / "planned range" / "target"; "HR above resting" (Home) vs "Heart rate above resting" (Biology); "Daily habits" is a mix of nutrition, weight and movement. | 314, 347, 1083 | P26, P14 |

### 3.2 Fitness (`App/Features/Fitness/FitnessView.swift`, `TrainingCards.swift`, `MuscleMap.swift`)

**On screen** (lines 15–57): custom title + calendar glass button (history) → week
strip → Day strain gauge (121–216) → Deload* (417–458) → section "Cardio fitness ·
90-day trend" → VO₂ max card (`TrainingCards` 319–445) → Weekly minutes* (226–264)
→ **Your workouts** row: My workouts + Empty (8–51) → section "Muscles" → muscle
map (`MuscleMap` 109–) → Hard sets this week (57–129) → section "Strength · Health
floor" → Strength days (136–218) → Strength for health (453–520) → section
"Training Load · Last 7 days vs usual" → Cardio / Muscular dials (220–298) →
section "Today's Activity" → activities with Start (302–351) → section "Heart Rate
Zones" → zones (353–413).

**Problems**

| # | Problem | Where | Principle |
|---|---|---|---|
| F1 | **14 blocks under 6 section titles**; analytics, actions and research notes are interleaved. Mockup order: week → day strain → training load → activity → zones. | 15–57 | P7, P14 |
| F2 | **Duplicates Home's strain card** (range, below/in/above message, tap to plan). | 121–216 | P14 |
| F3 | **Actions in the wrong place**: "My workouts / Empty" sits between the cardio and muscles sections (41); "Start" inside the activity list (320). The weekly plan and today's planned session, the most actionable training items, live on Home. | 41, 302–324; `ConsistencyCard` | P7, P3 |
| F4 | **Research text inline in every card** (captions and caption2 citations): sets 83, minutes 256, VO₂ max 336, strength-for-health 473, deload 448–454 (two citation lines). CLAUDE.md requires evidence notes in the UI, but they can sit in an "About this number" section of the detail view. | `TrainingCards` | P8, P13 |
| F5 | **Section titles with puzzling trailing text** ("Strength · Health floor", "Cardio fitness · 90-day trend") and sections holding one card. | 36, 45, 48 | P26 |
| F6 | **History is only an unlabeled calendar icon** (and a row in Add). | 22–27 | P3 |
| F7 | **Fixed type**: 10 pt numbers in the week-strip rings (99), 32 pt in load dials (243). | | P22 |
| F8 | Zones card explains itself in prose ("numbers under each bar are bpm", 372). | | P15 |

### 3.3 Coach (`App/Features/Coach/CoachView.swift`)

**On screen**: custom title with menu (New conversation, My Gym) → subtitle →
horizontally scrolling context chips → empty state with suggestions, or messages
with plan cards → follow-ups → input bar.

The chat itself is in good shape (clear empty state with suggestions, plan cards
that start a workout).

| # | Problem | Where | Principle |
|---|---|---|---|
| C1 | **My Gym in the chat menu** (fourth entry point for a setup screen). The empty state tells people to find it "menu, top right". | 100–106, 144–146 | P14 |
| C2 | Custom header with hidden nav bar; "New conversation" belongs as a toolbar button (compose icon). | 75, 87–113 | P21 |

### 3.4 Biology (`App/Features/Biology/BiologyView.swift`)

**On screen** (25–84): custom title "Biology · Your long-term baselines" → Body
age (373–446) → Progress photos (598–645) → Lab results (`LabsView` 7–45) → What
affects you (491–528) → How alcohol affects you (`AlcoholEffectCard`) → HRV
baseline chart (202–276) → Vitamins & minerals (530–596) → five sections (Heart,
Sleep, Breathing & temperature, Activity, Body) of 2-column tiles, ~30 tiles in all
including protein, waist-to-height and grip, plus a STOP-Bang card → "Using a
Garmin?" disclosure.

| # | Problem | Where | Principle |
|---|---|---|---|
| B1 | **Wrong primary.** Body age leads the page, though the app's own research flags it as a nocebo risk when older than real age (`behaviour-change.md` 459). The mockup (`04-biology.png`) leads with the HRV baseline, then five biomarker rows. | 36 | P16, P19 |
| B2 | **A wall of ~30 equal tiles**, each with its own colour, status chip and sparkline, all at the same weight. "No data" tiles are shown. | 43–67 | P7, P8, P16 |
| B3 | **Three kinds of content mixed**: records you add (photos, labs, waist, grip, BP), patterns (check-in insights, alcohol, micronutrients) and live measures. | 36–42 | P7 |
| B4 | **Sheet on sheet**: tiles open `VitalDetailView` as a sheet (94–97), and it can open `BloodPressureView` as another sheet. | | P5 |
| B5 | **Setup help in content**: the Garmin disclosure (74–83) is configuration help. | | P7 |
| B6 | **Tab name**: "Biology" is unclear to most people and is a competitor's tab name; the subtitle "Your long-term baselines" uses jargon. | `WorkoutAppApp` 176 | P26 |
| B7 | Copy points to the old place: "add last night's value with Add HRV on the Home tab" (269). | | P14 |

### 3.5 Add (`App/Features/Trainer/QuickAddView.swift`)

**On screen** (22–77), each row the same 46 pt icon card with chevron:

1. Resume workout* (sheet-less, opens the live workout)
2. Build a workout → sheet
3. Empty workout → starts immediately
4. This week's plan → sheet
5. My workouts → **push**
6. Log overnight HRV → sheet
7. Alcohol → **push**
8. Blood pressure → sheet
9. Lab results → sheet
10. Estimate a meal → sheet
11. Body measurements → sheet
12. Progress photos → sheet
13. Medications → sheet
14. My Gym → sheet
15. Workout history → **push**

| # | Problem | Where | Principle |
|---|---|---|---|
| A1 | **Three jobs in one flat list**: start training (2, 3), log a measurement (6–12), manage setup or browse (4, 5, 13–15). No grouping or headers. | 22–77 | P7, P10 |
| A2 | **No primary action.** "Build a workout" looks like "Lab results". The most frequent job (start a session) has the same weight as a twice-a-year one. | 26–31 | P7, P10 (a recommended default lowers choice effort) |
| A3 | **Pushes and sheets look the same** (chevron on all rows); "Empty workout" starts a session with no confirmation and no visual cue that it's different. | 35–49, 71–76 | P6, P14 |
| A4 | **Long subtitles** that wrap to two lines ("Pick your training days, and what to do when the day goes wrong"; "Describe it or add a photo; Claude estimates calories and macros (±30%)"). | 32, 56 | HIG *Lists*: "Keep item text succinct" |
| A5 | **Arbitrary colours**: the sleep indigo on My workouts, Alcohol, Lab results, My Gym; nutrition teal on Body measurements and Workout history. | 38–74 | P25 |
| A6 | **Wired as the search tab** (`Tab(…, role: .search)`) to get the separated trailing "+" look. That slot is defined for search; VoiceOver and future system behaviour treat it as search. | `WorkoutAppApp` 179 | P1 |
| A7 | **Duplicated destinations**: My Gym (also Settings, builder, Coach), history (Fitness), weekly plan (Home), medications (Home, Settings), HRV (Home tile), resume banner (Home). | | P14 |
| A8 | Built as a `ScrollView` of cards rather than a grouped `List`, so it doesn't get section headers, standard row heights, or row accessibility for free. | 21 | HIG *Lists*: grouped style "uses headers, footers, and additional space to separate groups" |

### 3.6 Settings (`App/Features/Settings/SettingsView.swift`)

Sections: You → Profile → Trainer (My Gym, RPE guide, rest timer) → Reminders
(check-ins, start on Apple Watch, workout reminders, creatine, Medications) →
Sleep & rest → Nutrition → Appearance → Units → AI coach → Apple Health → About.

| # | Problem | Where |
|---|---|---|
| S1 | Only reachable from the Home header (TodayView 72). | P3 |
| S2 | **Medications** (a feature) sits under Reminders (178); **Start workouts on Apple Watch** (a training preference) sits under Reminders (164). | P7 |
| S3 | Eleven sections at one level; Appearance and Units are one-row sections. | P7 |
| S4 | No place for "Data sources" help (Garmin, Cronometer) that is currently scattered across Biology and empty states. | P9 |

### 3.7 Workout screens

| # | Problem | Where | Principle |
|---|---|---|---|
| W1 | **Builder: the escape hatch comes before the main controls.** "Rather do your own?" (a full card) sits above the focus and duration pickers. | `WorkoutBuilderView` 45–63 | P7 |
| W2 | **Sheet on sheet and an app inside a sheet**: My Gym opens as a sheet from the builder sheet (98–104, 124); My workouts (with its own editor sheet) is pushed inside the builder sheet. | 45–47, 124 | P5 |
| W3 | **Finish sheet uses "Back" to dismiss** (FinishWorkoutSheet 65–66). HIG: Back "isn't intended to dismiss a sheet". | | P5 |
| W4 | Copy points to "Add → My workouts" (ActiveWorkoutView 136, FinishWorkoutSheet 49, WorkoutDetailView 87) and "Add → Alcohol" (CheckInView 204). | | P14 |
| W5 | Fixed sizes 26/28 pt (ActiveWorkoutView 233, 773, 993). The live workout otherwise follows the guidelines well: full-screen cover, Minimize, Finish as the tinted primary, destructive actions in a menu with confirmation. | | P22 |

### 3.8 Cross-cutting

| # | Problem | Evidence |
|---|---|---|
| X1 | **Hidden nav bars + custom titles on all four tabs**, glass circles in the content layer (`GlassIcon`, ScoreRing.swift 281–291). | P21 |
| X2 | **16 fixed font sizes** (`.font(.system(size:))` without `@ScaledMetric`) across Today, Fitness, Biology, Breathing, Measurements, ActiveWorkout. | P22 |
| X3 | **Colour collisions**: `Theme.sleep` marks sleep but also check-in, habits, insights, alcohol, labs, gym and saved workouts; `Theme.lifting` marks lifting but also medications, goals, progress photos and the alcohol card. | P25 |
| X4 | **Contrast** (computed, WCAG): on white cards `Theme.oxygen` 3.7:1, `Theme.nutrition` 2.6:1, `Theme.strain` 2.6:1, `Theme.recoveryHigh` 2.3:1, `Theme.recoveryModerate` 2.2:1. `Chip` maps only five accents to darker text colours (`Theme.textColor`, Theme.swift 60–67), so chips in oxygen, nutrition, heart or sleep use the raw accent (oxygen on its 10% pill: 3.3:1). Caption-size text in these colours fails 4.5:1 (weather pills 675–682, load-card status 231–233, deload title in oxygen 426–428). `secondaryText` on the page background is 4.39:1 (fails narrowly for small text outside cards: section trailing text, date line). | P24 |
| X5 | **Seven names for starting a workout**: Build a workout (Add), Plan a workout (Home), Start (consistency card, activity card), Empty / Empty workout / Start empty, Create a workout, Rather do your own? | P14, P26 |
| X6 | **Detail presentations vary**: metric details are medium/large sheets on Home and Biology, pushes for history and saved workouts, sheets for weekly plan/review, pushes for alcohol log. | P5, P6 |
| X7 | **Possessives mixed**: My Gym, My workouts, Your workouts, your long-term baselines. | P26 |

---

## 4. Target information architecture

### 4.1 Navigation rules (apply everywhere)

1. **Four tabs**: Today, Fitness, Coach, Health. Every tab uses the system
   navigation bar with a large title (`.navigationTitle`, `.toolbar`), so the
   title collapses on scroll and bar buttons get Liquid Glass automatically. Drop
   `toolbarVisibility(.hidden)` and the in-content `GlassIcon` headers.
2. **"+" (Log) in every tab's navigation bar** (trailing), opening the Log sheet
   (4.4). Remove the `.search`-role Add tab.
   *Alternative if you want to keep the bottom "+" from the mockups:* make it an
   ordinary fifth tab called **Log** with the same grouped screen, without
   `role: .search`. This keeps the look but is still an action-like tab, so HIG
   prefers the toolbar button.
3. **Profile/settings button** (person-circle symbol) in the leading or trailing
   toolbar of Today, Fitness and Health, opening Settings as a sheet.
4. **Workout in progress** shows as a **tab bar bottom accessory**
   (`tabViewBottomAccessory`): name, timer, Resume. It replaces the two
   `ResumeWorkoutBanner`s (Home and Add). This is the Music mini-player pattern
   the HIG describes.
5. **Push** to read more about something (metric detail, history, saved
   workouts, lab marker). **Sheet** to enter or change data (log forms, editors,
   plan, settings) with Cancel leading and Save/Done trailing. **Full screen**
   for the live workout. **Never a sheet on a sheet**: inside a sheet, go deeper
   with a push in the sheet's own `NavigationStack` (My Gym from the builder,
   blood pressure from its detail).
6. Today's quick explanations (recovery contributors, last night's sleep) may stay
   as medium-detent sheets: they are peeks, not destinations. Everything on
   Health and Fitness pushes.

### 4.2 Tab purposes and primary elements

| Tab | Label | Purpose | Primary element (one) |
|---|---|---|---|
| 1 | **Today** (was Home) | How am I today, and what's the one thing to do next? | Scores card: three rings + coaching line + one contextual button |
| 2 | **Fitness** | Plan, start and track training. | This week card with today's session and Start |
| 3 | **Coach** | Ask about my data; get a workout. | Conversation |
| 4 | **Health** (was Biology) | Long-term trends and health records. | HRV baseline chart |

"Today" matches the mockup title, the README and `TodayView`. "Health" is plain
English; wherever the copy means Apple's app, it must say "Apple Health".

### 4.3 Where everything goes (nothing is deleted)

| Feature | Now | Target | Why |
|---|---|---|---|
| Scores rings + coaching | Home | Today › Scores card (primary) | P7, P20 |
| Strain range card (bar, suggestions, Plan a workout, breathing offer) | Home | **Today › tap the Strain ring → Strain sheet** (bar, range note, suggestion rows, breathing offer). The Scores card's single button carries the top suggestion. | H2, H3; one primary |
| Day strain gauge | Fitness | Fitness › Today section (gauge + activities + zones row) | Keeps the mockup gauge; strain on Today is the ring only |
| Weekly plan, consistency, Review | Home card, Add row | **Fitness › This week** (primary). Today shows today's slot as one row in Up next. | F3, A7 |
| Daily check-in | Home card | Today › Up next row ("Morning check-in · 1 min"); disappears when done | H2 |
| Medications today | Home card | Today › Up next rows for doses due; full list in Health › Records › Medications; Settings link stays as "Medication reminders" | A7, S2 |
| Sleep debt + bedtime | Home card | Today › Up next row "In bed by 22:30–23:00"; debt detail in the Sleep sheet (ring tap) and Health › Sleep | H4 |
| Habits (caffeine, movement, weigh-in) | Home card | Today › Up next rows when due | H1 |
| Habits (protein, weight changing fast, cut × sleep, energy availability) | Home card | Today › Nutrition card line (protein) and Calorie details sheet (others; already there) | H5 |
| Calories + macros | Home | Today › Nutrition card | mockup |
| Water | Home card | Today › Nutrition card, one bar row; hidden when no water is logged; target in the details sheet | H7 |
| Weather | Home card | Today › one compact **Conditions** row only when a tip applies (heat, UV ≥ 6, AQI > 100); full card in the details sheet; "Add your city" moves to the Setup card / Settings | H9 |
| Health Monitor (8 tiles) | Home | Today › 4 tiles (RHR, HRV, breathing, sleep) + "All measures" link to Health; SpO₂, HR recovery, HR above resting, steps live in Health | H10 |
| Ask your coach card | Home | Removed from Today; suggestions stay in the Coach empty state; coaching line gets an "Ask why" link that opens Coach with the question | H6 |
| Illness / rest mode, Health access error | Home | Today › single **Alert slot** above the Scores card (max one; priority: Health access > illness > rest mode) | H7 |
| Goals prompt, Add your city, Set up My Gym | Home, Builder | Today › one **Finish setting up** card (checklist, dismissible) shown only until done; the same items live in Settings | H7, P9 |
| Resume workout | Home, Add | Tab bar accessory | rule 4 |
| Build a workout / Empty | Add, Home, Fitness | Log sheet top button; Fitness › This week Start; Today Scores button | X5 |
| My workouts | Add, Fitness, Builder | **Fitness › Workouts › Saved workouts** (push); Builder link stays | A7 |
| Workout history | Add, Fitness icon | **Fitness › Workouts › History** (row) + toolbar calendar | F6 |
| Muscle map + hard sets | Fitness | Fitness › Progress › Muscles row → detail page with both | F1 |
| VO₂ max + weekly minutes | Fitness | Fitness › Progress › Cardio fitness row → detail | F1 |
| Strength days + strength for health | Fitness | Fitness › Progress › Strength row → detail | F1 |
| Training load dials | Fitness | Fitness › Training load section (unchanged dials) | mockup |
| Deload | Fitness card | A line + chip inside This week ("Planned deload this week"), detail in the Strength page | F1 |
| HR zones | Fitness | Fitness › Today › "Heart-rate zones" row → detail (or inside the gauge card when there were zone minutes) | F1 |
| My Gym | Add, Settings, Builder, Coach | **Settings › Training › Gym equipment** (canonical); Builder toolbar link (push inside the sheet); removed from Add and Coach menu | A7, C1 |
| Body age | Biology top | Health › Key measures row ("Body age", with its range) | B1 |
| HRV baseline | Biology | Health primary | mockup |
| ~30 vital tiles | Biology | Health › Key measures (5–6 rows) + **All measures** (5 category rows → category page with the existing tile grid) | B2 |
| Progress photos, Labs, Blood pressure, Body measurements (+ STOP-Bang), Medications | Biology, Add | **Health › Records** (rows with last entry date); logging stays in the Log sheet | B3 |
| What affects you, Alcohol effects, Vitamins & minerals | Biology | **Health › Patterns** (rows → detail) | B3 |
| Garmin help | Biology disclosure | Settings › Data sources | B5, S4 |
| Weekly review | Home card button, notification | Fitness › This week "Review" button + notification | F3 |
| Breathing | Strain card row (easy days) | Strain sheet row + Up next row on easy days/stressful evenings | — |

### 4.4 The Log sheet (replaces the Add tab)

Presented from the "+" toolbar button as a sheet with `.medium` and `.large`
detents and a grabber; built as an inset-grouped `List`.

```
[ ▶ Start workout ]                 ← prominent capsule button (primary)
  Empty workout · Saved workouts    ← two small secondary buttons beneath

LOG
  Overnight HRV            Type it or measure with the camera
  Meal                     Estimate from a description or photo
  Drinks                   Alcohol, for today or an earlier day
  Blood pressure           One reading or the 7-day check
  Progress photo           Front and side
  Waist & grip             Monthly waist, grip twice a year
  Lab results              Enter by hand or import a PDF
```

Rows that open a form show a "+" or no accessory, not a chevron (P6). Icons use
each domain's colour (heart for BP, nutrition for meal, sleep only for sleep) or a
neutral grey for the rest (P25). Subtitles fit on one line (HIG *Lists*).

**Why each move**

| Item | Decision | Justification |
|---|---|---|
| Start workout | Top, prominent, opens the builder | Most frequent task; a recommended default lowers choice effort when options are many (P10, Chernev 2015); one primary (P7). |
| Empty workout, Saved workouts | Secondary buttons under Start | Same job (start training), lower frequency; keeps them one tap away without competing (P8). |
| HRV, meal, drinks | First three log rows | Daily for Garmin users and food loggers; order by frequency (P7, P13). |
| Blood pressure, photo, waist & grip, labs | Following rows, in frequency order | Weekly → monthly → yearly. |
| This week's plan | **Out** → Fitness › This week | Planning, not logging; next to the sessions it schedules (P7). |
| My workouts | **Out** → Fitness › Workouts (and as "Saved workouts" button) | Management of training content. |
| Medications | **Out** → Health › Records; doses taken from Today › Up next and notifications | Managing a list is not a log action; taking a dose already has a faster path. |
| My Gym | **Out** → Settings › Training (and the builder) | Setup done once, then rarely (P9); the builder links to it where it matters. |
| Workout history | **Out** → Fitness › Workouts | Browsing past content belongs in the content tab (P1, P3). |
| Resume workout | **Out** → tab bar accessory | Persistent state, visible from every tab (P4). |

Result: 2 groups, 1 primary button, 7 log rows (from 15 equal rows), each with
one obvious kind of behaviour.

### 4.5 Consistent card anatomy

One reusable component, `SummaryCard` (new file in `App/Design/`), used for every
summary card on Today, Fitness and Health:

```
┌──────────────────────────────────────────┐
│ TITLE (CardLabel)            [chip]   ›  │  ← one line; chip = verdict ("Normal", "In range")
│ 54 bpm                                   │  ← one key number, hero style (scaled)
│ 3 below your usual · 7-day average       │  ← one line of context, .subheadline secondary
│ [optional visual: sparkline / bar]       │
└──────────────────────────────────────────┘
```

- The whole card is the tap target and one accessibility element:
  label "Resting heart rate, 54 beats per minute, normal", hint "Shows history".
- Explanations, formulas and citations move to an **About this number** section
  at the bottom of the detail page. CLAUDE.md's rule (evidence in comments, weak
  evidence flagged in the UI) is kept: the detail view carries the caveat, and the
  card's context line says "estimate" where the number is one.
- A list version, `MetricRow` (title, value + unit, chip, sparkline, chevron), is
  what the mockup's Biomarkers list uses; use it for Health's Key measures and the
  Fitness Progress rows.
- Tints: drop the radial tint glow from most cards; keep it only on the primary
  card of each tab (P21: hierarchy through layout, not decoration).
- One corner radius (26) and one padding (16) everywhere, including tiles
  (`MonitorTile` currently 22).

**Type tokens** (add to `Theme`): screen title = system large title; section
header = `.title3.weight(.bold)`; card label = `CardLabel`; hero number =
`@ScaledMetric(relativeTo: .largeTitle) 44` rounded bold; tile number =
`@ScaledMetric(relativeTo: .title) 30` rounded semibold; body = `.subheadline`;
context = `.footnote` secondary. Replace all 16 `.system(size:)` uses.

**Colour rules**: each accent means its domain only (strain orange, recovery
green/amber/red, sleep indigo, nutrition teal, heart red, lifting pink, oxygen
blue). Neutral rows and icons use `secondaryText`. Text in an accent uses a
darker text variant: add `oxygenText`, `nutritionText`, `heartText`, `sleepText`
to `Theme` and extend `Theme.textColor(for:)` so every `Chip` passes 4.5:1. Darken
`secondaryText` slightly for text on the page background (≥ 4.5:1 on
`Theme.background`).

### 4.6 Per-screen redesign specs

#### Today (target: 5 blocks on a normal day)

1. **Navigation bar**: large title "Today", subtitle line with the date and sync
   status ("Updated 5 min ago"); toolbar: profile (Settings), "+" (Log).
2. **Alert slot** (0 or 1 card): Health access problem › illness (major) › rest
   mode. Minor illness signals become a line in the Scores card.
3. **Finish setting up** (only until done; dismissible): checklist of Goals, City,
   Gym, Weekly plan, each a row with chevron. Replaces GoalsPromptCard, "Add your
   city", and the builder's gym prompt as a home-screen nag.
4. **Scores card (primary)**: three rings as now; under them the coaching line;
   then **one** button chosen by state: "Start Push · 45 min" (planned today, not
   done) / "Plan a workout" (below range, nothing planned) / none (trained, in or
   above range). Ring taps: Strain → Strain sheet (moved `StrainGoalCard` content),
   Recovery → contributors, Sleep → last night (+ sleep debt section). "Ask why"
   text button opens Coach with the coaching question.
5. **Up next** (list card, max 4 rows, ordered by time): morning/evening check-in,
   today's planned session (if not shown in the Scores button), medication doses
   due, "In bed by …", caffeine cut-off, movement nudge, weigh-in. Each row:
   icon, one line, trailing action ("Take", "Start", chevron). Hidden when empty.
6. **Nutrition** (mockup card): calories ring with target, protein bar against
   goal, carbs, fat; water as a fourth bar only when water is logged. One
   context line ("Weekly average is what moves weight"); ⓘ opens the existing
   details sheet. With no food today: one row "No food logged yet · Protein goal
   150 g", no paragraph.
7. **Conditions row** (only when a tip applies): "31° · heat: go easier on outdoor
   cardio" → details sheet with the full weather card.
8. **Health Monitor**: section header with the "All normal / 2 to watch" verdict,
   4 tiles (RHR, HRV, breathing, sleep), footer link "All measures" → Health tab.
   Tiles with no data show "—" and a one-line reason only on the first.

Removed from Today but kept elsewhere: Strain range card (sheet), Consistency card
(Fitness), Sleep debt card (sheet + Up next), Habits card (Up next + Nutrition),
Water card (Nutrition), Medications card (Up next + Health), 4 monitor tiles
(Health), Ask coach card (Coach).

#### Fitness (target: 5 sections)

1. **Navigation bar**: large title "Fitness"; toolbar: History (calendar), "+".
2. **Week strip** (unchanged; ring numbers at ≥ 11 pt scaled).
3. **This week (primary)**: plan dots ("2 of 4 done"), today's slot with
   **Start** and "Short version · 25 min", deload chip when planned, buttons
   "Edit plan" and "Review" (Mondays). No plan: "Plan your week" button plus
   "Same days as last week".
4. **Today**: day-strain gauge with the range band, today's activities as rows
   beneath it (+strain chips), and a "Heart-rate zones" row → zones detail. No
   activities: one line, no Start button (the primary is above).
5. **Training load**: the two dials as now; status text as the context line;
   "What this means" in the detail.
6. **Progress** (`MetricRow`s, each → detail page with the existing full cards and
   their research notes):
   - Cardio fitness · "VO₂ max 42 · good for your age" (VO₂ card + weekly minutes)
   - Strength · "2 of 2+ days this week" (strength days, health floor,
     strength for health)
   - Muscles · "Chest 12 sets · back recovering" (map + hard sets)
7. **Workouts**: Saved workouts (n saved) ›, History ›.

#### Coach

1. System navigation bar: large title "Coach"; toolbar: compose (New
   conversation). Remove the menu's My Gym item; change the empty-state line to
   "Set up your gym in Settings so workouts use your equipment."
2. Context chips, empty state and conversation unchanged.

#### Health (target: 5 sections)

1. **Navigation bar**: large title "Health", subtitle "Trends and records";
   toolbar: profile, "+".
2. **HRV baseline** (primary; mockup card).
3. **Key measures** (one list card, `MetricRow`s, mockup "Biomarkers"): Weight
   trend, Resting heart rate, VO₂ max, Blood pressure, Body fat or waist-to-height,
   Body age. Rows with no data are hidden (one "Add data" hint at the end).
4. **All measures**: five rows (Heart, Sleep, Breathing & temperature, Activity,
   Body) showing "8 measures · 1 to watch" → push to a category page with the
   existing `VitalTile` grid (STOP-Bang stays on the Breathing page).
5. **Records**: Lab results, Blood pressure log, Body measurements, Progress
   photos, Medications; each row shows the last entry ("Waist · 3 weeks ago") and
   pushes to the existing view (sheet views become pushes, with their Add buttons
   in the toolbar).
6. **Patterns**: What affects you, Alcohol and your sleep, Vitamins & minerals →
   detail pages.

#### Settings (sheet from the profile button on any tab)

Inset-grouped list: **You** (name, goals, city) → **Profile** (Health fill-in, sex,
max HR, height, weight) → **Training** (Gym equipment, rest timer, start on Apple
Watch, RPE guide) → **Reminders** (check-ins, workouts, weekly review, creatine,
medication reminders) → **Sleep & rest** → **Nutrition** (hide calories) →
**Coach** (on-device / Claude; Supabase fields under an "Advanced" disclosure) →
**Data sources** (Apple Health access, Garmin help, Cronometer help) →
**Appearance** (theme, units in one section) → **About**.

#### Workout screens

- **Builder**: focus and duration first; summary; exercise list; "Start workout"
  stays pinned at the bottom (good). Move "Rather do your own?" to a toolbar
  menu or a plain row *below* the exercises, labelled "Saved workouts or empty
  workout". My Gym opens by **push** inside the builder's stack.
- **Finish sheet**: leading button "Cancel" (or "Keep going"), trailing "Save".
- **Live workout**: unchanged structure; replace fixed font sizes with scaled
  metrics.
- Copy: every "Add → My workouts" becomes "Fitness → Saved workouts"; "Add →
  Alcohol" becomes "+ → Drinks".

### 4.7 Wording changes

| Now | Proposed | Where |
|---|---|---|
| Home (tab) | Today | `WorkoutAppApp` 164 |
| Biology (tab), "Your long-term baselines" | Health, "Trends and records" | `WorkoutAppApp` 176, `BiologyView` 27–33 |
| Add (tab) | "+" button, sheet title "Log" | `WorkoutAppApp` 179, `QuickAddView` 83 |
| Build a workout / Plan a workout / Start / Create a workout | **Start workout** (opens the builder); **New workout** (create a saved one) | Add, Home 418, MyWorkouts 34 |
| Empty / Empty workout / Start empty | **Empty workout** | TrainingCards 39, MyWorkouts 37, Add 29 |
| My workouts / Your workouts / Rather do your own? | **Saved workouts** | TrainingCards 21, Add 38, Builder 51 |
| My Gym | **Gym equipment** (title of `MyGymView` may stay "My Gym" if preferred, but use one term everywhere) | Settings 139, Builder 102, Coach 102 |
| Log overnight HRV · "From your watch's app" | **Overnight HRV** · "Type it or measure with the camera" | Add 41 |
| Alcohol | **Drinks** | Add 47 |
| Estimate a meal | **Meal** · "Estimate from a description or photo" | Add 56 |
| Body measurements · "Waist, grip strength and the sleep apnoea screen" | **Waist & grip** | Add 59 |
| Strain range / Range / planned range / target | **Today's range** (chip: "In range", "Below range", "Above range") | TodayView 314–347, FitnessView 134, CoachView 123, Builder 268 |
| HR above resting / Heart rate above resting | **Heart-rate stress (estimate)** | TodayView 1083, VitalsModel 252 |
| Daily habits | (removed; rows move to Up next) | HabitsCard 35 |
| What affects you | **Your patterns** | BiologyView 497 |
| Strength · Health floor | Strength · "Minimum for health: 2 days, 30 min a week" in the detail | FitnessView 45 |
| Cardio fitness · 90-day trend | Cardio fitness (trend shown in the chart) | FitnessView 36 |
| "…numbers under each bar are bpm" | Axis caption "bpm" under the bars | FitnessView 372 |
| "Set your goals on the Home tab…" | "Set your goals in Settings › Goals…" | TodayView 961 |
| "…with Add HRV on the Home tab" | "…tap + › Overnight HRV" | BiologyView 269 |
| "Start it again… from Add → My workouts" | "…from Fitness › Saved workouts" | ActiveWorkoutView 136, FinishWorkoutSheet 49, WorkoutDetailView 87 |
| "Forgot last night? Use Add → Alcohol." | "Forgot last night? Tap + › Drinks." | CheckInView 204 |
| "Set up My Gym (menu, top right)" | "Set up your gym equipment in Settings" | CoachView 145 |
| Finish sheet "Back" | "Cancel" | FinishWorkoutSheet 66 |

### 4.8 Accessibility checklist for the rebuild

- Every summary card and tile: one accessibility element, spoken as "title,
  value unit, verdict", hint for the tap (P27).
- Hit targets ≥ 44 pt: text buttons such as "See all" (TodayView 746), "Review"
  (ConsistencyCard 59), chips used as buttons, and the rest-timer pills need
  `.frame(minHeight: 44)` or `.contentShape` padding (P23).
- All numbers via text styles or `@ScaledMetric`; test at the largest
  accessibility size: the three rings should wrap to a vertical stack and the
  2-column tiles to one column (`ViewThatFits` or a Dynamic Type check) (P22).
- Contrast fixes in 4.5 (P24); never colour alone: chips always carry a word, and
  arrows accompany up/down changes (already done on tiles).
- Charts: a title that states the message ("HRV 6% above last month") and an
  accessibility summary (P15).

---

## 5. Prioritised changes

Impact: how much it reduces clutter or confusion for most users. Effort: S (< ½
day), M (½–2 days), L (> 2 days).

| # | Change | Impact | Effort | Wave |
|---|---|---|---|---|
| 1 | Log sheet replaces the Add tab (grouped list, primary Start); remove `role: .search` | High | M | 1 |
| 2 | Tab rename (Today, Health), system nav bars with large titles, profile + "+" toolbar on every tab | High | M | 1 |
| 3 | Tab bar accessory for an active workout; remove both resume banners | Medium | S | 1 |
| 4 | Design tokens: type scale, text colours for accents, `SummaryCard`, `MetricRow`, contrast fixes | High (enables the rest) | M | 1 |
| 5 | Builder: My Gym push not sheet; escape hatch below; finish sheet "Cancel"; copy fixes | Medium | S | 1 |
| 6 | Today: Scores card with one action, strain card → Strain sheet, Up next, Nutrition (with water), alert slot, setup card, 4 tiles | High | L | 2 |
| 7 | Fitness: This week (from Home) as primary, Today gauge + activities, Progress rows → detail pages, Workouts rows | High | L | 2 |
| 8 | Health: HRV hero, Key measures rows, All measures category pages, Records, Patterns; details as pushes | High | L | 2 |
| 9 | Settings regroup, Data sources section, Medications/Apple Watch moved | Medium | M | 3 |
| 10 | Coach header to system nav bar; remove My Gym from the menu | Low | S | 3 |
| 11 | Onboarding: optional steps for goals, city, gym, matching the setup card | Medium | M | 3 |
| 12 | Dynamic Type sweep on workout screens; 44 pt targets; VoiceOver labels on cards | Medium | M | 3 |

---

## 6. Implementation waves

Waves run in order. Inside a wave, the builders work in parallel and **never edit
the same file**. New files are listed under the builder that creates them.

### Wave 1: foundation, navigation shell, Log sheet

**Builder 1A, design system**
- `App/Design/Theme.swift`: type tokens, `oxygenText` / `nutritionText` /
  `heartText` / `sleepText`, extended `textColor(for:)`, darker secondary text
  for page backgrounds, optional `tint` only for primary cards.
- `App/Design/ScoreRing.swift`: `Chip` contrast, `MonitorTile`-style tile moved
  here as a shared `MetricTile` (radius 26), `SectionTitle` variant with a "See
  all" link; mark `GlassIcon`/`GlassIconButton` deprecated (removed in wave 2 when
  no screen uses them).
- **New** `App/Design/SummaryCard.swift`: `SummaryCard`, `MetricRow`, `SetupChecklistCard`.

**Builder 1B, navigation shell and Log**
- `App/WorkoutAppApp.swift`: tabs Today / Fitness / Coach / Health; remove the
  Add tab; `tabViewBottomAccessory` for an active session; app-level Log and
  Settings sheet state (`AppRouter` flags).
- `App/Services/Reminders.swift` (only the `AppRouter` part): `showLog`,
  `showSettings` flags.
- `App/Features/Trainer/QuickAddView.swift`: rewrite as the Log sheet (grouped
  `List`, Start workout button, 7 rows; remove plan, saved workouts, meds, gym,
  history rows).
- **New** `App/Design/TabToolbar.swift`: a `ViewModifier` adding the profile and
  "+" toolbar items, used by every tab in wave 2.

**Builder 1C, workout flow and copy**
- `App/Features/Trainer/WorkoutBuilderView.swift`: My Gym by push; escape hatch
  below the exercises, relabelled.
- `App/Features/Trainer/MyWorkoutsView.swift`: "Saved workouts", "New workout",
  "Empty workout".
- `App/Features/Workout/FinishWorkoutSheet.swift`: "Cancel"; copy.
- `App/Features/Workout/ActiveWorkoutView.swift`: copy (136); scaled fonts (233,
  773, 993).
- `App/Features/Workout/WorkoutDetailView.swift`: copy (87).
- `App/Features/Today/CheckInView.swift`: copy (204).

### Wave 2: the three content tabs

Each builder adopts the system nav bar and `TabToolbar`, uses `SummaryCard` /
`MetricRow`, and replaces fixed font sizes in its own files.

**Builder 2A, Today**
- `App/Features/Today/TodayView.swift` (split it): keep `TodayView`, Nutrition
  and Health Monitor here; **new** `Today/ScoresCard.swift`,
  `Today/StrainSheet.swift` (moved `StrainGoalCard`, `StrainOptions`,
  `SuggestionRow`), `Today/UpNextCard.swift`, `Today/AlertSlot.swift`,
  `Today/ConditionsRow.swift` (weather card moved into its detail sheet).
- `App/Features/Today/HabitsCard.swift`: turn into Up next row providers (or
  delete after moving logic to `UpNextCard.swift`).
- `App/Features/Today/SleepDebtCard.swift`: card removed; debt section moves into
  `LastNightSleepSheet` (same file).
- `App/Features/Today/IllnessAlertCard.swift`: fit the alert slot.
- `App/Features/Today/RecoveryContributorsSheet.swift`: only if the ring-tap
  sheet needs the new header.
- `App/Features/Breathing/BreathingView.swift`: `BreathingOfferRow` as an Up next
  row; scaled font (169).

**Builder 2B, Fitness**
- `App/Features/Fitness/FitnessView.swift`: new section order; remove
  `DayStrainCard` duplication of the range message; Today section.
- `App/Features/Fitness/TrainingCards.swift`: cards become detail-page content;
  add `MetricRow` summaries; delete `YourWorkoutsCard` (replaced by Workouts rows).
- `App/Features/Fitness/MuscleMap.swift`: card variant for the detail page.
- `App/Features/Today/ConsistencyCard.swift` → **move** to
  `App/Features/Fitness/ThisWeekCard.swift` (absorbs the deload line).
- `App/Features/Workout/WorkoutHistoryView.swift`: pushed from the Workouts row.
- **New** `Fitness/CardioDetailView.swift`, `Fitness/StrengthDetailView.swift`,
  `Fitness/MusclesDetailView.swift`, `Fitness/ZonesDetailView.swift`.

**Builder 2C, Health**
- `App/Features/Biology/BiologyView.swift` → rename to `HealthView` (file
  `App/Features/Health/HealthView.swift`): HRV hero, Key measures, All measures,
  Records, Patterns; Garmin disclosure removed (moves to Settings in wave 3).
- **New** `Health/CategoryView.swift` (tile grid per category),
  `Health/RecordsSection.swift`, `Health/PatternsSection.swift`.
- `App/Features/Biology/VitalDetailView.swift`: pushed, not a sheet; blood
  pressure by push; scaled font (102).
- `App/Features/Biology/AlcoholEffectCard.swift`, `StopBangView.swift`,
  `BodyMeasurementsView.swift` (scaled fonts 150, 295), `BloodPressureView.swift`,
  `ProgressPhotosView.swift`: work as pushed views with toolbar Add buttons.
- `App/Features/Labs/LabsView.swift`, `App/Features/Medications/MedicationsView.swift`:
  pushed from Records (keep sheet use from notifications through the router).

Wave 2 leaves `WorkoutAppApp.swift` alone; the tab's root view name is changed by
keeping a `typealias BiologyView = HealthView` until wave 3, or by 2C editing only
the one line in `WorkoutAppApp.swift` after 1B has merged.

### Wave 3: settings, coach, onboarding, accessibility sweep

**Builder 3A, Settings and onboarding**
- `App/Features/Settings/SettingsView.swift`: new grouping, Data sources section
  (Garmin and Cronometer help moved from Biology and README), Medications under
  Reminders as "Medication reminders" linking to the Health record.
- `App/Features/Settings/OnboardingView.swift`: optional goals/city/gym steps that
  tick the setup checklist.
- `App/Features/Settings/GoalsView.swift`, `LocationPicker.swift`: only if the
  checklist needs completion callbacks.

**Builder 3B, Coach**
- `App/Features/Coach/CoachView.swift`: system nav bar, compose button, remove My
  Gym from the menu, copy (145).

**Builder 3C, accessibility and polish**
- `App/Features/Workout/ActiveWorkoutView.swift` (VoiceOver labels on set rows,
  44 pt rest pills), `App/Features/Workout/RPEGuideView.swift`,
  `App/Features/Workout/ExercisePickerView.swift`, `App/Features/Workout/LiftProgressView.swift`,
  `App/Features/Trainer/MyGymView.swift`: Dynamic Type at the largest sizes,
  44 pt targets.
- `App/WorkoutAppApp.swift`: remove the `BiologyView` alias; final route cleanup.
- `README.md`: update the feature table and the "Add HRV on the Recovery card"
  instructions to the new locations.

### Checks after each wave

- `swift test --package-path Packages/AppCore` (no AppCore changes are planned).
- CI simulator build (Linux can't build iOS).
- Manual pass at the default and the largest accessibility text size, light and
  dark, with VoiceOver on the three content tabs.
- Every feature in 4.3 reachable in at most two taps from a tab root, or one tap
  from the "+" button.

---

## 7. References

Apple (read 4 November 2026)
- Human Interface Guidelines: Tab bars; Modality; Sheets; Materials; Layout;
  Typography; Accessibility; Buttons; Charts; Color; Writing; Onboarding; Lists
  and tables; Toolbars; Search fields. developer.apple.com/design/human-interface-guidelines
- WWDC25 session 356, *Get to know the new design system*. developer.apple.com/videos/play/wwdc2025/356
- Apple Support, *Use the Health app on your iPhone or iPad*. support.apple.com/104997

Nielsen Norman Group (nngroup.com blocked here; confirmed through search)
- Nielsen J. *Progressive Disclosure*. nngroup.com/articles/progressive-disclosure/
- Pernice K, Budiu R. *Hamburger Menus and Hidden Navigation Hurt UX Metrics*, 2016. nngroup.com/articles/hamburger-menus/
- *Dashboards: Making Charts and Graphs Easier to Understand*. nngroup.com/articles/dashboards-preattentive/
- Nielsen J. *10 Usability Heuristics for User Interface Design* (1994; updated 2020) *(from memory)*
- Pernice K. *F-Shaped Pattern of Reading on the Web: Misunderstood, But Still Relevant*, 2017 *(from memory)*

Research
- Scheibehenne B, Greifeneder R, Todd PM. Can there ever be too many options? A meta-analytic review of choice overload. *J Consum Res* 2010;37:409–425.
- Chernev A, Böckenholt U, Goodman J. Choice overload: a conceptual review and meta-analysis. *J Consum Psychol* 2015;25:333–358.
- Hick WE. On the rate of gain of information. *Q J Exp Psychol* 1952; Hyman R. Stimulus information as a determinant of reaction time. *J Exp Psychol* 1953 *(from memory)*.
- Cleveland WS, McGill R. Graphical perception. *J Am Stat Assoc* 1984;79:531–554 *(from memory)*.
- Peters E, Dieckmann N, Dixon A, Hibbard JH, Mertz CK. Less is more in presenting quality information to consumers. *Med Care Res Rev* 2007;64:169–190.
- Zikmund-Fisher BJ, Scherer AM, Witteman HO, et al. Effect of harm anchors in visual displays of test results on patient perceptions of urgency about near-normal values: experimental study. *J Med Internet Res* 2018;20(3):e98.
- Zikmund-Fisher BJ, Witteman HO, Dickson M, et al. Blocks, ovals, or people? Icon type affects risk perceptions and recall of pictographs. *Med Decis Making* 2014;34:443–453.
- Rosman L, Lampert R, Zhuo S, et al. Wearable devices, health care use, and psychological well-being in patients with atrial fibrillation. *J Am Heart Assoc* 2024;13:e033750.
- W3C. Web Content Accessibility Guidelines 2.2, 1.4.3 and 1.4.4.

Industry (vendor statements)
- Oura, *The new Oura app experience* (October 2025). ouraring.com/blog/new-oura-app-experience/
- WHOOP, *The all-new WHOOP home screen* (2025). whoop.com/thelocker/the-all-new-whoop-home-screen/
- Gentler Streak, App Store release notes (iOS 26 update).


## Decisions (user, November 2026)

- **Log stays a bottom tab**, renamed "Log" (no search role): Start workout at the top, Empty and Saved workouts under it, then the log rows. The navigation-bar "+" is not used.
- **Biology is renamed "Health".** Copy always says "Apple Health" when it means Apple's app.
