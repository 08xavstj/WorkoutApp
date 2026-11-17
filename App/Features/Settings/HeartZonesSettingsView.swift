import SwiftUI
import AppCore

/// Settings › Training › Heart-rate zones: the row that opens the page.
struct HeartZonesSettingsRow: View {
    @AppStorage(ZonePreferences.kindKey) private var kindRaw = HeartRateZoneScheme.Kind.reserve.rawValue

    var body: some View {
        NavigationLink {
            HeartZonesSettingsView()
        } label: {
            LabeledContent("Heart-rate zones", value: (HeartRateZoneScheme.Kind(rawValue: kindRaw) ?? .reserve).title)
        }
        .accessibilityIdentifier("settings-heart-zones")
    }
}

/// Which heart-rate zones the app shows in workouts and sends to the Watch's
/// cardio mode (`HeartRateZoneScheme`; docs/research/workout-zones-2026-11.md).
/// Four options, each with one sentence and the bpm ranges it gives. Day
/// strain stays on heart-rate reserve whatever is picked, and the page says so.
struct HeartZonesSettingsView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(DailyMetricsModel.self) private var metrics
    @Environment(\.healthClient) private var health
    @AppStorage(ZonePreferences.kindKey) private var kindRaw = HeartRateZoneScheme.Kind.reserve.rawValue
    /// What Apple Health answered when the page opened; nil until it has.
    @State private var reading: HealthZoneReading?
    /// The five typed limits, as text.
    @State private var customText = Array(repeating: "", count: HeartRateZoneScheme.zoneCount)
    /// Bumped after a write to `ZonePreferences`, so the ranges redraw.
    @State private var revision = 0
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 70

    private var kind: HeartRateZoneScheme.Kind { HeartRateZoneScheme.Kind(rawValue: kindRaw) ?? .reserve }

    /// Today's profile, or the settings profile before the first refresh.
    private var profile: HeartRateProfile {
        metrics.heartRateProfile ?? settings.heartRateProfile(restingHeartRate: nil)
    }

    /// The scheme in use. Reading `revision` redraws the page after a write to `ZonePreferences`.
    private var currentResolution: HeartRateZoneScheme.Resolution {
        _ = revision
        return ZonePreferences.resolution(profile: profile)
    }

    var body: some View {
        let resolution = currentResolution
        let scheme = resolution.scheme
        Form {
            Section {
                ForEach(HeartRateZoneScheme.Kind.allCases) { option in
                    ZoneOptionRow(kind: option, isSelected: option == kind, note: note(for: option)) {
                        select(option)
                    }
                }
            } header: {
                Text("Zones to show")
            } footer: {
                Text("Day strain and the Fitness tab's daily zone minutes always use heart-rate reserve, whatever you pick. The strain formula was built on reserve, and changing its scale would change every past score. Your choice sets the zones in workouts and on the Watch.")
            }
            if kind == .custom {
                customSection
            }
            Section {
                ForEach(1...HeartRateZoneScheme.zoneCount, id: \.self) { zone in
                    ZoneRangeRow(zone: zone, range: scheme.rangeText(forZone: zone))
                }
            } header: {
                Text("In use: \(scheme.kind.title)")
            } footer: {
                if resolution.fellBack {
                    Text(fallbackText(for: resolution.requested))
                } else if scheme.floor == nil {
                    Text("Zone 1 has no lower limit here, so all time under zone 2 counts as zone 1.")
                }
            }
            Section {
                LabeledContent("Easy", value: "\(scheme.easyBand.text) bpm")
            } header: {
                Text("Easy target")
            } footer: {
                Text("For easy cardio on the Watch: 40–60% of your heart-rate reserve, a pace you can talk at. \(easyPlacement(in: scheme)) It is an estimate. If you can't talk in full sentences, slow down, whatever the number says.")
            }
            Section {
                EvidenceDisclosure(points: Self.evidence, title: "How these work")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationTitle("Heart-rate zones")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            fillCustomText()
            reading = await ZonePreferences.refreshAppleZones(health: health, force: true)
            revision += 1
        }
        .onChange(of: customText) { saveCustom() }
        // The Watch's cardio mode gets the zones as soon as they change.
        .onChange(of: scheme, initial: true) { WatchSync.shared.updateZones(profile: profile) }
    }

    private var customSection: some View {
        Section {
            ForEach(0..<HeartRateZoneScheme.zoneCount, id: \.self) { index in
                LabeledContent("Zone \(index + 1) starts at") {
                    HStack(spacing: 4) {
                        TextField("bpm", text: $customText[index])
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: fieldWidth)
                            .accessibilityIdentifier("heart-zones-custom-\(index + 1)")
                        Text("bpm").foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            if typedStarts == nil {
                Text("Each zone must start at least 1 bpm above the one before, between 40 and 230.")
                    .font(.footnote)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
        } header: {
            Text("Your limits")
        } footer: {
            Text("Type where each zone starts. They are saved once all five rise in order.")
        }
    }

    /// The typed limits when all five are numbers that rise in order.
    private var typedStarts: [Double]? {
        let values = customText.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == HeartRateZoneScheme.zoneCount else { return nil }
        return HeartRateZoneScheme.validated(values)
    }

    private func select(_ option: HeartRateZoneScheme.Kind) {
        kindRaw = option.rawValue
        // Custom starts from the limits on screen, so it is never empty.
        if option == .custom, ZonePreferences.customStarts == nil { saveCustom() }
        revision += 1
    }

    private func saveCustom() {
        guard let starts = typedStarts, starts != ZonePreferences.customStarts else { return }
        ZonePreferences.customStarts = starts
        revision += 1
    }

    /// The saved limits, or Tensile's as a starting point.
    private func fillCustomText() {
        guard customText.allSatisfy(\.isEmpty) else { return }
        let tensile = HeartRateZoneScheme.tensile(profile: profile)
        let starts = ZonePreferences.customStarts ?? ([tensile.floor ?? 0] + tensile.boundaries)
        guard starts.count == HeartRateZoneScheme.zoneCount else { return }
        customText = starts.map { "\(Int($0.rounded()))" }
    }

    /// A line under an option: where Apple Health's zones came from, or why they can't be used.
    private func note(for option: HeartRateZoneScheme.Kind) -> String? {
        guard option == .appleHealth, let reading else { return nil }
        switch reading {
        case .unsupported: return "Needs iOS 27."
        case .none: return "Apple Health has no heart-rate zones yet."
        case .failed: return "Apple Health's zones couldn't be read just now."
        case let .zones(_, boundaries, setByUser):
            if boundaries.count != HeartRateZoneScheme.zoneCount - 1 { return "Apple Health has \(boundaries.count + 1) zones; Tensile draws five." }
            return setByUser ? "Set by you in Apple's settings." : "Worked out by Apple Health."
        }
    }

    private func fallbackText(for requested: HeartRateZoneScheme.Kind) -> String {
        switch requested {
        case .appleHealth:
            "Apple Health's zones aren't available, so Tensile's are shown. They need iOS 27 and your date of birth in Health. You can also set them in the Watch app under Workout › Heart Rate Zones."
        case .custom:
            "Your limits aren't complete yet, so Tensile's zones are shown."
        case .reserve, .percentOfMax:
            "Tensile's zones are shown."
        }
    }

    /// "In these zones that is zone 1 and just under it."
    private func easyPlacement(in scheme: HeartRateZoneScheme) -> String {
        let low = scheme.zone(for: scheme.easyBand.lower)
        guard let high = scheme.zone(for: scheme.easyBand.upper - 1) else {
            return "In these zones that is under zone 1."
        }
        guard let low else { return "In these zones that is zone \(high) and just under it." }
        return low == high ? "In these zones that is zone \(low)." : "In these zones that is zones \(low)–\(high)."
    }

    /// Short points with their sources (docs/research/workout-zones-2026-11.md).
    private static let evidence = [
        "No percentage fits everyone. In 100 adults the first threshold sat anywhere from 60% to 90% of maximum heart rate (Iannetta 2020). Zones are labels for effort, not measurements.",
        "Tensile: five steps from 50% to 100% of heart-rate reserve (Karvonen 1957), the scale the strain formula uses (Banister 1991).",
        "Percent of max: five steps from 50% to 100% of maximum (Edwards 1993). The same heart rate lands about a zone higher than on Tensile's scale.",
        "Apple Health: Apple doesn't publish the percentages behind its zones.",
        "Easy: moderate intensity by the ACSM, 40–59% of reserve (Garber 2011). The talk test tracks the first threshold (Reed & Pipe 2014).",
        "Easy cardio is not proven better than harder work. Mostly easy with some hard training raised VO₂peak a little more than other mixes over under 12 weeks, and race times no more (Oliveira 2024).",
    ]
}

/// One zone option: its name, one sentence, and a checkmark when chosen.
private struct ZoneOptionRow: View {
    let kind: HeartRateZoneScheme.Kind
    let isSelected: Bool
    let note: String?
    let select: () -> Void

    var body: some View {
        Button {
            select()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.title)
                        .foregroundStyle(Theme.primaryText)
                    Text(kind.explanation)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.heartText)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("heart-zones-option-\(kind.rawValue)")
    }
}

/// "Zone 2   133–146 bpm" with the zone's color.
private struct ZoneRangeRow: View {
    let zone: Int
    let range: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.zoneColors[zone - 1])
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text("Zone \(zone)")
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            Text("\(range) bpm")
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}
