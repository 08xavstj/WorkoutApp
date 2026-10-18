import SwiftUI
import SwiftData
import AppCore

/// Home: score rings and coaching, the strain goal with ways to reach it,
/// nutrition and energy balance, and the health monitor.
struct TodayView: View {
    let askCoach: (String) -> Void

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRefresher.self) private var refresher
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \HRVReading.date, order: .reverse) private var hrvReadings: [HRVReading]
    @State private var showingSettings = false
    @State private var showingHRVEntry = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    if let active = sessions.first(where: \.isActive) {
                        ResumeWorkoutBanner(session: active) { launcher.activeSession = active }
                    }
                    if let error = metrics.errorMessage {
                        HealthAccessCard(message: error)
                    }
                    IllnessAlertCard()
                    ScoresCard()
                    GoalsPromptCard()
                    CheckInCard()
                    ConditionsCard()
                    StrainGoalCard(sessions: sessions)
                    MedsTodayCard()
                    EnergyCard()
                    HydrationCard()
                    HealthMonitor(onEnterHRV: { showingHRVEntry = true })
                    askCoachCard
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .lockedToScreenWidth()
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.butter, Theme.Wash.sky])
            }
            .background(Theme.background)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await refresher.refresh() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingHRVEntry) {
                HRVEntrySheet(existing: hrvReadings.first { Calendar.current.isDateInToday($0.date) })
                    .presentationDetents([.medium])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppLogoHeader()
                Spacer(minLength: 8)
                SyncChip(isLoading: metrics.isLoading, lastUpdated: metrics.lastUpdated)
                GlassIconButton(systemName: "person.fill", label: "Settings") {
                    showingSettings = true
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(greeting)
                    .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.top, 8)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        let name = settings.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    private var askCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ask your coach", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(LinearGradient(colors: [Theme.sleep, Theme.lifting], startPoint: .leading, endPoint: .trailing))
            ForEach(CoachModel.suggestions.prefix(3), id: \.self) { question in
                Button {
                    askCoach(question)
                } label: {
                    HStack {
                        Text(question)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .padding(12)
                    .background(Theme.cardRaised, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .card(tint: Theme.sleep)
    }
}

// MARK: - Header pieces

private struct SyncChip: View {
    let isLoading: Bool
    let lastUpdated: Date?

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView().controlSize(.mini)
                Text("Syncing")
            } else {
                Circle().fill(Theme.recoveryHigh).frame(width: 8, height: 8)
                Text(lastUpdated == nil ? "Not synced" : "Synced")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(lastUpdated == nil && !isLoading ? Theme.secondaryText : Theme.recoveryHigh)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

struct ResumeWorkoutBanner: View {
    let session: WorkoutSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconBadge(systemName: "dumbbell.fill", color: Theme.lifting, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.name) in progress")
                        .font(.headline)
                    TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(session.startedAt)).formatted(.time(pattern: .hourMinuteSecond)))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                Chip(text: "Resume", color: Theme.lifting, filled: true)
            }
            .foregroundStyle(Theme.primaryText)
            .card()
        }
        .buttonStyle(.plain)
    }
}

private struct HealthAccessCard: View {
    let message: String
    @Environment(\.healthClient) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Health", systemImage: "heart.text.square")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text("If you already answered, open the Health app → your profile picture → Apps → WorkoutApp, and tap Turn On All.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Button("Allow access") {
                Task { try? await health?.requestAuthorization() }
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
    }
}

// MARK: - Scores

private struct ScoresCard: View {
    @Environment(DailyMetricsModel.self) private var metrics

