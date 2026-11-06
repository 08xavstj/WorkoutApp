import SwiftUI

// Shared card anatomy for the redesign (docs/research/ux-audit.md 4.5):
// one title, one verdict, one key number, one line of context, details on
// tap. Grounded in "less is more" for lay health information (Peters et al.,
// Med Care Res Rev 2007;64:169), plain verdicts next to numbers (Zikmund-Fisher
// et al., JMIR 2018;20(3):e98) and one accessibility element per card with a
// hint for the tap (HIG Accessibility; ux-audit.md P16, P17, P27).

// MARK: - Shared pieces

/// A plain-word verdict shown as a `Chip`, e.g. "Normal" or "In range".
/// Reserve warning colours for values that matter (ux-audit.md P17, P19).
struct MetricVerdict {
    var text: String
    /// Any accent; the chip text uses `Theme.textColor(for:)` (4.5:1+).
    var color: Color

    init(_ text: String, color: Color = Theme.secondaryText) {
        self.text = text
        self.color = color
    }
}

/// A number with its unit, in one of the type tokens (ux-audit.md 4.5):
/// `.hero` (44 pt rounded bold, scaled), `.tile` (30 pt rounded semibold,
/// scaled) or `.row` (`.title2` semibold rounded). Nil shows "No data".
struct MetricValueText: View {
    enum Style {
        case hero, tile, row
    }

    let value: String?
    var unit: String = ""
    var style: Style = .hero

    var body: some View {
        if let value {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                number(value)
                if !unit.isEmpty {
                    Text(unit)
                        .font(unitFont)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .foregroundStyle(Theme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        } else {
            Text("No data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private func number(_ value: String) -> some View {
        switch style {
        case .hero:
            Text(value).heroNumberFont()
        case .tile:
            Text(value).tileNumberFont()
        case .row:
            Text(value)
                .font(Theme.Typography.rowNumber)
                .fontDesign(.rounded)
                .monospacedDigit()
        }
    }

    private var unitFont: Font {
        switch style {
        case .hero: Theme.Typography.heroUnit
        case .tile, .row: .subheadline
        }
    }
}

/// The trailing chevron of a row or card that pushes a page (HIG Lists and
/// tables; ux-audit.md P6).
private struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .accessibilityHidden(true)
    }
}

/// "Title, value unit, verdict, context", the spoken form of a card or row.
private func spokenSummary(title: String, value: String?, unit: String, spokenUnit: String?, verdict: MetricVerdict?, context: String?) -> String {
    var parts = [title]
    if let value {
        let unitWords = spokenUnit ?? unit
        parts.append(unitWords.isEmpty ? value : "\(value) \(unitWords)")
    } else {
        parts.append("No data")
    }
    if let verdict { parts.append(verdict.text) }
    if let context, !context.isEmpty { parts.append(context) }
    return parts.joined(separator: ", ")
}

// MARK: - Summary card

/// The standard summary card (ux-audit.md 4.5):
///
/// ```
/// TITLE                      [chip]  ›
/// 54 bpm
/// 3 below your usual · 7-day average
/// [optional visual]
/// ```
///
/// The whole card is one tap target and one accessibility element, read as
/// "title, value unit, verdict, context" with a hint ("Shows history").
/// Pass `destination` to push a page (reading more) or `action` for anything
/// else (e.g. a medium-detent peek on Today); with neither the card is static
/// and has no chevron. Say "estimate" in `context` where the number is one;
/// explanations and citations go in the detail page's "About this number".
/// Use `tint` only on the one primary card of a tab.
///
/// ```swift
/// SummaryCard(title: "Resting heart rate", value: "54", unit: "bpm",
///             spokenUnit: "beats per minute", verdict: MetricVerdict("Normal"),
///             context: "3 below your usual", destination: RHRDetailView())
/// SummaryCard(title: "Sleep", value: "7h 43m", context: "Need 8h",
///             action: { showSleep = true }) {
///     Sparkline(values: nights, color: Theme.sleep).frame(height: 44)
/// }
/// ```
struct SummaryCard<Visual: View, Destination: View>: View {
    let title: String
    let value: String?
    let unit: String
    let spokenUnit: String?
    let verdict: MetricVerdict?
    let context: String?
    let tint: Color?
    let hint: String
    private let destination: Destination?
    private let action: (() -> Void)?
    private let visual: Visual

    /// A card that pushes `destination`, with a visual under the context line.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        context: String? = nil,
        tint: Color? = nil,
        hint: String = "Shows history",
        destination: Destination,
        @ViewBuilder visual: () -> Visual
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.spokenUnit = spokenUnit
        self.verdict = verdict
        self.context = context
        self.tint = tint
        self.hint = hint
        self.destination = destination
        self.action = nil
        self.visual = visual()
    }

    var body: some View {
        if let destination {
            NavigationLink {
                destination
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
        } else if let action {
            Button(action: action) {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        SummaryCardContent(
            title: title,
            value: value,
            unit: unit,
            verdict: verdict,
            context: context,
            tint: tint,
            showsChevron: showsChevron,
            visual: visual
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(title: title, value: value, unit: unit, spokenUnit: spokenUnit, verdict: verdict, context: context))
    }
}

extension SummaryCard where Visual == EmptyView {
    /// A card that pushes `destination`, without a visual.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        context: String? = nil,
        tint: Color? = nil,
        hint: String = "Shows history",
        destination: Destination
    ) {
        self.init(title: title, value: value, unit: unit, spokenUnit: spokenUnit, verdict: verdict,
                  context: context, tint: tint, hint: hint, destination: destination) { EmptyView() }
    }
}

extension SummaryCard where Destination == EmptyView {
    /// A card that runs `action` when tapped, with a visual under the context
    /// line. `action` is required here so a trailing closure is always the visual.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        context: String? = nil,
        tint: Color? = nil,
        hint: String = "Shows history",
        action: (() -> Void)?,
        @ViewBuilder visual: () -> Visual
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.spokenUnit = spokenUnit
        self.verdict = verdict
        self.context = context
        self.tint = tint
        self.hint = hint
        self.destination = nil
        self.action = action
        self.visual = visual()
    }
}

extension SummaryCard where Visual == EmptyView, Destination == EmptyView {
    /// A card that runs `action` when tapped (or is static when `action` is
    /// nil), without a visual.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        context: String? = nil,
        tint: Color? = nil,
        hint: String = "Shows history",
        action: (() -> Void)? = nil
    ) {
        self.init(title: title, value: value, unit: unit, spokenUnit: spokenUnit, verdict: verdict,
                  context: context, tint: tint, hint: hint, action: action) { EmptyView() }
    }
}

/// The drawn card, shared by every `SummaryCard` form.
private struct SummaryCardContent<Visual: View>: View {
    let title: String
    let value: String?
    let unit: String
    let verdict: MetricVerdict?
    let context: String?
    let tint: Color?
    let showsChevron: Bool
    let visual: Visual

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At accessibility sizes the chip moves under the number so the title
        // keeps its width (ux-audit.md 4.8).
        let chipInHeader = !dynamicTypeSize.isAccessibilitySize
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                CardLabel(text: title)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if chipInHeader, let verdict {
                    Chip(text: verdict.text, color: verdict.color)
                }
                if showsChevron {
                    DisclosureChevron()
                }
            }
            MetricValueText(value: value, unit: unit, style: .hero)
            if !chipInHeader, let verdict {
                Chip(text: verdict.text, color: verdict.color)
            }
            if let context, !context.isEmpty {
                Text(context)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            visual
        }
        .card(tint: tint)
        .contentShape(.rect(cornerRadius: Theme.cornerRadius))
    }
}

