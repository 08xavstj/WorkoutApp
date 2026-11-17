import SwiftUI
import AppCore

// The insomnia path (`SleepWindow`, `SleepWindowStore`): a mode of the bed-by
// window, not a new section. It is reached only from
// - Up next, when the data suggests asking (`UpNextCard`, "Trouble sleeping?"),
//   when a course ends, and (while one runs) through tonight's bedtime row;
// - Settings › Sleep & nutrition › Trouble sleeping;
// - Last night's sheet while a course runs (`SleepWindowDebtRows`).
// No tips, breathing or relaxation (Furukawa 2024) and no notifications.

/// The questions, the safety screen, the offer, the running course and its
/// ending, in one page. Pushed (`pushed: true`) from Settings and from last
/// night's sheet; a sheet from Up next.
struct SleepWindowView: View {
    /// True when pushed onto another NavigationStack.
    var pushed = false
    /// Why the app raised the question, when it did (Up next).
    var askReason: SleepWindow.AskReason?

    @Environment(\.dismiss) private var dismiss

    private var store: SleepWindowStore { SleepWindowStore.shared }

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            Form {
                if let outcome = store.state.outcome {
                    SleepWindowOutcomeSection(outcome: outcome)
                } else if let course = store.course {
                    SleepWindowCourseSections(course: course)
                } else {
                    SleepWindowQuestionFlow(askReason: askReason)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(store.isActive ? "Sleep window" : "Trouble sleeping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("sleepwindow-done")
                    }
                }
            }
        }
    }
}

// MARK: - Questions, screen and offer