    var body: some View {
        let coaching = TrainerSuggestions.coachingLine(metrics: metrics)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                ScoreRing(
                    title: "Strain",
                    value: metrics.strain.map { "\(whole($0.strain))" } ?? "--",
                    unit: metrics.strain == nil ? "" : "%",
                    subtitle: metrics.targetStrain.map { "Goal \(whole($0.lowerBound))–\(whole($0.upperBound))%" } ?? "Day strain",
                    progress: (metrics.strain?.strain ?? 0) / StrainCalculator.maximum,
                    colors: Theme.strainColors,
                    size: 100
                )
                .frame(maxWidth: .infinity)
                ScoreRing(
                    title: "Recovery",
                    value: metrics.recovery.map { "\($0.score)" } ?? "--",
                    unit: metrics.recovery == nil ? "" : "%",
                    subtitle: metrics.recovery.map { $0.status.rawValue.capitalized },
                    progress: Double(metrics.recovery?.score ?? 0) / 100,
                    colors: Theme.recoveryColors(for: metrics.recovery?.score),
                    size: 100
                )
                .frame(maxWidth: .infinity)
                ScoreRing(
                    title: "Sleep",
                    value: metrics.sleep.map { "\($0.score)" } ?? "--",
                    unit: metrics.sleep == nil ? "" : "%",
                    subtitle: metrics.sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
                    progress: Double(metrics.sleep?.score ?? 0) / 100,
                    colors: Theme.sleepColors,
                    size: 100
                )
                .frame(maxWidth: .infinity)
            }
            Divider().overlay(Theme.separator)
            VStack(alignment: .leading, spacing: 6) {
                Label("Coaching", systemImage: "sparkle")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(Theme.strain)
                if let highlight = coaching.highlight {
                    let lead = Text(coaching.text).foregroundStyle(Theme.primaryText)
                    let accent = Text(highlight).foregroundStyle(Theme.strain).fontWeight(.semibold)
                    Text("\(lead) \(accent)")
                        .font(.body)
                } else {
                    Text(coaching.text)
                        .font(.body)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .card()
    }
}

// MARK: - Strain goal

private struct StrainGoalCard: View {
    let sessions: [WorkoutSession]

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(WorkoutLauncher.self) private var launcher