// MARK: - Metric row

/// A list row for a measure (the mockup's Biomarkers list; Health's Key
/// measures and Fitness's Progress rows, ux-audit.md 4.5): title, value with
/// unit, a verdict chip, an optional sparkline and a chevron. Put rows in one
/// `.card()` with `Divider()`s between them. One accessibility element, read
/// as "title, value unit, verdict", with a hint for the tap. The sparkline is
/// decorative (hidden from VoiceOver) and is dropped at accessibility sizes.
///
/// ```swift
/// MetricRow(title: "Resting heart rate", value: "54", unit: "bpm",
///           spokenUnit: "beats per minute", verdict: MetricVerdict("Normal"),
///           trend: rhrPoints, trendColor: Theme.heart, destination: RHRDetailView())
/// MetricRow(title: "Weight", value: "74.2", unit: "kg", action: { showWeight = true })
/// ```
struct MetricRow<Destination: View>: View {
    let title: String
    let value: String?
    let unit: String
    let spokenUnit: String?
    let verdict: MetricVerdict?
    let trend: [DatedValue]
    let trendColor: Color
    let hint: String
    private let destination: Destination?
    private let action: (() -> Void)?

    /// A row that pushes `destination`.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        trend: [DatedValue] = [],
        trendColor: Color = Theme.secondaryText,
        hint: String = "Shows history",
        destination: Destination
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.spokenUnit = spokenUnit
        self.verdict = verdict
        self.trend = trend
        self.trendColor = trendColor
        self.hint = hint
        self.destination = destination
        self.action = nil
    }

    var body: some View {
        if let destination {
            NavigationLink {
                destination
            } label: {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
            .accessibilityIdentifier("metric-\(title)") // UI tests (ScreenshotTests)
        } else if let action {
            Button(action: action) {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint)
        } else {
            content(showsChevron: false)
        }
    }

    private func content(showsChevron: Bool) -> some View {
        MetricRowContent(
            title: title,
            value: value,
            unit: unit,
            verdict: verdict,
            trend: trend,
            trendColor: trendColor,
            showsChevron: showsChevron
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary(title: title, value: value, unit: unit, spokenUnit: spokenUnit, verdict: verdict, context: nil))
    }
}

