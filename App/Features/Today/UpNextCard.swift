import SwiftUI
import AppCore

/// Today's "Up next": at most four small things to do, ordered by time of
/// day, each with an icon, one line and a trailing action; hidden when there's
/// nothing. It replaces the daily check-in, medications, sleep debt and daily
/// habits cards, which each took a full card (docs/research/ux-audit.md 4.3,
/// 4.6, H1, H2; HIG Layout: most important first, group related items, P7).
///
/// Rows: morning and evening check-in (until done), medication doses due
/// (with Take), the caffeine cut-off, the day's movement nudge, a weigh-in
/// reminder, the breathing offer and tonight's bed-by window. Today's planned
/// session is the Scores card's button, so it isn't repeated here.
struct UpNextCard: View {
    let habits: TodayHabits

    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(UserSettings.self) private var settings
    @Environment(CheckInStore.self) private var checkIns
    @Environment(MedicationsModel.self) private var meds

    /// Most rows shown at once (ux-audit.md 4.6).
    private static let maximumRows = 4

    var body: some View {
        let items = Array(upNextItems().prefix(Self.maximumRows))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                CardLabel(text: "Up next")
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    UpNextItemRow(item: item)
                }
            }
            .card()
        }
    }

    // MARK: Building the rows

    private func upNextItems() -> [UpNextItem] {
        let now = Self.minutesNow()
        var items: [UpNextItem] = []
        items += checkInItems(now: now)
        items += doseItems()
        if let caffeine = caffeineItem(now: now) { items.append(caffeine) }
        if let nudge = habits.movementNudge { items.append(movementItem(nudge, now: now)) }
        if WeighInNudge.isDue(goals: metrics.goals, lastWeighIn: metrics.lastWeighIn) {
            // Lose/gain goal with no weigh-in for 3+ days (`WeighInNudge`: Zheng 2015; Madigan 2015).
            items.append(UpNextItem(id: "weighin", minutes: settings.morningCheckInMinutes, kind: .info(
                icon: "scalemass", color: Theme.nutrition, title: WeighInNudge.title,
                detail: WeighInNudge.detail(lastWeighIn: metrics.lastWeighIn))))
        }
        if BreathingOfferRow.isOffered(metrics: metrics, checkIns: checkIns) {
            items.append(UpNextItem(id: "breathing", minutes: now, kind: .breathing))
        }
        if let bedtime = bedtimeItem() { items.append(bedtime) }
        return items.sorted { $0.minutes < $1.minutes }
    }

    /// Morning check-in until it's done; the evening one from noon until it's done.
    private func checkInItems(now: Int) -> [UpNextItem] {
        var items: [UpNextItem] = []
        if checkIns.morning() == nil {
            items.append(UpNextItem(id: "checkin-morning", minutes: settings.morningCheckInMinutes, kind: .checkIn(.morning)))
        }
        if checkIns.evening() == nil, now >= 12 * 60 {
            items.append(UpNextItem(id: "checkin-evening", minutes: settings.eveningCheckInMinutes, kind: .checkIn(.evening)))
        }
        return items
    }

    /// Today's doses that are due (their time has come) and not taken yet.
    /// The full list is in Health › Records › Medications (also the Log tab and Settings).
    private func doseItems() -> [UpNextItem] {
        meds.todayDoses
            .filter { !meds.isTaken($0) && $0.time <= .now }
            .map { UpNextItem(id: "dose-\($0.id)", minutes: $0.minutes, kind: .dose($0)) }
    }

    /// The caffeine cut-off before it passes, or a warning when today's last
    /// caffeine was late (`CaffeineTiming`).
    private func caffeineItem(now: Int) -> UpNextItem? {
        let caffeine = habits.caffeine(metrics: metrics, checkIns: checkIns)
        guard caffeine.isLate || now < caffeine.cutoffMinutes else { return nil }
        return UpNextItem(id: "caffeine", minutes: caffeine.cutoffMinutes, kind: .info(
            icon: "cup.and.saucer.fill",
            color: caffeine.isLate ? Theme.recoveryModerate : Theme.sleep,
            title: caffeine.title,
            detail: caffeine.detail))
    }

    /// At most one nudge a day (`MovementBreaks`; Buffey 2022; Dunstan 2012).
    private func movementItem(_ nudge: MovementBreaks.Nudge, now: Int) -> UpNextItem {
        switch nudge {
        case .postMealWalk:
            UpNextItem(id: "movement", minutes: now, kind: .info(
                icon: "figure.walk", color: Theme.strain,
                title: MovementBreaks.postMealTitle, detail: MovementBreaks.postMealDetail))
        case .sedentary(let hours):
            UpNextItem(id: "movement", minutes: now, kind: .info(
                icon: "figure.walk.motion", color: Theme.strain,
                title: MovementBreaks.sedentaryTitle, detail: MovementBreaks.sedentaryDetail(hours: hours)))
        }
    }

    /// Tonight's bed-by window while there's sleep debt (`BedtimeWindow`: the
    /// wake time stays put, Windred et al., Sleep 2024, and repayment comes
    /// from going to bed earlier). Opens last night's sheet with the debt.
    private func bedtimeItem() -> UpNextItem? {
        guard let debt = metrics.sleepDebt, debt.level != .none, let window = metrics.bedtimeWindow else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: window.start)
        var minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A window after midnight still comes last today.
        if minutes < 12 * 60 { minutes += 24 * 60 }
        return UpNextItem(id: "bedtime", minutes: minutes, kind: .bedtime(
            title: "In bed by \(window.windowText) tonight",
            detail: "Sleep debt \(SleepText.hours(debt.hours))"))
    }

    private static func minutesNow() -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// One Up next row's content.
