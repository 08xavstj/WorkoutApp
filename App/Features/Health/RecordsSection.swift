import SwiftUI
import SwiftData
import AppCore

/// A list row that pushes a page: icon, title, one line of detail and a
/// chevron (HIG Lists and tables: the chevron means "drill in", ux-audit.md
/// P6). One accessibility element with a hint, 44 pt tall at least (P23, P27).
/// Put rows in one `.card()` with `Divider()`s between them.
struct HealthNavigationRow<Destination: View>: View {
    let title: String
    let detail: String
    let icon: String
    /// The domain's accent for domain rows (heart for blood pressure);
    /// neutral otherwise, so each colour keeps one meaning (ux-audit.md 4.5, P25).
    var color: Color = Theme.secondaryText
    var hint: String = "Opens the page"
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: icon, color: color, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(detail)
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }
}

/// Health › Records: things you add yourself, each row showing its latest
/// entry and pushing the full view (ux-audit.md 4.3, 4.6). Adding new entries
/// also stays in the Log tab.
struct RecordsSection: View {
    @Environment(LabsModel.self) private var labs
    @Environment(VitalsModel.self) private var vitals
    @Environment(BodyMeasurementsStore.self) private var measurements
    @Environment(ProgressPhotosModel.self) private var photos
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Records")
            VStack(spacing: 0) {
                HealthNavigationRow(title: "Lab results", detail: labsDetail, icon: "testtube.2") {
                    LabsView(pushed: true)
                }
                Divider()
                HealthNavigationRow(title: "Blood pressure", detail: bloodPressureDetail, icon: "heart.text.square", color: Theme.heart) {
                    BloodPressureView(pushed: true)
                }
                Divider()
                HealthNavigationRow(title: "Body measurements", detail: measurementsDetail, icon: "ruler") {
                    BodyMeasurementsView(pushed: true)
                }
                Divider()
                HealthNavigationRow(title: "Progress photos", detail: photosDetail, icon: "camera.fill") {
                    ProgressPhotosPage()
                }
                Divider()
                HealthNavigationRow(title: "Medications", detail: medicationsDetail, icon: "pills.fill") {
                    MedicationsView(pushed: true)
                }
            }
            .card()
        }
    }

    // MARK: Latest entries

    /// "today", "yesterday", "3 weeks ago".
    static func ago(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "today" }
        if calendar.isDateInYesterday(date) { return "yesterday" }
        return date.formatted(.relative(presentation: .named))
    }

    private var labsDetail: String {
        guard let last = labs.results.map(\.date).max() else { return "Add blood tests by hand or from a PDF" }
        let flagged = labs.outOfRange.count
        let summary = flagged > 0 ? "\(flagged) outside the range" : "\(labs.latest.count) tests"
        return "\(summary) · \(Self.ago(last))"
    }

    private var bloodPressureDetail: String {
        guard let bp = vitals.stat("bp"), let value = bp.value, let last = bp.series.last else {
            return "Cuff readings and the 7-day home check"
        }
        return "\(value) mmHg · \(Self.ago(last.date))"
    }

    private var measurementsDetail: String {
        var entries: [(name: String, date: Date)] = []
        if let waist = measurements.latestWaist { entries.append((name: "Waist", date: waist.date)) }
        if let grip = measurements.latestGrip { entries.append((name: "Grip", date: grip.date)) }
        if let screen = measurements.stopBang { entries.append((name: "Sleep apnoea screen", date: screen.date)) }
        guard let latest = entries.max(by: { $0.date < $1.date }) else {
            return "Waist, grip and the sleep apnoea screen"
        }
        return "\(latest.name) · \(Self.ago(latest.date))"
    }

    private var photosDetail: String {
        let dates = ProgressPhotosModel.Pose.allCases.compactMap { photos.latest($0)?.date }
        guard let last = dates.max() else { return "Front and side, kept only in the app" }
        return "Last photo · \(Self.ago(last))"
    }

    private var medicationsDetail: String {
        let current = meds.medications.filter(\.isActive).count
        guard current > 0 else { return "Doses, reminders and effects on training" }
        return "\(current) current · doses and reminders"
    }
}

// MARK: - Progress photos, pushed

/// Progress photos pushed from Records, with the same weekly analysis the
/// root sheet runs from `RootView`.
private struct ProgressPhotosPage: View {
    @Environment(ProgressPhotosModel.self) private var photos
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(MuscleModel.self) private var muscles
    @Environment(VitalsModel.self) private var vitals
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        ProgressPhotosView(runAnalysis: analyze, pushed: true)
    }

    private func analyze() async {
        let context = ProgressPhotosContext.text(settings: settings, metrics: metrics, sessions: sessions, muscles: muscles, vitals: vitals)
        await photos.analyze(context: context, settings: settings)
    }
}

/// Goal and data the weekly photo analysis relates the pictures to. The same
/// lines as `RootView.progressContext()` (WorkoutAppApp.swift), which can call
/// this instead.
enum ProgressPhotosContext {
    static func text(settings: UserSettings, metrics: DailyMetricsModel, sessions: [WorkoutSession],
                     muscles: MuscleModel, vitals: VitalsModel) -> String {
        var lines: [String] = []
        lines.append("Sex: \(settings.sex.rawValue), age \(settings.age).")
        lines.append(settings.goalsSet ? "Goal: \(settings.goals.title)." : "No goal set.")
        if let weight = metrics.bodyMassKg { lines.append("Weight: \(weight.formatted(.number.precision(.fractionLength(1)))) kg.") }
        if let weekly = metrics.weightTrendWeekly { lines.append("Weight trend: \(weekly.formatted(.number.precision(.fractionLength(2)))) kg/week (last 4 weeks).") }
        if let maintenance = metrics.maintenance {
            lines.append("Average intake \(whole(maintenance.averageIntake)) kcal vs measured maintenance \(whole(maintenance.maintenance)) kcal.")
        }
        if let target = metrics.calorieTarget { lines.append("Calorie target \(whole(target)) kcal/day.") }
        if let protein = metrics.proteinTarget { lines.append("Protein target \(whole(protein)) g/day.") }
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let recentSessions = sessions.filter { !$0.isActive && $0.startedAt >= cutoff }.count
        lines.append("Gym sessions in the last 2 weeks: \(recentSessions).")
        let weekly = muscles.states.values.filter { $0.weeklySets > 0 }
            .sorted { $0.weeklySets > $1.weeklySets }
            .map { "\($0.muscle.name) \($0.weeklySets.formatted(.number.precision(.fractionLength(0...1))))" }
        if !weekly.isEmpty { lines.append("Hard sets per muscle this week: " + weekly.joined(separator: ", ") + ".") }
        if let fat = vitals.stat("fat")?.value { lines.append("Smart-scale body fat: \(fat)%.") }
        return lines.joined(separator: "\n")
    }
}
