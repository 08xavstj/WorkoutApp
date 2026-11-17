import SwiftUI

/// Apple's Health Age, as typed in from the Health app.
///
/// The Health app in iOS 27.3 (with an Apple Watch) shows a Health Age worked
/// out from resting heart rate, VO₂ max, sleep and HRV (Apple's announcement,
/// 3 Nov 2026; the method isn't published). Apple offers no HealthKit type
/// for it: checked on 17 Nov 2026, the HealthKit updates page lists none and
/// there is no `healthAge` identifier. So the app can't read it, and the
/// number is typed in. When Apple adds an API, read it in `VitalsModel` and
/// keep this entry as the fallback.
enum AppleHealthAge {
    static let valueKey = "appleHealthAge"
    static let dateKey = "appleHealthAgeDate"
    /// Ages a typed value may be (anything else is a typo).
    static let plausible = 10...120

    /// The saved value, or nil when none was typed.
    static var saved: (years: Int, date: Date)? {
        let years = UserDefaults.standard.integer(forKey: valueKey)
        guard plausible.contains(years) else { return nil }
        return (years, Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: dateKey)))
    }
}

/// The card on Health › Body age: Apple's number beside Tensile's estimate,
/// a field to type it into, and a link to the Health app.
struct AppleHealthAgeCard: View {
    /// Tensile's own estimate, for the comparison line.
    let estimate: ClosedRange<Int>?

    @AppStorage(AppleHealthAge.valueKey) private var years = 0
    @AppStorage(AppleHealthAge.dateKey) private var enteredAt = 0.0
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var parsed: Int? {
        guard let value = Int(draft.trimmingCharacters(in: .whitespaces)), AppleHealthAge.plausible.contains(value) else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Apple's Health Age")
            if AppleHealthAge.plausible.contains(years) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(years)")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .foregroundStyle(Theme.primaryText)
                    Text("years · entered \(Date(timeIntervalSince1970: enteredAt).formatted(.relative(presentation: .named)))")
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
                Button("Save") {
                    guard let parsed else { return }
                    years = parsed
                    enteredAt = Date.now.timeIntervalSince1970
                    draft = ""
                    editing = false
                }
                .buttonStyle(.bordered)
                .disabled(parsed == nil)
                Spacer(minLength: 0)
                if let url = URL(string: "x-apple-health://") {
                    Link("Open Health", destination: url)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
