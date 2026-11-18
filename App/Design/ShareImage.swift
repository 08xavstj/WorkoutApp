import AppCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

// Shared pieces for the share images (cardio, lifting, weekly, charts):
// rendering a card to PNG, the light/dark/transparent styles, the frame and
// wordmark, and the preview with its share button. Rules from spec §6 of
// docs/research/competitor-features-2026-11.md: made only when the user taps
// Share, built on the phone, no location metadata (a rendered PNG carries
// none), and the Tensile wordmark small in a corner.

/// A rendered PNG for the share sheet (alpha kept for the transparent style).
nonisolated struct SharedPNG: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName("Tensile.png")
    }
}

/// Light or dark card, or transparent with white text to lay over your own
/// photo (spec B1/B3: "transparent stats overlay").
enum ShareCardStyle: String, CaseIterable, Identifiable {
    case light, dark, transparent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .transparent: "Overlay"
        }
    }

    /// The transparent overlay is drawn in the dark scheme: light text and lines.
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
    var isOpaque: Bool { self != .transparent }
}

/// Renders share cards to PNG at a fixed size.
enum ShareRenderer {
    /// `size` in points; the image is `ShareCards.renderScale` times larger.
    /// Dynamic Type is fixed so the card's layout is the same for everyone.
    static func png<Content: View>(_ content: Content, size: CGSize, style: ShareCardStyle) -> Data? {
        let renderer = ImageRenderer(content: content
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, style.colorScheme)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = ShareCards.renderScale
        renderer.isOpaque = style.isOpaque
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage?.pngData()
    }

    static var cardSize: CGSize { CGSize(width: ShareCards.cardPointSize.width, height: ShareCards.cardPointSize.height) }
    static var chartSize: CGSize { CGSize(width: ShareCards.chartPointSize.width, height: ShareCards.chartPointSize.height) }
}

/// The card's background and padding, with the wordmark at the bottom.
/// Card text uses fixed sizes (`.system(size:)`) on purpose: the card is a
/// fixed-size picture, not live UI, so Dynamic Type doesn't apply to it; the
/// preview and the switches around it are ordinary scaled text.
struct ShareCardFrame<Content: View>: View {
    let style: ShareCardStyle
    /// Two pastel washes for the top (`Theme.Wash`), like the tab it comes from.
    var wash: [Color] = [Theme.Wash.sky, Theme.Wash.lavender]
    /// One line at the bottom: what's an estimate, what was rounded or hidden.
    var footnote: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 8) {
                if let footnote {
                    Text(footnote)
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                TensileWordmark()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if style.isOpaque {
                ZStack(alignment: .top) {
                    Theme.background
                    LinearGradient(colors: wash.map { $0.opacity(0.9) } + [Theme.background], startPoint: .top, endPoint: .bottom)
                        .frame(height: 220)
                }
            }
        }
    }
}

/// "Tensile", small, in the corner of every image.
struct TensileWordmark: View {
    var body: some View {
        Text("Tensile")
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(Theme.primaryText.opacity(0.8))
    }
}

/// A small label-over-value stat for cards.
struct ShareStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Minutes in zones 1-5 as one bar with labels underneath.
struct ShareZoneBar: View {
    let minutes: [Double]

    var body: some View {
        if let fractions = ShareCards.zoneFractions(minutes) {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(Array(fractions.enumerated()), id: \.offset) { index, fraction in
                            if fraction > 0, index < Theme.zoneColors.count {
                                Theme.zoneColors[index]
                                    .frame(width: max(2, (geo.size.width - 8) * fraction))
                            }
                        }
                    }
                    .clipShape(.capsule)
                }
                .frame(height: 8)
                HStack(spacing: 0) {
                    ForEach(Array(minutes.prefix(5).enumerated()), id: \.offset) { index, value in
                        Text("Z\(index + 1) \(whole(value.rounded()))m")
                            .font(.system(size: 8, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// The rendered image as it will be shared, and the share button.
struct ShareImagePreview: View {
    let png: Data?
    let style: ShareCardStyle
    /// Width over height of the image.
    var aspectRatio: CGFloat = ShareCards.cardPointSize.width / ShareCards.cardPointSize.height
    var subject = "Workout"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // A transparent image is shown on a dark tile so its white text reads.
                RoundedRectangle(cornerRadius: 18)
                    .fill(style == .transparent ? Color(white: 0.25) : Theme.track)
                if let png, let image = UIImage(data: png) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 18))
                        .accessibilityLabel("Preview of the image to share")
                } else {
                    ProgressView()
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            if let png {
                ShareLink(item: SharedPNG(data: png), preview: SharePreview(subject, image: Image(systemName: "photo"))) {
                    Label("Share image", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
