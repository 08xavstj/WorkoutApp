import AppCore
import SwiftUI

/// Any trend chart as a 1080 × 1080 image with its title, range and caveat
/// line (spec B9 and §6: "Any trend chart with title, range and caveat"),
/// e.g. to show a coach or doctor. Sharing progress with others raised goal
/// attainment (Harkin et al., Psychol Bull 2016).
struct ShareableChartCard<ChartContent: View>: View {
    let title: String
    let subtitle: String
    let caveat: String?
    let style: ShareCardStyle
    @ViewBuilder var chart: ChartContent

    var body: some View {
        ShareCardFrame(style: style, wash: [Theme.Wash.sky, Theme.Wash.lavender], footnote: caveat) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            chart
                .frame(maxWidth: .infinity)
                .frame(height: 220)
        }
    }
}

/// A small share button for a chart: renders `ShareableChartCard` and opens
/// the preview. The chart passed in must not depend on the environment's
/// models (it is rendered off screen); pass it its values.
struct ChartShareButton<ChartContent: View>: View {
    let title: String
    let subtitle: String
    var caveat: String?
    @ViewBuilder var chart: () -> ChartContent
    @State private var sharing = false

    var body: some View {
        Button {
            sharing = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share \(title) chart as an image")
        .sheet(isPresented: $sharing) {
            ChartShareSheet(title: title, subtitle: subtitle, caveat: caveat, chart: chart)
        }
    }
}

private struct ChartShareSheet<ChartContent: View>: View {
    let title: String
    let subtitle: String
    let caveat: String?
    let chart: () -> ChartContent

    @Environment(\.dismiss) private var dismiss
    @State private var style = ShareCardStyle.light
    @State private var image: RenderedShareImage?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Style", selection: $style) {
                        ForEach(ShareCardStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    ShareImagePreview(image: image, style: style, aspectRatio: 1, subject: title)
                        .listRowBackground(Color.clear)
                } footer: {
                    Text("Made on this iPhone; it goes only where you send it.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Share chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: style) {
                let card = ShareableChartCard(title: title, subtitle: subtitle, caveat: caveat, style: style) { chart() }
                image = ShareRenderer.image(card, size: ShareRenderer.chartSize, style: style)
            }
        }
    }
}
