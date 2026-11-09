import SwiftUI
import AppCore

/// Sex, age, height and weight, asked for when Apple Health doesn't have
/// them: onboarding's "About you" step and Today's `ProfileSetupCard`.
/// Until they're set the app uses stand-ins (male, 30) only so the maths can
/// run, and says "Not set" instead of quietly applying men's norms.
struct ProfileBasicsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    /// True when pushed onto another NavigationStack (onboarding).
    var pushed = false

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            Form {
                ProfileBasicsRows()
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .refreshingOnProfileChange()
            .navigationTitle("About you")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

/// The four fields, as one Form section. Fields Apple Health fills stay
/// editable in Settings › Profile.
struct ProfileBasicsRows: View {
    @Environment(UserSettings.self) private var settings
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 80

    /// Inches alongside pounds, centimetres alongside kilograms; stored in cm.
    private var heightUnit: LengthUnit { settings.weightUnit == .pounds ? .inches : .centimeters }

    var body: some View {
        Section {
            SexPickerRow()
            AgePickerRow()
            LabeledContent("Height") {
                HStack(spacing: 4) {
                    TextField("Not set", value: heightBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: fieldWidth)
                    Text(heightUnit.rawValue).foregroundStyle(Theme.secondaryText)
                }
            }
            LabeledContent("Weight") {
                HStack(spacing: 4) {
                    TextField("Not set", value: weightBinding, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: fieldWidth)
                    Text(settings.weightUnit.rawValue).foregroundStyle(Theme.secondaryText)
                }
            }
        } footer: {
            Text("Heart-rate zones, calories, fitness norms and body age depend on these. They stay on this iPhone.")
        }
    }

    /// Accepts 100-250 cm (app sanity range, the same floor the Health sync uses).
    private var heightBinding: Binding<Double?> {
        Binding(
            get: { settings.heightCm > 0 ? (heightUnit.display(settings.heightCm) * 10).rounded() / 10 : nil },
            set: { value in
                guard let value else { return }
                let cm = heightUnit.toCentimeters(value)
                if (100...250).contains(cm) { settings.heightCm = cm }
            }
        )
    }

    /// Accepts 30-300 kg (app sanity range, the same floor the Health sync uses).
    private var weightBinding: Binding<Double?> {
        Binding(
            get: { settings.weightKg > 0 ? (settings.weightUnit.display(settings.weightKg) * 10).rounded() / 10 : nil },
            set: { value in
                guard let value else { return }
                let kg = settings.weightUnit.toKilograms(value)
                if (30...300).contains(kg) { settings.weightKg = kg }
            }
        )
    }
}

/// Sex with a "Not set" choice until one is picked. Labelled "Sex" because
/// the norms behind it (VO₂ max, grip, calories) are by sex at birth.
struct SexPickerRow: View {
    @Environment(UserSettings.self) private var settings
    var suffix = ""

    var body: some View {
        Picker("Sex\(suffix)", selection: Binding<BiologicalSex?>(
            get: { settings.sexIsSet ? settings.sex : nil },
            set: { value in if let value { settings.sex = value } }
        )) {
            if !settings.sexIsSet {
                Text("Not set").tag(BiologicalSex?.none)
            }
            Text("Female").tag(BiologicalSex?.some(.female))
            Text("Male").tag(BiologicalSex?.some(.male))
        }
    }
}

/// Age 13-100 with a "Not set" choice until one is picked.
struct AgePickerRow: View {
    @Environment(UserSettings.self) private var settings
    var suffix = ""

    var body: some View {
        Picker("Age\(suffix)", selection: Binding<Int?>(
            get: { settings.ageIsSet ? settings.age : nil },
            set: { value in if let value { settings.age = value } }
        )) {
            if !settings.ageIsSet {
                Text("Not set").tag(Int?.none)
            }
            ForEach(13...100, id: \.self) { age in
                Text("\(age)").tag(Int?.some(age))
            }
        }
    }
}

/// Today's card while sex, age, height or weight is missing: shown until
/// they're set (no "Not now"), because without them women get men's norms.
struct ProfileSetupCard: View {
    @Environment(UserSettings.self) private var settings
    @State private var showingForm = false

    var body: some View {
        // Kept while its sheet is open, so typing the last field doesn't pull the sheet away.
        if settings.hasOnboarded, settings.profileBasicsMissing || showingForm {
            Button {
                showingForm = true
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemName: "person.crop.circle.badge.questionmark", color: Theme.oxygen, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add your \(missingList)")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Text("Apple Health doesn't have \(pronoun). Zones, calories and fitness norms need \(pronoun).")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card(tint: Theme.oxygen)
            .sheet(isPresented: $showingForm) { ProfileBasicsView() }
        }
    }

    private var pronoun: String { missingList.contains(" and ") ? "them" : "it" }

    /// "sex and age", "height", "sex, age and weight".
    private var missingList: String {
        var parts: [String] = []
        if !settings.sexIsSet { parts.append("sex") }
        if !settings.ageIsSet { parts.append("age") }
        if settings.heightCm <= 0 { parts.append("height") }
        if settings.weightKg <= 0 { parts.append("weight") }
        guard let last = parts.popLast() else { return "details" }
        return parts.isEmpty ? last : parts.joined(separator: ", ") + " and " + last
    }
}

extension View {
    /// Refreshes the scores once sex, age, height or the weight unit change,
    /// so norms, zones, calories and stored display units don't go stale.
    func refreshingOnProfileChange() -> some View {
        modifier(ProfileChangeRefresh())
    }
}

private struct ProfileChangeRefresh: ViewModifier {
    @Environment(UserSettings.self) private var settings
    @Environment(AppRefresher.self) private var refresher
    @State private var pending: Task<Void, Never>?

    /// Everything that changes what other screens show.
    private var key: String {
        let sex = settings.sexIsSet ? settings.sex.rawValue : "unset"
        let age = settings.ageIsSet ? String(settings.age) : "unset"
        return [sex, age, String(settings.heightCm), settings.weightUnit.rawValue].joined(separator: "|")
    }

    func body(content: Content) -> some View {
        content.onChange(of: key) { refreshSoon() }
    }

    /// One refresh a second after the last change (a picker or typing fires several).
    private func refreshSoon() {
        pending?.cancel()
        let refresher = refresher
        pending = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await refresher.refresh()
        }
    }
}
