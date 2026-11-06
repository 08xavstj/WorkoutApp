import SwiftUI
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
        .accessibilityIdentifier("row-\(title)") // UI tests (ScreenshotTests)
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
                Divider()
                HealthNavigationRow(title: "Supplements", detail: supplementsDetail, icon: "leaf.fill", color: Theme.nutrition) {
                    SupplementsView(pushed: true)
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

    /// Entries in the medications list that the research table recognises (`SupplementKnowledge`).
    private var supplementsDetail: String {
        let count = meds.supplements.count
        guard count > 0 else { return "Research grades and dose checks, creatine to ashwagandha" }
        return "\(count) in your list · research and dose check"
    }

    private var medicationsDetail: String {
        let current = meds.medications.filter(\.isActive).count
        guard current > 0 else { return "Doses, reminders and effects on training" }
        return "\(current) current · doses and reminders"
    }
}

// MARK: - Progress photos, pushed

/// Progress photos pushed from Records (the Log tab opens the same view as a sheet).
private struct ProgressPhotosPage: View {
    var body: some View {
        ProgressPhotosView(pushed: true)
    }
}
