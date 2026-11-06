import SwiftUI
import SwiftData

/// The Log tab: start a workout, or log a measurement
/// (docs/research/ux-audit.md 4.4).
///
/// One primary action (Start workout) above a grouped list of log rows, ordered
/// by how often people log them: daily, then weekly, monthly, yearly. "Place
/// the most important items near the top" and "group related items" (HIG
/// *Layout*); a recommended default lowers choice effort when the options are
/// many (Chernev, Böckenholt & Goodman, J Consum Psychol 2015, meta-analysis).
/// Rows that open a form show a "+"; rows that push show the list's chevron
/// (HIG *Lists and tables*).
struct LogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkoutLauncher.self) private var launcher
    @Environment(AppRouter.self) private var router
    @State private var showingSavedWorkouts = false
    @State private var showingLabs = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StartWorkoutButtons(
                        start: { launcher.openBuilder() },
                        startEmpty: { launcher.startEmpty(in: modelContext) },
                        openSaved: { showingSavedWorkouts = true }
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                logSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.rose, Theme.Wash.peach, Theme.Wash.butter])
            }
            .background(Theme.background)
            .navigationTitle("Log")
            .tabToolbar()
            .navigationDestination(isPresented: $showingSavedWorkouts) { MyWorkoutsView() }
            .sheet(isPresented: $showingLabs) { LabsView() }
        }
    }

    /// Daily logs first (HRV, drinks), then weekly, monthly, yearly.
    private var logSection: some View {
        Section("Log") {
            Button { router.showHRVEntry = true } label: {
                LogRow(title: "Overnight HRV", detail: "Type it or measure with the camera", icon: "waveform.path.ecg")
            }
            NavigationLink {
                AlcoholLogView()
            } label: {
                LogRow(title: "Drinks", detail: "Alcohol, for today or an earlier day", icon: "wineglass.fill", opensForm: false)
            }
            Button { router.showBloodPressure = true } label: {
                LogRow(title: "Blood pressure", detail: "One reading or the 7-day check", icon: "heart.text.square", color: Theme.heart)
            }
            Button { router.showProgressPhotos = true } label: {
                LogRow(title: "Progress photo", detail: "Front and side", icon: "camera.fill")
            }
            Button { router.showMeasurements = true } label: {
                LogRow(title: "Waist & grip", detail: "Monthly waist, grip twice a year", icon: "ruler")
            }
            Button { showingLabs = true } label: {
                LogRow(title: "Lab results", detail: "Type in results from your report", icon: "testtube.2")
            }
            // Doses are logged with a Taken button on the Medications page (also Health › Records).
            NavigationLink {
                MedicationsView(pushed: true)
            } label: {
                LogRow(title: "Medications & supplements", detail: "Tick off today's doses", icon: "pills.fill", opensForm: false)
            }
        }
    }
}

/// Start workout (primary, opens the builder) with Empty workout and Saved
/// workouts beneath it as smaller secondary buttons (ux-audit 4.4).
private struct StartWorkoutButtons: View {
    let start: () -> Void
    let startEmpty: () -> Void
    let openSaved: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Side by side normally; stacked at accessibility sizes so neither label truncates.
        let stacked = dynamicTypeSize.isAccessibilitySize
        let secondary = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        VStack(spacing: 10) {
            Button(action: start) {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 8)
                    .background(LinearGradient(colors: Theme.strainButtonColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("The trainer plans it from your gym and recovery.")

            secondary {
                SecondaryCapsuleButton(title: "Empty workout", systemImage: "dumbbell.fill", stacked: stacked, action: startEmpty)
                    .accessibilityHint("Starts now. Add exercises as you go.")
                SecondaryCapsuleButton(title: "Saved workouts", systemImage: "list.bullet.rectangle.portrait", stacked: stacked, action: openSaved)
            }
        }
    }
}

private struct SecondaryCapsuleButton: View {
    let title: String
    let systemImage: String
    /// Full width under the other button: the label may wrap instead of shrinking.
    var stacked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(stacked ? nil : 1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.card, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// One row: icon in its domain colour (heart for blood pressure, nutrition for
/// meals) or neutral grey, a title and a one-line description (ux-audit 4.4, P25).
private struct LogRow: View {
    let title: String
    let detail: String
    let icon: String
    var color: Color = Theme.secondaryText
    /// Opens a sheet (shows "+"); pushes otherwise (the list adds a chevron).
    var opensForm = true
    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, color: color, size: badgeSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if opensForm {
                Image(systemName: "plus")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}