private struct SleepWindowQuestionFlow: View {
    let askReason: SleepWindow.AskReason?

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case questions
        case answered(String)
        case screening
        case screenApnoeaFirst
        case refused([SleepWindow.Refusal])
        case cannotPropose(String)
        case proposal(SleepWindow.Proposal)
    }

    @State private var step: Step = .questions
    @State private var frequency: SleepWindow.Frequency?
    @State private var affectsDay: Bool?
    @State private var declared: Set<SleepWindow.Exclusion> = []
    @State private var checking = false
    @State private var wakeMinutes = 6 * 60 + 30

    private var store: SleepWindowStore { SleepWindowStore.shared }

    var body: some View {
        switch step {
        case .questions:
            questions
        case .answered(let note):
            Section {
                Text(note)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .screening:
            screening
        case .screenApnoeaFirst:
            screenApnoeaFirst
        case .refused(let refusals):
            refused(refusals)
        case .cannotPropose(let text):
            Section {
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .proposal(let proposal):
            offer(proposal)
        }
    }

    // MARK: The two questions

    @ViewBuilder
    private var questions: some View {
        Section {
            if let askReason {
                Text(askReason.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(SleepWindow.questionIntro)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(SleepWindow.questionTitle)
        }
        Section(SleepWindow.frequencyQuestion) {
            ForEach(SleepWindow.Frequency.allCases) { option in
                SleepWindowChoiceRow(title: option.label, selected: frequency == option) { frequency = option }
                    .accessibilityIdentifier("sleepwindow-frequency-\(option.rawValue)")
            }
        }
        Section(SleepWindow.daytimeQuestion) {
            SleepWindowChoiceRow(title: "Yes", selected: affectsDay == true) { affectsDay = true }
                .accessibilityIdentifier("sleepwindow-affects-yes")
            SleepWindowChoiceRow(title: "No", selected: affectsDay == false) { affectsDay = false }
                .accessibilityIdentifier("sleepwindow-affects-no")
        }
        Section {
            Button("Continue") { answer() }
                .disabled(frequency == nil || affectsDay == nil)
                .accessibilityIdentifier("sleepwindow-continue")
            if askReason != nil {
                Button("Not now") {
                    store.notNow()
                    dismiss()
                }
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("sleepwindow-notnow")
            }
        } footer: {
            Text(SleepWindow.notCareNote)
        }
    }

    private func answer() {
        guard let frequency, let affectsDay else { return }
        let answers = SleepWindow.Answers(frequency: frequency, affectsDay: affectsDay, day: Calendar.current.startOfDay(for: .now))
        store.answer(answers)
        if let note = answers.note {
            step = .answered(note)
        } else {
            step = .screening
        }
    }

    // MARK: Who it isn't for

    @ViewBuilder
    private var screening: some View {
        Section {
            Text(SleepWindow.screeningIntro)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(SleepWindow.screeningTitle)
        }
        Section {
            ForEach(SleepWindow.Exclusion.asked(sex: settings.sex)) { exclusion in
                Toggle(isOn: Binding(
                    get: { declared.contains(exclusion) },
                    set: { on in
                        if on { declared.insert(exclusion) } else { declared.remove(exclusion) }
                    }
                )) {
                    Text(exclusion.question)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tint(Theme.sleep)
                .accessibilityIdentifier("sleepwindow-exclusion-\(exclusion.rawValue)")
            }
        }
        Section {
            Button(checking ? "Checking…" : "Continue") { check() }
                .disabled(checking)
                .accessibilityIdentifier("sleepwindow-check")
        } footer: {
            Text("The app also checks your sleep apnoea screen, your watch's apnoea alerts and breathing disturbances, and whether your sleep falls in the daytime.")
        }
    }

    @ViewBuilder
    private var screenApnoeaFirst: some View {
        Section {
            Text(SleepWindow.screenFirstText)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink("Sleep apnoea screen") { StopBangView(pushed: true) }
                .accessibilityIdentifier("sleepwindow-stopbang")
            Button(checking ? "Checking…" : "I've done it: continue") { check() }
                .disabled(checking || measurements.stopBang == nil)
                .accessibilityIdentifier("sleepwindow-checkagain")
        }
    }

    private func check() {
        checking = true
        let declared = declared
        Task {
            let screening = await SleepWindowStore.screening(declared: declared, stopBang: measurements.stopBang,
                                                             health: health, nights: metrics.sleepNights)
            checking = false
            switch SleepWindow.decide(screening) {
            case .screenApnoeaFirst:
                step = .screenApnoeaFirst
            case .refuse(let refusals):
                store.refuse(refusals)
                step = .refused(refusals)
            case .offer:
                propose()
            }
        }
    }

    @ViewBuilder
    private func refused(_ refusals: [SleepWindow.Refusal]) -> some View {
        Section {
            ForEach(refusals) { refusal in
                Text(refusal.reason)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(SleepWindow.refusalAdvice)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(SleepWindow.refusalTitle)
        }
    }

    // MARK: The offer

    private func propose() {
        let nights = metrics.sleepNights
        let usualWake = BedtimeWindow.usualWakeMinutes(nights.suffix(14).map(\.wake))
        guard let proposal = SleepWindow.propose(nights: SleepWindowStore.nights(nights), sleepNeedHours: settings.sleepNeedHours,
                                                 usualWakeMinutes: usualWake) else {
            step = .cannotPropose(SleepWindow.needsNightsText)
            return
        }
        guard proposal.isShorter else {
            step = .cannotPropose(SleepWindow.nothingToShortenText(proposal))
            return
        }
        wakeMinutes = proposal.wakeMinutes
        step = .proposal(proposal)
    }

    @ViewBuilder
    private func offer(_ proposal: SleepWindow.Proposal) -> some View {
        let bedMinutes = ((wakeMinutes - proposal.windowMinutes) % 1440 + 1440) % 1440
        Section {
            Text(SleepWindow.windowText(windowMinutes: proposal.windowMinutes, wakeMinutes: wakeMinutes))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            Text(SleepWindow.basisText(proposal))
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("Up at", selection: wakeBinding, displayedComponents: .hourAndMinute)
                .accessibilityIdentifier("sleepwindow-wake")
        } header: {
            Text("Your sleep window")
        } footer: {
            Text("Pick a wake time you can keep every day, weekends too.")
        }
        Section("How it works") {
            ForEach(SleepWindow.rules(wakeMinutes: wakeMinutes, bedMinutes: bedMinutes), id: \.self) { rule in
                Label(rule, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
            Text(SleepWindow.howItChanges)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        Section {
            SleepWindowWarning()
            Text(SleepWindow.estimateNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            EvidenceDisclosure(points: SleepWindow.evidence)
        }
        Section {
            Button("Start tonight") {
                SleepWindowStore.shared.start(proposal, wakeMinutes: wakeMinutes)
            }
            .font(.headline)
            .accessibilityIdentifier("sleepwindow-start")
        } footer: {
            Text(SleepWindow.notCareNote)
        }
    }

    private var wakeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(wakeMinutes * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                // To 5 minutes, so the bedtime is a round time too.
                let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                wakeMinutes = (Int((Double(minutes) / 5).rounded()) * 5) % 1440
            }
        )
    }
}

// MARK: - While it runs

private struct SleepWindowCourseSections: View {
    let course: SleepWindow.Course

    @Environment(UserSettings.self) private var settings
    @State private var confirmingStop = false

    private var store: SleepWindowStore { SleepWindowStore.shared }

    var body: some View {
        Section {
            Text(SleepWindow.windowText(windowMinutes: course.windowMinutes, wakeMinutes: course.wakeMinutes))
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            ForEach(SleepWindow.rules(course), id: \.self) { rule in
                Label(rule, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
            if let last = course.reviews.last {
                Text(last.text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let next = course.nextReviewDay() {
                Text("Next check: \(next.formatted(.dateTime.weekday(.wide))).")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text(SleepWindow.heading(course))
        }
        if settings.isRestMode {
            Section {
                Text(SleepWindow.restingNote)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if course.isStalled && !course.continuedPastStall {
            Section {
                Text(SleepWindow.stalledText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Keep going to week \(SleepWindow.maximumWeeks)") { store.continuePastStall() }
                    .accessibilityIdentifier("sleepwindow-keepgoing")
            }
        }
        Section {
            SleepWindowWarning()
            Button("Too sleepy: 15 minutes longer") {
                store.tooSleepy(sleepNeedHours: settings.sleepNeedHours)
            }
            .accessibilityIdentifier("sleepwindow-toosleepy")
        }
        Section {
            Text(SleepWindow.howItChanges)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(SleepWindow.estimateNote)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if course.reviews.count > 1 {
                ForEach(course.reviews.dropLast().reversed(), id: \.week) { review in
                    Text(review.text)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            EvidenceDisclosure(points: SleepWindow.evidence)
        }
        Section {
            Button("Stop the sleep window", role: .destructive) { confirmingStop = true }
                .accessibilityIdentifier("sleepwindow-stop")
        } footer: {
            Text(SleepWindow.notCareNote)
        }
        .confirmationDialog("Stop the sleep window?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) { store.stop() }
        } message: {
            Text("The regular bed-by window comes back tonight.")
        }
    }
}

// MARK: - The ending

private struct SleepWindowOutcomeSection: View {
    let outcome: SleepWindow.Outcome

    private var store: SleepWindowStore { SleepWindowStore.shared }

    var body: some View {
        Section {
            Text(SleepWindow.outcomeText(outcome))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if outcome.needsAnswer {
                Button("Yes, still") { store.answerStillStruggling(true) }
                    .accessibilityIdentifier("sleepwindow-still-yes")
                Button("No, it's better") { store.answerStillStruggling(false) }
                    .accessibilityIdentifier("sleepwindow-still-no")
            } else {
                Button("OK") { store.dismissOutcome() }
                    .accessibilityIdentifier("sleepwindow-outcome-ok")
            }
        } header: {
            Text("Sleep window")
        }
    }
}

// MARK: - Pieces

/// The driving warning, shown with the offer and all through the course (Kyle et al., Sleep 2014).
private struct SleepWindowWarning: View {
    var body: some View {
        Label {
            Text(SleepWindow.sleepinessWarning)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "car.fill")
                .foregroundStyle(Theme.recoveryModerate)
        }
    }
}

/// One answer in a list, with a checkmark when chosen.
private struct SleepWindowChoiceRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.sleep)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Settings › Sleep & nutrition › Trouble sleeping: the way in that's always there.
struct SleepWindowSettingsRow: View {
    var body: some View {
        NavigationLink {
            SleepWindowView(pushed: true)
        } label: {
            LabeledContent("Trouble sleeping") {
                if let course = SleepWindowStore.shared.course {
                    Text("Week \(course.week) of \(SleepWindow.maximumWeeks)")
                }
            }
        }
        .accessibilityIdentifier("settings-sleep-window")
    }
}

/// Last night's sheet while a course runs: in place of the debt plan and
/// the bed-by rows, tonight's sleep window, the warning and a way to the page.
struct SleepWindowDebtRows: View {
    let course: SleepWindow.Course
    let window: BedtimeWindow.Result?

    @Environment(UserSettings.self) private var settings

    var body: some View {
        Text(SleepWindow.debtPausedNote)
            .font(.subheadline)
            .foregroundStyle(Theme.primaryText)
            .fixedSize(horizontal: false, vertical: true)
        Divider().overlay(Theme.separator)
        if let window {
            Text("Tonight: bed from \(window.start.formatted(date: .omitted, time: .shortened)), only when sleepy. Up at \(window.wake.formatted(date: .omitted, time: .shortened)).")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        Text(SleepWindow.sleepinessWarning)
            .font(.caption)
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
        HStack {
            NavigationLink(SleepWindow.heading(course)) { SleepWindowView(pushed: true) }
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("lastnight-sleepwindow-link")
            Spacer()
            Button("Too sleepy") { SleepWindowStore.shared.tooSleepy(sleepNeedHours: settings.sleepNeedHours) }
                .font(.subheadline)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("lastnight-sleepwindow-toosleepy")
        }
    }
}
