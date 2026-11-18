import AppCore
import SwiftUI

/// Preview and share the lifting card, with the plain-text summary as a
/// second option. Heart rate and strain are workout numbers, on by default
/// (spec §5a: health data such as recovery, sleep and weight stays off; none
/// of it is on this card). Calories aren't on the card at all.
struct LiftingShareSheet: View {
    let data: SummaryData
    let heart: SummaryHeart?
    let unit: WeightUnit
    /// The text version (`SummaryFormat.shareText`).
    let text: String

    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle.light
    @State private var showMuscles = true
    @State private var showHeart = true
    @State private var png: Data?

    private struct Options: Equatable {
        var style: ShareCardStyle
        var showMuscles: Bool
        var showHeart: Bool
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    ShareImagePreview(png: png, style: style, subject: data.title)
                        .listRowBackground(Color.clear)
                }
                Section {
                    if !data.muscles.isEmpty {
                        Toggle("Show muscle map", isOn: $showMuscles)
                    }
                    if heart != nil {
                        Toggle("Show strain", isOn: $showHeart)
                    }
                    ShareLink(item: text) {
                        Label("Share as text instead", systemImage: "text.alignleft")
                    }
                } footer: {
                    Text("Made on this iPhone. Weights are in \(unit == .kilograms ? "kilograms" : "pounds"), as in your gym settings.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Share workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: Options(style: style, showMuscles: showMuscles, showHeart: showHeart)) {
                let card = LiftingShareCard(data: data, heart: heart, unit: unit, style: style,
                                            showMuscles: showMuscles, showHeart: showHeart)
                png = ShareRenderer.png(card, size: ShareRenderer.cardSize, style: style)
            }
        }
    }
}
