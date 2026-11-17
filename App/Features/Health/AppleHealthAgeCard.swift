import SwiftUI
import AppCore

/// Apple's Health Age, as brought in from the Health app.
///
/// The Health app in iOS 27.3 (with an Apple Watch) shows a Health Age worked
/// out from resting heart rate, VO₂ max, sleep and HRV (Apple's announcement,
/// 3 Nov 2026; the method isn't published). Apple offers no HealthKit type
/// for it: checked again on 17 Nov 2026 against the type lists, the HealthKit
/// updates page and the iOS 27.2 and 27.3 release notes
/// (docs/research/apple-scores-2026-11.md). So the app can't read it.
///
/// The value and its history now live in `AppleScoresStore`, with Apple's
/// Readiness and Sleep score. These two UserDefaults keys are where the first
/// version kept its one typed value: the store moves that value into its log
/// once and then keeps the keys in step with the latest Health Age, because
/// Health › Key measures still reads them with `@AppStorage`.
enum AppleHealthAge {
    static let valueKey = "appleHealthAge"
    static let dateKey = "appleHealthAgeDate"
    /// Ages a typed value may be (anything else is a typo).
    static let plausible = AppleScoreKind.healthAge.range

    /// The value in UserDefaults, or nil when there is none.
    static var saved: (years: Int, date: Date)? {
        let years = UserDefaults.standard.integer(forKey: valueKey)
        guard plausible.contains(years) else { return nil }
        return (years, Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: dateKey)))
    }
}

/// The card on Health › Body age: Apple's number beside Tensile's estimate,
/// a field to type it into, and links to the Health app and to the page with
/// all of Apple's scores.
struct AppleHealthAgeCard: View {
    /// Tensile's own estimate, for the comparison line.
    let estimate: ClosedRange<Int>?

    @Environment(VitalsModel.self) private var vitals
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var store: AppleScoresStore { .shared }

    private var parsed: Int? {
        guard let value = Int(draft.trimmingCharacters(in: .whitespaces)), AppleScoreKind.healthAge.accepts(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Apple's Health Age")
            if let latest = store.latest(.healthAge) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(latest.reading.value)")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.primaryText)
                    Text("years · added \(AppleScoresView.dayText(latest.day))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if let estimate {
                    Text("Tensile's estimate is \(estimate.lowerBound)–\(estimate.upperBound). The two won't match exactly: Apple uses heart rate, VO₂ max, sleep and HRV; Tensile's also counts body composition and daily steps.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("The Health app (iOS 27.3, with an Apple Watch) works out a Health Age from your resting heart rate, VO₂ max, sleep and HRV. Apple doesn't share it with other apps yet, so type it in here to keep it beside Tensile's estimate.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                TextField("Health Age", text: $draft)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 130)
                    .focused($editing)
                    .accessibilityLabel("Apple's Health Age in years")
                Button("Save", action: save)
                    .buttonStyle(.bordered)
                    .disabled(parsed == nil)
                Spacer(minLength: 0)
                if let url = URL(string: "x-apple-health://") {
                    Link("Open Health", destination: url)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(minHeight: 44)
            NavigationLink {
                AppleScoresView()
            } label: {
                HStack {
                    Text("Readiness and Sleep score too")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.primaryText)
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Apple's scores, with a screenshot reader and history")
            .accessibilityIdentifier("apple-scores-link")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Saves today's Health Age with Tensile's current body age beside it.
    private func save() {
        guard let parsed else { return }
        store.save([.healthAge: parsed], on: store.now, source: .typed)
        if let years = vitals.bodyAge?.years {
            store.keepAppValues(recovery: nil, recoveryIsFromYesterday: false, bodyAge: years)
        }
        draft = ""
        editing = false
    }
}
