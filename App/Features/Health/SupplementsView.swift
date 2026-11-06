import SwiftUI
import AppCore

/// Supplements: the ones you take (entries in your Medications list that
/// `SupplementKnowledge` recognises, so creatine and ashwagandha appear) with
/// the research summary and a dose check, then everything else to browse by
/// goal with its evidence grade. Information only; the app never says "take X".
///
/// Pushed from Health › Records and Medications (`pushed: true`).
struct SupplementsView: View {
    @Environment(MedicationsModel.self) private var meds
    @Environment(\.dismiss) private var dismiss
    /// True when pushed onto another NavigationStack.
    var pushed = false

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    YourSupplementsSection()
                    BrowseSupplementsSection()
                    Text("Grades follow the IOC consensus on supplements (2018) and the ISSN position stands: strong means several good trials agree, moderate a consistent but small or situational effect, weak a few small or industry-funded trials, none no benefit shown in people who aren't deficient. Information for your own decisions, not advice; check with your doctor if you take medicines or are pregnant.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.mint, Theme.Wash.sky, Theme.Wash.lavender])
            }
            .background(Theme.background)
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .onAppear { meds.reload() }
        }
    }
}

// MARK: - Your supplements

private struct YourSupplementsSection: View {
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        SectionTitle(text: "Your supplements")
        if meds.supplements.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing recognised yet")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("Open one below and tap Add to my list, or add it under Medications. Each one you take shows its research grade and a dose check here.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .card()
        }
        ForEach(meds.supplements) { match in
            NavigationLink {
                SupplementDetailView(entry: match.entry)
            } label: {
                YourSupplementRow(match: match)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Name, your logged dose, the best grade and the dose check in one card.
private struct YourSupplementRow: View {
    let match: MedicationsModel.SupplementMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(match.medication.name + (match.medication.dose.isEmpty ? "" : " · \(match.medication.dose)"))
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            EvidenceChip(evidence: match.entry.evidence)
            if let claim = match.entry.claims.first {
                Text(claim.summary)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
            }
            Label {
                Text("Dose check: \(match.entry.doseLine)")
                    .font(Theme.Typography.context)
                    .foregroundStyle(Theme.primaryText)
            } icon: {
                Image(systemName: "scalemass").foregroundStyle(Theme.nutrition)
            }
        }
        .card(tint: Theme.nutrition)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the research page")
    }
}

// MARK: - Browse

private struct BrowseSupplementsSection: View {
    var body: some View {
        SectionTitle(text: "Browse by goal")
        ForEach(SupplementKnowledge.Category.allCases) { category in
            BrowseCategoryCard(category: category)
        }
    }
}

private struct BrowseCategoryCard: View {
    let category: SupplementKnowledge.Category

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: category.rawValue, color: Theme.nutrition)
            VStack(spacing: 0) {
                let entries = SupplementKnowledge.entries(in: category)
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    BrowseRow(entry: entry)
                }
            }
        }
        .card()
    }
}

/// One supplement: name, what it's for and its best grade, pushing the detail page.
private struct BrowseRow: View {
    let entry: SupplementKnowledge.Entry

    var body: some View {
        NavigationLink {
            SupplementDetailView(entry: entry)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    Text(entry.claims.first?.purpose ?? "")
                        .font(Theme.Typography.context)
                        .foregroundStyle(Theme.secondaryText)
                    EvidenceChip(evidence: entry.evidence)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the research page")
    }
}

/// The evidence grade as a chip; every grade is always visible.
struct EvidenceChip: View {
    let evidence: SupplementKnowledge.Evidence

    var body: some View {
        Chip(text: evidence.label, color: color)
    }

    private var color: Color {
        switch evidence {
        case .strong: Theme.recoveryHigh
        case .moderate: Theme.oxygen
        case .weak: Theme.recoveryModerate
        case .none: Theme.secondaryText
        }
    }
}

// MARK: - Detail

/// What it does and how good the evidence is, dose and timing, cautions, how
/// it shows in your data, and the sources. "Add to my list" creates a
/// Medication entry (reminders are set there).
struct SupplementDetailView: View {
    let entry: SupplementKnowledge.Entry
    @Environment(MedicationsModel.self) private var meds

    private var logged: Medication? { meds.supplementEntry(for: entry) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let logged {
                    DoseCheckCard(entry: entry, medication: logged)
                }
                ClaimsCard(claims: entry.claims)
                DoseCard(entry: entry)
                BulletCard(title: "Cautions", items: entry.cautions, icon: "exclamationmark.triangle.fill", color: Theme.recoveryModerate)
                BulletCard(title: "In your data", items: entry.dataNotes, icon: "chart.xyaxis.line", color: Theme.oxygen)
                SourcesCard(sources: entry.sources)
                if logged == nil {
                    Button("Add to my list", systemImage: "plus") { meds.addSupplement(entry) }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.nutrition)
                        .accessibilityHint("Adds it under Medications, where you can set a dose and reminders")
                }
                Text("Information, not advice. Check with your doctor or pharmacist if you take medicines, are pregnant or have a health condition.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.name)
                .font(.title.weight(.bold))
                .foregroundStyle(Theme.primaryText)
            HStack(spacing: 8) {
                EvidenceChip(evidence: entry.evidence)
                Chip(text: entry.category.rawValue, color: Theme.nutrition)
                if logged != nil { Chip(text: "In your list", color: Theme.recoveryHigh) }
            }
        }
    }
}

/// Your logged dose next to what the trials used.
private struct DoseCheckCard: View {
    let entry: SupplementKnowledge.Entry
    let medication: Medication

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Dose check", color: Theme.nutrition)
            Text(medication.dose.isEmpty ? "No dose logged yet. Add one under Medications to compare it here." : "You logged \(medication.dose).")
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
            Text("Trials used \(entry.doseLine).")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Text(medication.times.isEmpty ? "No reminder set." : "Reminders: " + medication.times.map(timeText).joined(separator: ", "))
                .font(Theme.Typography.context)
                .foregroundStyle(Theme.secondaryText)
        }
        .card(tint: Theme.nutrition)
    }
}

/// Each purpose with its own grade; one grade would hide that ashwagandha is
/// moderate for stress and weak for strength.
private struct ClaimsCard: View {
    let claims: [SupplementKnowledge.Claim]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "What it does, and the evidence")
            ForEach(claims) { claim in
                VStack(alignment: .leading, spacing: 4) {
                    Text(claim.purpose)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    EvidenceChip(evidence: claim.evidence)
                    Text(claim.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .card()
    }
}

private struct DoseCard: View {
    let entry: SupplementKnowledge.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Dose and timing")
            labelled("Dose", entry.dose)
            labelled("Timing", entry.timing)
            labelled("What to expect", entry.expect)
        }
        .card()
    }

    private func labelled(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
        }
    }
}

private struct BulletCard: View {
    let title: String
    let items: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: title, color: color)
            ForEach(items, id: \.self) { item in
                Label {
                    Text(item).font(.subheadline).foregroundStyle(Theme.primaryText)
                } icon: {
                    Image(systemName: icon).foregroundStyle(color)
                }
            }
        }
        .card(tint: color)
    }
}

private struct SourcesCard: View {
    let sources: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardLabel(text: "Sources")
            ForEach(sources, id: \.self) { source in
                Text("• " + source)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }
}
