import SwiftUI

/// The studies behind a sheet's plain-words caption, folded away under a
/// small "Evidence" row so the sheet reads as one short sentence per idea
/// (used by the Sleep and Recovery detail sheets).
struct EvidenceDisclosure: View {
    let points: [String]
    /// The row's label, "Evidence" unless the points are about something else
    /// (e.g. "About this number").
    var title = "Evidence"
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(points, id: \.self) { point in
                    Text(point)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Label(title, systemImage: "info.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .tint(Theme.secondaryText)
    }
}