    var body: some View {
        let current = metrics.strain?.strain ?? 0
        let target = metrics.targetStrain ?? StrainCalculator.targetStrain(forRecovery: 50)
        let status = StrainPlanner().status(current: current, target: target)
        let suggestions = TrainerSuggestions.make(metrics: metrics, settings: settings, sessions: sessions)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                CardLabel(text: "Strain goal")
                Spacer()
                switch status {
                case .below(let remaining):
                    Chip(text: "\(strainText(remaining)) to go")
                case .inRange:
                    Chip(text: "Target reached", color: Theme.recoveryHigh)
                case .above:
                    Chip(text: "Above target", color: Theme.recoveryModerate)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(strainText(current))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing))
                Text("target \(whole(target.lowerBound))–\(whole(target.upperBound))%")
                    .font(.title3)
                    .foregroundStyle(Theme.secondaryText)
            }
            StrainGoalBar(current: current, target: target)
            Text(metrics.usualTrainingStrain.map { "Scaled to you: your training days usually reach \(whole($0))%, so the target moves as you get fitter or take time off." }
                 ?? "Your target adapts to you after 6 training days in 4 weeks.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)

            switch status {
            case .below:
                CardLabel(text: "Suggested to close the gap")
                ForEach(suggestions) { suggestion in
                    Button {
                        if suggestion.option.kind == .strength {
                            launcher.openBuilder(focus: suggestion.focus, minutes: suggestion.minutes)
                        }
                    } label: {
                        SuggestionRow(suggestion: suggestion)
                    }
                    .buttonStyle(.plain)
                    .disabled(suggestion.option.kind == .cardio)
                }
                Button {
                    let strength = suggestions.first { $0.option.kind == .strength }
                    launcher.openBuilder(focus: strength?.focus, minutes: strength?.minutes)
                } label: {
                    Label("Start workout", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(LinearGradient(colors: [Theme.strainLight, Theme.strain, Theme.lifting], startPoint: .leading, endPoint: .trailing), in: .capsule)
                        .shadow(color: Theme.strain.opacity(0.35), radius: 10, y: 5)
                }
                .buttonStyle(.plain)
            case .inRange:
                Text("You've hit today's target. Anything more is optional; recovery work and sleep will pay off tomorrow.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            case .above:
                Text("You're past today's target. Keep the rest of the day easy and get to bed early.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card(tint: Theme.strain)
    }
}

private struct SuggestionRow: View {
    let suggestion: TrainerSuggestions.Suggestion

    var body: some View {
        let isStrength = suggestion.option.kind == .strength
        HStack(spacing: 12) {
            IconBadge(
                systemName: isStrength ? "dumbbell.fill" : "bicycle",
                color: isStrength ? Theme.lifting : Theme.sleep,
                size: 42
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.option.title)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(suggestion.option.detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Text("+\(strainText(suggestion.option.gain))")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Theme.strain)
            if isStrength {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(12)
        .background(Theme.cardRaised, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isStrength ? "Opens the workout builder" : "")
    }
}

// MARK: - Illness watch

private struct IllnessAlertCard: View {
    @Environment(VitalsModel.self) private var vitals
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(CheckInStore.self) private var checkIns

    var body: some View {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        if let alert = vitals.illnessAlert(
            metrics: metrics,
            drinksLastNight: checkIns.evening(on: yesterday)?.drinks,
            reportedSymptoms: checkIns.morning()?.isSick ?? false
        ) {
            let color = alert.level == .likely ? Theme.recoveryLow : Theme.recoveryModerate
            let immune = Micronutrients.notes(metrics.micronutrients, area: .immune)
            VStack(alignment: .leading, spacing: 10) {
                Label(alert.level == .likely ? "Your body may be fighting something" : "Vitals above your normal",
                      systemImage: "cross.case.fill")
                    .font(.headline)
                    .foregroundStyle(color)
                Text(alert.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                HStack(spacing: 6) {
                    ForEach(alert.signals, id: \.self) { Chip(text: $0, color: color) }
                }
                if !immune.isEmpty {
                    Text("From your food log: " + immune.joined(separator: " ") + " Vitamin C, vitamin D and zinc support immune defences.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text("Not a diagnosis. See a doctor if you feel unwell or it lasts.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card(tint: color)
        }
    }
}

// MARK: - Goals

private struct GoalsPromptCard: View {
    @Environment(UserSettings.self) private var settings
    @State private var showingGoals = false

    var body: some View {
        Group {
            if !settings.goalsSet {
                Button {
                    showingGoals = true
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: "target", color: Theme.lifting, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Set your goals")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("Lose, maintain or gain; build muscle, strength or stamina. Sets your calories, protein and workouts.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                    .card(tint: Theme.lifting)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingGoals) { GoalsView() }
    }
}

// MARK: - Water

private struct HydrationCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings

    var body: some View {
        let drank = metrics.nutritionToday?.waterLiters ?? 0
        let exerciseMinutes = Double(metrics.activities.map(\.minutes).reduce(0, +))
        let target = Hydration.target(sex: settings.sex, exerciseMinutes: exerciseMinutes, feelsLikeC: conditions.current?.feelsLike)
        let assessment = Hydration.assess(drank: drank, target: target, hour: Calendar.current.component(.hour, from: .now))
        let color: Color = switch assessment.status {
        case .low: Theme.recoveryModerate
        case .onTrack: Theme.oxygen
        case .high: Theme.recoveryLow
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Water", color: Theme.oxygen)
                Spacer()
                Chip(text: assessment.status.rawValue, color: color)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(drank.formatted(.number.precision(.fractionLength(1))))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                Text("of \(target.liters.formatted(.number.precision(.fractionLength(1)))) L")
                    .font(.headline)
                    .foregroundStyle(Theme.secondaryText)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(LinearGradient(colors: Theme.oxygenColors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, geo.size.width * min(1, drank / max(target.liters, 0.1))))
                    // Where you'd be by now on an even pace.
                    Rectangle()
                        .fill(Theme.primaryText.opacity(0.35))
                        .frame(width: 2, height: 16)
                        .offset(x: geo.size.width * min(1, assessment.expectedByNow / max(target.liters, 0.1)) - 1)
                }
            }
            .frame(height: 12)
            ForEach(assessment.effects, id: \.self) { effect in
                Text(effect)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Target: \(target.base.formatted()) L base\(target.exercise > 0 ? " + \(target.exercise.formatted(.number.precision(.fractionLength(1)))) L for training" : "")\(target.heat > 0 ? " + \(target.heat.formatted()) L for heat" : ""). Includes water from food, as Cronometer counts it. The line marks an even pace for this time of day.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card(tint: Theme.oxygen)
    }
}

// MARK: - Weather

private struct ConditionsCard: View {
    @Environment(ConditionsModel.self) private var conditions
    @Environment(UserSettings.self) private var settings
    @State private var showingPicker = false

    var body: some View {
        Group {
            if let c = conditions.current, settings.hasLocation {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        Image(systemName: c.symbol)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 38))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int(c.temperature.rounded()))° · \(c.summary)")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.primaryText)
                            Text("Feels \(Int(c.feelsLike.rounded()))°\(c.high.map { " · H \(Int($0.rounded()))°" } ?? "")\(c.low.map { " L \(Int($0.rounded()))°" } ?? "") · \(settings.placeName)")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        if let uv = c.uvIndexMax { pill("sun.max", "UV \(Int(uv.rounded()))") }
                        if let aqi = c.usAQI { pill("aqi.medium", "AQI \(Int(aqi))") }
                        if let daylight = c.daylightHours { pill("sunrise", String(format: "%.1f h light", daylight)) }
                    }
                    if let sunrise = c.sunrise, let sunset = c.sunset {
                        Text("Sunrise \(sunrise.formatted(date: .omitted, time: .shortened)) · Sunset \(sunset.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(conditions.tips.prefix(2)) { tip in
                        Label {
                            Text(tip.text).font(.subheadline).foregroundStyle(Theme.primaryText)
                        } icon: {
                            Image(systemName: tip.level == .info ? "lightbulb.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(tip.level == .info ? Theme.oxygen : Theme.recoveryModerate)
                        }
                    }
                }
                .card(tint: Theme.oxygen)
            } else if !settings.hasLocation {
                Button {
                    showingPicker = true
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(systemName: "location.fill", color: Theme.oxygen, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add your city")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("Weather, air quality and daylight for smarter coaching.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingPicker) { LocationPicker() }
    }

    private func pill(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.oxygen)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.oxygen.opacity(0.1), in: .capsule)
    }
}

// MARK: - Check-in

private struct CheckInCard: View {
    @Environment(CheckInStore.self) private var store
    @Environment(AppRouter.self) private var router

    var body: some View {
        let morningDone = store.morning() != nil
        let eveningDone = store.evening() != nil
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Daily check-in", color: Theme.sleep)
            HStack(spacing: 10) {
                button("Morning", icon: "sun.max.fill", done: morningDone, colors: [Theme.strainLight, Theme.strain]) {
                    router.checkIn = .morning
                }
                button("Evening", icon: "moon.stars.fill", done: eveningDone, colors: [Theme.sleepLight, Theme.sleep]) {
                    router.checkIn = .evening
                }
            }
            if let advice = store.advice {
                Label {
                    Text(advice).font(.subheadline).foregroundStyle(Theme.primaryText)
                } icon: {
                    Image(systemName: "sparkle").foregroundStyle(Theme.sleep)
                }
            }
        }
        .card(tint: Theme.sleep)
    }

    private func button(_ title: String, icon: String, done: Bool, colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                Text(done ? "\(title) done" : title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(done ? Theme.primaryText : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(done ? AnyShapeStyle(Theme.cardRaised) : AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Medications

/// Today's doses with tap-to-take, shown when the user has medications.
private struct MedsTodayCard: View {
    @Environment(MedicationsModel.self) private var meds
    @Environment(AppRouter.self) private var router

    var body: some View {
        if !meds.todayDoses.isEmpty || !meds.notes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    CardLabel(text: "Medications", color: Theme.lifting)
                    Spacer()
                    Button("See all") { router.showMedications = true }
                        .font(.subheadline.weight(.semibold))
                }
                if !meds.todayDoses.isEmpty {
                    TodayDosesList()
                }
                ForEach(meds.notes.prefix(2), id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .card(tint: Theme.lifting)
        }
    }
}

// MARK: - Energy and nutrition

private struct EnergyCard: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @State private var showingDetails = false

    var body: some View {
        let food = metrics.nutritionToday
        let summary = metrics.calories
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                CardLabel(text: "Calories today")
                Spacer()
                Button {
                    showingDetails = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("How calories are calculated")
            }
            if let summary, let target = metrics.calorieTarget {
                let left = target - (summary.eaten ?? 0)
                HStack(alignment: .center, spacing: 20) {
                    GradientRing(
                        progress: (summary.eaten ?? 0) / max(target, 1),
                        colors: Theme.nutritionColors,
                        lineWidth: 13
                    ) {
                        VStack(spacing: 0) {
                            Text(whole(abs(left)).formatted())
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(left >= 0 ? Theme.primaryText : Theme.recoveryModerate)
                                .minimumScaleFactor(0.6)
                            Text(left >= 0 ? "kcal left" : "kcal over")
                                .font(.caption2)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(width: 124, height: 124)
                    VStack(alignment: .leading, spacing: 12) {
                        CalorieLine(icon: "fork.knife", color: Theme.nutrition, label: "Eaten", value: summary.eaten ?? 0)
                        CalorieLine(icon: "flame.fill", color: Theme.strain, label: "Burned so far", value: summary.burnedSoFar)
                        CalorieLine(icon: "target", color: Theme.sleep, label: metrics.goals == nil ? "Maintenance" : "Daily target", value: target)
                    }
                }
                Text(targetExplanation(left: left))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Add your weight in Apple Health (or Settings) to see calories burned.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Divider().overlay(Theme.separator)
            if let food, !food.isEmpty {
                HStack(spacing: 14) {
                    MacroColumn(label: "Protein", value: food.proteinGrams ?? 0, goal: metrics.proteinTarget, color: Theme.nutrition)
                    MacroColumn(label: "Carbs", value: food.carbsGrams ?? 0, goal: nil, color: Theme.strain)
                    MacroColumn(label: "Fat", value: food.fatGrams ?? 0, goal: nil, color: Theme.sleep)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.nutrition)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No food logged yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("Meals you log in Cronometer show up here\(metrics.proteinTarget.map { ". Protein goal: \(whole($0)) g" } ?? "").")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .card(tint: Theme.nutrition)
        .sheet(isPresented: $showingDetails) {
            CalorieDetailsSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func targetExplanation(left: Double) -> String {
        let source = metrics.maintenance.map { "Your maintenance is \(whole($0.maintenance).formatted()) kcal, worked out from \($0.loggedDays) days of food and your weight trend." }
            ?? "Maintenance is estimated from your watch until there are 2 weeks of food logs and weigh-ins."
        let goal: String
        if let goals = metrics.goals {
            goal = "Goal: \(goals.title.lowercased())."
        } else {
            goal = "Set a goal in Settings to get a target."
        }
        let today = left >= 0 ? "About \(whole(left).formatted()) kcal left today." : "\(whole(-left).formatted()) kcal over today's target."
        return "\(today) \(goal) \(source)"
    }
}

private struct CalorieLine: View {
    let icon: String
    let color: Color
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(color.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("\(whole(value).formatted()) kcal")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
            }
        }
    }
}

private struct MacroColumn: View {
    let label: String
    let value: Double
    let goal: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Text(goal.map { "\(whole(value))/\(whole($0)) g" } ?? "\(whole(value)) g")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(6, geo.size.width * min(1, value / max(goal ?? max(value, 1) * 1.2, 1))))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where each calorie number comes from.
private struct CalorieDetailsSheet: View {
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let summary = metrics.calories {
                    Section {
                        row("Resting so far", summary.restingSoFar)
                        row("Active so far", summary.activeSoFar)
                        row("Burned so far", summary.burnedSoFar, bold: true)
                        row("Resting still to come", summary.projected - summary.burnedSoFar)
                        row("Burn by midnight", summary.projected, bold: true)
                    } header: {
                        Text("Burned")
                    } footer: {
                        Text(summary.fromWatch
                             ? "From your Garmin via Apple Health, so \"burned so far\" matches your watch. \"By midnight\" adds the resting calories your body will burn before the day ends; more activity adds to it."
                             : "Estimated: resting from \(metrics.energy?.bmrMethod ?? "your profile"), activity from heart rate and steps, plus about 10% of food eaten for digestion.")
                    }
                    Section {
                        if let maintenance = metrics.maintenance {
                            row("Maintenance (your data)", maintenance.maintenance, bold: true)
                            row("Average eaten", maintenance.averageIntake)
                            LabeledContent("Weight trend", value: "\(maintenance.weeklyChangeKg >= 0 ? "+" : "")\(maintenance.weeklyChangeKg.formatted(.number.precision(.fractionLength(2)))) kg/week")
                        } else {
                            Text("Needs 14+ days of food logged and 4+ weigh-ins over 10+ days in the last 4 weeks.")
                                .font(.footnote)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if let target = metrics.calorieTarget {
                            row("Daily target", target, bold: true)
                        }
                        row("Eaten today", summary.eaten ?? 0)
                    } header: {
                        Text("Your real maintenance")
                    } footer: {
                        Text("Wrist trackers are off by over 30% on calories burned, on average. Comparing what you eat (Cronometer) with how your weight moves gives a truer number: each kg of weight change is about 7,700 kcal.")
                    }
                }
            }
            .navigationTitle("Calories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        LabeledContent(label) {
            Text("\(whole(value).formatted()) kcal")
                .monospacedDigit()
                .fontWeight(bold ? .semibold : .regular)
        }
    }
}

// MARK: - Health monitor

private struct HealthMonitor: View {
    let onEnterHRV: () -> Void
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(VitalsModel.self) private var vitals

    var body: some View {
        VStack(spacing: 12) {
            SectionTitle(text: "Health Monitor", trailing: summary.text, trailingColor: summary.color)
            HStack(spacing: 12) {
                rhrTile
                hrvTile
            }
            HStack(spacing: 12) {
                respiratoryTile
                sleepTile
            }
            HStack(spacing: 12) {
                vitalTile("spo2", title: "Blood oxygen", color: Theme.oxygen, light: Theme.oxygenLight)
                vitalTile("hrr", title: "HR recovery", color: Theme.heart, light: Theme.heartLight)
            }
            HStack(spacing: 12) {
                vitalTile("stress", title: "Stress", color: Theme.recoveryModerate, light: Theme.recoveryHighLight)
                vitalTile("steps", title: "Steps", color: Theme.strain, light: Theme.strainLight)
            }
        }
    }

    private func vitalTile(_ id: String, title: String, color: Color, light: Color) -> some View {
        let stat = vitals.stat(id)
        return MonitorTile(
            title: title,
            value: stat?.value,
            unit: stat?.unit ?? "",
            status: stat?.status.map { TileStatus(text: $0, color: VitalTile.color(for: stat?.tone ?? .neutral)) },
            gauge: stat?.gauge,
            color: color,
            lightColor: light
        )
    }

    private var summary: (text: String?, color: Color) {
        guard let recovery = metrics.recovery, recovery.isCalibrated else { return (nil, Theme.secondaryText) }
        let flags = [(recovery.hrvChangePercent ?? 0) < -15, (recovery.restingHeartRateChange ?? 0) > 5].filter { $0 }.count
        return flags == 0 ? ("All normal", Theme.recoveryHigh) : ("\(flags) to watch", Theme.recoveryModerate)
    }

    /// Position of a value within baseline ± 2 SD, as 0...1.
    private func position(_ value: Double?, mean: Double?, sd: Double?) -> Double? {
        guard let value, let mean, let sd, sd > 0 else { return value == nil ? nil : 0.5 }
        return min(1, max(0, (value - (mean - 2 * sd)) / (4 * sd)))
    }

    private var rhrTile: some View {
        let change = metrics.recovery?.restingHeartRateChange
        return MonitorTile(
            title: "Resting HR",
            value: metrics.restingHeartRate.map { "\(whole($0.rounded()))" },
            unit: "bpm",
            status: change.map { delta in
                delta <= 0
                    ? TileStatus(text: "Lower", icon: "arrow.down", color: Theme.recoveryHigh)
                    : TileStatus(text: "Higher", icon: "arrow.up", color: delta > 5 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(metrics.restingHeartRate, mean: metrics.baseline?.meanRHR, sd: metrics.baseline?.sdRHR),
            color: Theme.heart,
            lightColor: Theme.heartLight
        )
    }

    private var hrvTile: some View {
        let change = metrics.recovery?.hrvChangePercent
        let logValue = metrics.hrv.map { log($0) }
        return MonitorTile(
            title: "HRV",
            value: metrics.hrv.map { "\(whole($0.rounded()))" },
            unit: "ms",
            status: change.map { delta in
                delta >= 0
                    ? TileStatus(text: "Higher", icon: "arrow.up", color: Theme.recoveryHigh)
                    : TileStatus(text: "Lower", icon: "arrow.down", color: delta < -15 ? Theme.recoveryModerate : Theme.secondaryText)
            },
            gauge: position(logValue, mean: metrics.baseline?.meanLogHRV, sd: metrics.baseline?.sdLogHRV),
            color: Theme.recoveryHigh,
            lightColor: Theme.recoveryHighLight,
            actionTitle: metrics.hrv == nil ? "Add HRV" : (metrics.hrvIsManual ? "Edit" : nil),
            onAction: onEnterHRV
        )
    }

    private var respiratoryTile: some View {
        let rate = metrics.respiratoryRate
        let normal = rate.map { (12...20).contains($0) } ?? true
        return MonitorTile(
            title: "Respiratory",
            value: rate.map { $0.formatted(.number.precision(.fractionLength(1))) },
            unit: "rpm",
            status: rate.map { _ in
                normal ? TileStatus(text: "Normal", color: Theme.secondaryText) : TileStatus(text: "Check", color: Theme.recoveryModerate)
            },
            gauge: rate.map { min(1, max(0, ($0 - 8) / 16)) },
            color: Theme.oxygen,
            lightColor: Theme.oxygenLight
        )
    }

    private var sleepTile: some View {
        let sleep = metrics.sleep
        return MonitorTile(
            title: "Sleep",
            value: sleep.map { Duration.seconds($0.asleep).formatted(.units(allowed: [.hours, .minutes], width: .narrow)) },
            unit: "",
            status: sleep.map { night in
                night.asleep >= night.need * 0.9
                    ? TileStatus(text: "Normal", color: Theme.secondaryText)
                    : TileStatus(text: "Short", color: Theme.recoveryModerate)
            },
            gauge: sleep.map { min(1, $0.asleep / max($0.need * 1.3, 1)) },
            color: Theme.sleep,
            lightColor: Theme.sleepLight
        )
    }
}

private struct TileStatus {
    var text: String
    var icon: String?
    var color: Color
}

private struct MonitorTile: View {
    let title: String
    let value: String?
    let unit: String
    let status: TileStatus?
    let gauge: Double?
    let color: Color
    var lightColor: Color?
    var actionTitle: String?
    var onAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(unit)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .foregroundStyle(Theme.primaryText)
                } else {
                    Text("No data")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText.opacity(0.7))
                }
                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                } else if let status {
                    HStack(spacing: 3) {
                        if let icon = status.icon {
                            Image(systemName: icon)
                        }
                        Text(status.text)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status.color.opacity(0.12), in: .capsule)
                }
            }
            Spacer(minLength: 0)
            VerticalRangeGauge(value: gauge, color: color, lightColor: lightColor)
                .frame(height: 78)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(RadialGradient(colors: [color.opacity(0.13), color.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: 160))
                )
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, y: 5)
        .accessibilityElement(children: .combine)
    }
}