extension MetricRow where Destination == EmptyView {
    /// A row that runs `action` when tapped, or a static row when it's nil.
    init(
        title: String,
        value: String?,
        unit: String = "",
        spokenUnit: String? = nil,
        verdict: MetricVerdict? = nil,
        trend: [DatedValue] = [],
        trendColor: Color = Theme.secondaryText,
        hint: String = "Shows history",
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.unit = unit
        self.spokenUnit = spokenUnit
        self.verdict = verdict
        self.trend = trend
        self.trendColor = trendColor
        self.hint = hint
        self.destination = nil
        self.action = action
    }
}

/// The drawn row, shared by both `MetricRow` forms.
private struct MetricRowContent: View {
    let title: String
    let value: String?
    let unit: String
    let verdict: MetricVerdict?
    let trend: [DatedValue]
    let trendColor: Color
    let showsChevron: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                valueAndChip
            }
            Spacer(minLength: 8)
            if trend.count > 1, !dynamicTypeSize.isAccessibilitySize {
                Sparkline(values: trend, color: trendColor, showsArea: false)
                    .frame(width: 84, height: 36)
            }
            if showsChevron {
                DisclosureChevron()
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var valueAndChip: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                MetricValueText(value: value, unit: unit, style: .row)
                if let verdict {
                    Chip(text: verdict.text, color: verdict.color)
                }
            }
        } else {
            HStack(alignment: .center, spacing: 10) {
                MetricValueText(value: value, unit: unit, style: .row)
                if let verdict {
                    Chip(text: verdict.text, color: verdict.color)
                }
            }
        }
    }
}

// MARK: - Setup checklist

/// One card listing what's still to set up, with a single "Set up" action.
/// Replaces stacks of separate empty-state prompts (ux-audit.md 4.6 Today;
/// HIG Onboarding: postpone nonessential setup, ux-audit.md P9). Shows
/// nothing once every item is done.
///
/// ```swift
/// SetupChecklistCard(items: [
///     .init(id: "goals", title: "Set your goals", systemImage: "target", isDone: hasGoals),
///     .init(id: "gym", title: "Add your gym equipment", systemImage: "dumbbell", isDone: hasGym),
/// ]) { showSetup = true }
/// ```
struct SetupChecklistCard: View {
    struct Item: Identifiable {
        let id: String
        var title: String
        /// Optional short line under the title, e.g. why it helps.
        var detail: String?
        /// SF Symbol for the item while it's still to do.
        var systemImage: String
        var isDone: Bool

        init(id: String, title: String, detail: String? = nil, systemImage: String = "circle", isDone: Bool = false) {
            self.id = id
            self.title = title
            self.detail = detail
            self.systemImage = systemImage
            self.isDone = isDone
        }
    }

    let title: String
    let items: [Item]
    let buttonTitle: String
    let action: () -> Void

    init(title: String = "Finish setting up", items: [Item], buttonTitle: String = "Set up", action: @escaping () -> Void) {
        self.title = title
        self.items = items
        self.buttonTitle = buttonTitle
        self.action = action
    }

    private var doneCount: Int {
        items.filter(\.isDone).count
    }

    var body: some View {
        if doneCount < items.count {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CardLabel(text: title)
                    Spacer(minLength: 8)
                    Text("\(doneCount) of \(items.count) done")
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                ForEach(items) { item in
                    SetupChecklistRow(item: item)
                }
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.card)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.ink)
            }
            .card()
        }
    }
}

/// One line of the setup checklist. Neutral icons (colour rules, ux-audit.md
/// 4.5); a done item shows a check and the word "Done" for VoiceOver.
private struct SetupChecklistRow: View {
    let item: SetupChecklistCard.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(minWidth: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.Typography.body.weight(.semibold))
                    .foregroundStyle(item.isDone ? Theme.secondaryText : Theme.primaryText)
                    .strikethrough(item.isDone)
                if let detail = item.detail, !item.isDone {
                    Text(detail)
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.isDone ? "\(item.title), done" : "\(item.title), not set up")
    }
}
