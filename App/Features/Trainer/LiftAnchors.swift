import SwiftUI
import AppCore

/// Five-rep maxes you typed in ("Know your numbers?" in the workout builder),
/// in kilograms, in UserDefaults. First-time weights start from these
/// (`LoadEstimator.Lifter.anchorOneRepMaxKg`) instead of the body-weight
/// tables, which are population averages with a wide spread.
@Observable
final class LiftAnchorsStore {
    static let shared = LiftAnchorsStore()

    private static let key = "liftAnchorFiveRepMaxKg"

    /// The lifts asked about: the reference lift of a movement each.
    enum Lift: String, CaseIterable, Identifiable {
        case bench, squat, deadlift, press

        var id: String { rawValue }

        var title: String {
            switch self {
            case .bench: "Bench press"
            case .squat: "Back squat"
            case .deadlift: "Deadlift"
            case .press: "Overhead press"
            }
        }
    }

    /// Lift → kilograms for 5 reps.
    private(set) var values: [String: Double]

    init() {
        values = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    func value(_ lift: Lift) -> Double? { values[lift.rawValue] }

    /// Nil or 0 clears the lift.
    func set(_ kilograms: Double?, for lift: Lift) {
        if let kilograms, kilograms.isFinite, kilograms > 0 {
            values[lift.rawValue] = kilograms
        } else {
            values[lift.rawValue] = nil
        }
        UserDefaults.standard.set(values, forKey: Self.key)
    }

    var isEmpty: Bool { values.isEmpty }

    /// 1RMs by movement for the planner (`LoadEstimator.anchors`).
    var anchors: [MovementSlot: Double] {
        LoadEstimator.anchors(benchKg: value(.bench), squatKg: value(.squat), deadliftKg: value(.deadlift),
                              pressKg: value(.press))
    }
}

/// "Know your numbers?": an optional row in the workout builder for your
/// 5-rep bench, squat, deadlift and overhead press. Collapsed until tapped.
struct KnowYourNumbersRow: View {
    var unit: LoadUnit
    /// Called after a number changes, so the plan is rebuilt.
    var onChange: () -> Void

    @State private var store = LiftAnchorsStore.shared
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the fields" : "Shows fields for your 5-rep maxes")
            if isExpanded {
                Text("Your best weight for 5 reps. New lifts start from these instead of averages for your body weight.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(LiftAnchorsStore.Lift.allCases) { lift in
                    AnchorField(lift: lift, unit: unit, store: store, onChange: onChange)
                }
            }
        }
        .card()
    }

    private var header: some View {
        HStack {
            CardLabel(text: "Know your numbers?")
            Spacer()
            Text(store.isEmpty ? "Optional" : "\(store.values.count) set")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

/// One lift's 5-rep max, in the gym's unit, saved in kilograms.
private struct AnchorField: View {
    let lift: LiftAnchorsStore.Lift
    let unit: LoadUnit
    let store: LiftAnchorsStore
    var onChange: () -> Void

    @State private var text = ""

    var body: some View {
        HStack {
            Text(lift.title)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            TextField("5 reps", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
                .accessibilityLabel("\(lift.title), weight for 5 reps in \(unit.rawValue)")
            Text(unit.rawValue)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
        .onAppear { text = Self.display(store.value(lift), unit: unit) }
        .onSubmit(save)
        .onChange(of: text) { save() }
    }

    private func save() {
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
        let value = Double(cleaned).map { unit.toKilograms($0) }
        // Showing the saved value (rounded, maybe converted) isn't a change.
        let saved = store.value(lift)
        if let value, let saved, abs(value - saved) < 0.05 { return }
        if value == nil, saved == nil { return }
        store.set(value, for: lift)
        onChange()
    }

    private static func display(_ kilograms: Double?, unit: LoadUnit) -> String {
        guard let kilograms else { return "" }
        return unit.fromKilograms(kilograms).formatted(.number.precision(.fractionLength(0...1)))
    }
}