private struct UpNextItem: Identifiable {
    enum Kind {
        case checkIn(CheckInKind)
        case dose(Dose)
        case breathing
        case bedtime(title: String, detail: String)
        /// Advice with no action, e.g. the caffeine cut-off.
        case info(icon: String, color: Color, title: String, detail: String?)
    }

    let id: String
    /// When it's due, in minutes after midnight (the sort order).
    let minutes: Int
    let kind: Kind
}

// MARK: - Rows

private struct UpNextItemRow: View {
    let item: UpNextItem

    var body: some View {
        switch item.kind {
        case .checkIn(let kind):
            CheckInUpNextRow(kind: kind)
        case .dose(let dose):
            DoseUpNextRow(dose: dose)
        case .breathing:
            BreathingOfferRow()
        case .bedtime(let title, let detail):
            BedtimeUpNextRow(title: title, detail: detail)
        case .info(let icon, let color, let title, let detail):
            UpNextRow(icon: icon, color: color, title: title, detail: detail)
                .accessibilityElement(children: .combine)
        }
    }
}

private struct CheckInUpNextRow: View {
    let kind: CheckInKind
    @Environment(AppRouter.self) private var router

    var body: some View {
        let isMorning = kind == .morning
        Button { router.checkIn = kind } label: {
            UpNextRow(
                icon: isMorning ? "sun.max.fill" : "moon.stars.fill",
                color: Theme.secondaryText,
                title: isMorning ? "Morning check-in · 1 min" : "Evening check-in · 1 min",
                detail: isMorning ? "How you slept and how you feel" : "Caffeine, drinks and how the day went"
            ) {
                UpNextChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the check-in")
    }
}

/// A dose that's due, with Take (the full list with undo is in Medications).
private struct DoseUpNextRow: View {
    let dose: Dose
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        UpNextRow(
            icon: "pills.fill",
            color: Theme.secondaryText,
            title: dose.name,
            detail: [dose.dose, dose.time.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · ")
        ) {
            Button("Take") { meds.toggle(dose) }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityLabel("Take \(dose.name)")
        }
    }
}

private struct BedtimeUpNextRow: View {
    let title: String
    let detail: String
    @State private var showingSleep = false

    var body: some View {
        Button { showingSleep = true } label: {
            UpNextRow(icon: "bed.double.fill", color: Theme.sleep, title: title, detail: detail) {
                UpNextChevron()
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows last night's sleep and your sleep debt")
        .sheet(isPresented: $showingSleep) {
            LastNightSleepSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

/// The row layout: icon, a line (and an optional detail), then a trailing
/// action or chevron. At least 44 pt tall (HIG Accessibility; ux-audit.md P23).
private struct UpNextRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String?
    let trailing: Trailing

    init(icon: String, color: Color, title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.icon = icon
        self.color = color
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(systemName: icon, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

extension UpNextRow where Trailing == EmptyView {
    /// A row with nothing trailing (advice only).
    init(icon: String, color: Color, title: String, detail: String? = nil) {
        self.init(icon: icon, color: color, title: title, detail: detail) { EmptyView() }
    }
}

/// The trailing chevron of a row that opens something.
private struct UpNextChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}
