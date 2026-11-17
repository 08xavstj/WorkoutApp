import SwiftUI
import AppCore

/// "Change one or two accessory lifts?" in the block report's Next block
/// card (`BlockApplyCard`): the planner's alternatives for this gym, none
/// chosen at first, at most two (`BlockVariety`). Main lifts stay; the old
/// lift's history stays.
struct BlockVarietyPicker: View {
    let options: [BlockVariety.Option]
    @Binding var chosen: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Change one or two accessory lifts?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primaryText)
            ForEach(options) { option in
                Toggle(isOn: binding(for: option.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.toName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primaryText)
                        Text("in place of \(option.fromName)")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .tint(Theme.lifting)
                .disabled(!chosen.contains(option.id) && chosen.count >= BlockVariety.maximumChanges)
                .accessibilityIdentifier("blockReport.variety.\(option.fromID)")
            }
            // Baz-Valle 2019; Sylvester 2016; Kassiano 2022 (all as read for healthy-living-2026-11.md).
            Text("Your main lifts stay. Swapping a few accessories gave the same gains and more enjoyment in one small trial of trained men (Baz-Valle 2019); random changes every session may slow progress (Kassiano 2022). The old lift's history is kept for when it comes back.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { chosen.contains(id) },
            set: { isOn in
                var updated = chosen
                if isOn {
                    guard updated.count < BlockVariety.maximumChanges else { return }
                    updated.insert(id)
                } else {
                    updated.remove(id)
                }
                chosen = updated
            }
        )
    }
}
