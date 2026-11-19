import SwiftUI
import AppCore

/// Settings › Health data check: for each measure Apple Watch writes to Apple
/// Health, whether it reaches Tensile (newest reading, days with data, where
/// from) and, when it doesn't, why that can be and where to turn it on
/// (`HealthDataCheck`). Health never says that read access is off, so
/// "nothing" names both causes.
struct HealthDataCheckView: View {
    @Environment(\.healthClient) private var health
    @State private var items: [HealthDataCheckItem]?
    @State private var checkedAt = Date.now

    var body: some View {
        HealthDetailPage(title: "Health data check") {
            Text("What your Apple Watch writes to Apple Health, and whether it reaches Tensile. Health never tells an app that a switch is off, so \"nothing\" can mean no readings or no access.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if let items {
                summary(items)
                ForEach(HealthDataCheckItem.Group.allCases, id: \.self) { group in
                    let rows = items.filter { $0.group == group }
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            CardLabel(text: group.rawValue)
                            ForEach(rows) { item in
                                HealthDataCheckRow(item: item, now: checkedAt)
                                if item.id != rows.last?.id { Divider() }
                            }
                        }
                        .card()
                    }
                }
                Button("Ask for Apple Health access again") {
                    Task {
                        try? await health?.requestAuthorization()
                        await load()
                    }
                }
                .buttonStyle(.bordered)
                Text("iOS only shows the permission screen for measures it hasn't asked about. For the rest, use Settings › Privacy & Security › Health › Tensile.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ProgressView("Checking Apple Health…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        checkedAt = .now
        items = await health?.dataCheck(now: checkedAt) ?? []
    }

    /// "17 of 21 arriving. 2 with nothing in 30 days."
    @ViewBuilder
    private func summary(_ items: [HealthDataCheckItem]) -> some View {
        let measures = items.filter { $0.cadence != .alert }
        let arriving = measures.filter { $0.status(now: checkedAt) == .current }.count
        let missing = measures.filter { $0.status(now: checkedAt) == .none }.count
        VStack(alignment: .leading, spacing: 4) {
            Text("\(arriving) of \(measures.count) measures arriving")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
            if missing > 0 {
                Text("\(missing) with nothing in the last \(HealthDataCheck.windowDays) days")
                    .font(.subheadline)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One measure: name, status, newest reading and where it came from, and
/// what to do when it isn't arriving.
private struct HealthDataCheckRow: View {
    let item: HealthDataCheckItem
    let now: Date

    private var status: HealthDataCheck.Status { item.status(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer(minLength: 8)
                Label(statusText, systemImage: statusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            if let newest = item.newest {
                Text(newestLine(newest))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            if !item.sources.isEmpty {
                Text("From " + item.sources.formatted(.list(type: .and)))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            if let advice = HealthDataCheck.advice(status: status, cadence: item.cadence, healthName: item.healthName) {
                Text(advice)
                    .font(.footnote)
                    .foregroundStyle(item.cadence == .alert ? Theme.secondaryText : Theme.recoveryModerateText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "14.6 /min · 3:12 am today · 13 of the last 14 days".
    private func newestLine(_ newest: Date) -> String {
        var parts: [String] = []
        if let value = item.newestValue { parts.append(value) }
        parts.append(newest.formatted(.relative(presentation: .named)))
        if item.cadence != .alert, item.cadence != .occasional {
            parts.append("\(item.daysWithData) of the last 14 days")
        }
        return parts.joined(separator: " · ")
    }

    private var statusText: String {
        switch (status, item.cadence) {
        case (.current, .alert): "Notified"
        case (.current, _): "Arriving"
        case (.late, _): "Late"
        case (.none, .alert): "None"
        case (.none, _): "Nothing"
        }
    }

    private var statusIcon: String {
        switch (status, item.cadence) {
        case (.current, .alert): "bell.fill"
        case (.current, _): "checkmark.circle.fill"
        case (.late, _): "clock.fill"
        case (.none, .alert): "bell.slash"
        case (.none, _): "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch (status, item.cadence) {
        case (.current, .alert): Theme.recoveryModerateText
        case (.current, _): Theme.recoveryHighText
        case (.none, .alert): Theme.secondaryText
        case (.late, _), (.none, _): Theme.recoveryModerateText
        }
    }
}
