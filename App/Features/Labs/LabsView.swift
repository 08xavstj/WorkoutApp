import SwiftUI
import Charts
import UniformTypeIdentifiers
import AppCore

/// Biology card: latest out-of-range results, opens the full list.
struct LabsCard: View {
    @Environment(LabsModel.self) private var labs
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack(spacing: 12) {
                IconBadge(systemName: "testtube.2", color: Theme.sleep, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lab results")
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .card(tint: Theme.sleep)
        .sheet(isPresented: $showing) { LabsView() }
    }

    private var subtitle: String {
        if labs.results.isEmpty { return "Add blood tests by hand or from a PDF to track them over time." }
        let flagged = labs.outOfRange
        if flagged.isEmpty { return "\(labs.latest.count) tests, all in range on your latest results." }
        return "\(flagged.count) outside the range: " + flagged.prefix(3).map(\.name).joined(separator: ", ")
    }
}

/// Every test you've logged, grouped by panel, with trends.
struct LabsView: View {
    @Environment(LabsModel.self) private var labs
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var showingEntry = false
    @State private var showingImporter = false
    @State private var drafts: [LabDraft] = []
    @State private var showingReview = false
    @State private var isImporting = false
    @State private var importError: String?

    private struct Panel: Identifiable {
        var name: String
        var results: [LabResult]
        var id: String { name }
    }

    private var panels: [Panel] {
        let grouped = Dictionary(grouping: labs.latest) { $0.panel ?? "Other" }
        return grouped.keys.sorted().map { name in
            Panel(name: name, results: (grouped[name] ?? []).sorted { $0.name < $1.name })
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        actionButton("Add a result", "plus") { showingEntry = true }
                        actionButton(isImporting ? "Reading…" : "Import a PDF", "doc.text.viewfinder") { showingImporter = true }
                            .disabled(isImporting)
                    }
                    if isImporting {
                        ProgressView("Reading your report…")
                            .frame(maxWidth: .infinity)
                    }
                    if let importError {
                        Label(importError, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .card(tint: Theme.recoveryModerate)
                    }
                    if labs.results.isEmpty {
                        Text("Track blood tests over time: cholesterol, HbA1c, ferritin, vitamin D, thyroid, testosterone, kidney and liver markers. Import a lab PDF and check what was read before saving, or type results in.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                            .card()
                    }
                    ForEach(panels) { panel in
                        SectionTitle(text: panel.name)
                        VStack(spacing: 0) {
                            ForEach(panel.results) { result in
                                NavigationLink {
                                    LabMarkerDetailView(key: result.groupKey)
                                } label: {
                                    LabRow(result: result, history: labs.history(for: result.groupKey))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card()
                    }
                    Text("Ranges come from your lab when the report shows them; otherwise typical adult ranges are used, and your lab's range wins. This tracks results; it doesn't diagnose. Talk to your doctor about anything outside the range. PDFs are read on the app's server and not kept there.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Lab results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEntry) { LabEntrySheet() }
            .sheet(isPresented: $showingReview) { LabImportReviewView(drafts: $drafts) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { return }
                Task { await importFile(url) }
            }
        }
    }

    private func actionButton(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient(colors: [Theme.sleep, Theme.lifting], startPoint: .leading, endPoint: .trailing), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func importFile(_ url: URL) async {
        importError = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            importError = "Couldn't open that file."
            return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            drafts = try await labs.importPDF(data, filename: url.lastPathComponent, sex: settings.sex, settings: settings)
            showingReview = true
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct LabRow: View {
    let result: LabResult
    let history: [LabResult]

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text([result.rangeText.map { "Range \($0)" }, result.date.formatted(date: .abbreviated, time: .omitted)]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(result.value.formatted(.number.precision(.fractionLength(0...2)))) \(result.unit)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.primaryText)
                if let status = result.status {
                    Text(status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LabStatusColor.color(status))
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 0.5)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint(history.count > 1 ? "\(history.count) results over time" : "")
    }
}

enum LabStatusColor {
    static func color(_ status: LabMarkers.Status) -> Color {
        switch status {
        case .inRange: Theme.recoveryHighText
        case .low, .high: Theme.recoveryModerateText
        }
    }
}

/// One test over time, against its range.
struct LabMarkerDetailView: View {
    let key: String
    @Environment(LabsModel.self) private var labs
    @State private var pendingDelete: LabResult?

    private var history: [LabResult] { labs.history(for: key) }
    private var latest: LabResult? { history.last }
    private var marker: LabMarkers.Marker? { LabMarkers.marker(id: key) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(latest.value.formatted(.number.precision(.fractionLength(0...2))))
                            .font(.largeTitle.weight(.bold))
                            .fontDesign(.rounded)
                            .foregroundStyle(Theme.primaryText)
                        Text(latest.unit)
                            .font(.title3)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if let status = latest.status {
                        Chip(text: status.rawValue + (latest.rangeText.map { " · range \($0)" } ?? ""), color: LabStatusColor.color(status))
                    }
                }
                if history.count > 1 {
                    chart.frame(height: 200).card()
                }
                if let about = marker?.about {
                    VStack(alignment: .leading, spacing: 6) {
                        CardLabel(text: "What it means", color: Theme.sleep)
                        Text(about)
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                VStack(alignment: .leading, spacing: 0) {
                    CardLabel(text: "Results", color: Theme.sleep).padding(.bottom, 8)
                    ForEach(history.reversed()) { result in
                        HStack {
                            Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("\(result.value.formatted(.number.precision(.fractionLength(0...2)))) \(result.unit)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.primaryText)
                            Button {
                                pendingDelete = result
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete result from \(result.date.formatted(date: .abbreviated, time: .omitted))")
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.separator).frame(height: 0.5)
                        }
                    }
                }
                .card()
                Text("Talk to your doctor about results outside the range; one result on its own often isn't meaningful.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(latest?.name ?? "Result")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this result?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { labs.delete(pendingDelete) }
                pendingDelete = nil
            }
        }
    }

    /// The latest result's range to shade; open-ended ranges run to the edge of the data.
    private var referenceBand: (low: Double, high: Double)? {
        guard let latest else { return nil }
        let values = history.map(\.value)
        let top: Double = max(values.max() ?? 0, latest.referenceLow ?? 0) * 1.1
        switch (latest.referenceLow, latest.referenceHigh) {
        case let (low?, high?): return (low, high)
        case let (nil, high?): return (0, high)
        case let (low?, nil): return (low, max(top, low))
        default: return nil
        }
    }

    private var chart: some View {
        Chart {
            if let band = referenceBand {
                RectangleMark(yStart: .value("Range low", band.low), yEnd: .value("Range high", band.high))
                    .foregroundStyle(Theme.recoveryHigh.opacity(0.10))
            }
            ForEach(history) { result in
                LineMark(x: .value("Date", result.date), y: .value(result.name, result.value))
                    .foregroundStyle(Theme.sleep)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                PointMark(x: .value("Date", result.date), y: .value(result.name, result.value))
                    .foregroundStyle(result.status == .inRange || result.status == nil ? Theme.sleep : Theme.recoveryModerate)
                    .symbolSize(60)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

/// Type in one result.
struct LabEntrySheet: View {
    @Environment(LabsModel.self) private var labs
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var markerID = LabMarkers.all.first?.id ?? "other"
    @State private var customName = ""
    @State private var value: Double?
    @State private var unit = ""
    @State private var low: Double?
    @State private var high: Double?
    @State private var date = Date.now
    @State private var notes = ""

    private var marker: LabMarkers.Marker? { LabMarkers.marker(id: markerID) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Test") {
                    Picker("Test", selection: $markerID) {
                        ForEach(LabMarkers.all) { marker in
                            Text(marker.name).tag(marker.id)
                        }
                        Text("Other…").tag("other")
                    }
                    if marker == nil {
                        TextField("Test name", text: $customName)
                    }
                }
                Section {
                    LabeledContent("Result") {
                        TextField("Value", value: $value, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let marker {
                        Picker("Unit", selection: $unit) {
                            ForEach(marker.units) { option in
                                Text(option.unit).tag(option.unit)
                            }
                        }
                    } else {
                        TextField("Unit (e.g. mg/dL)", text: $unit)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
                Section {
                    LabeledContent("Low") {
                        TextField("none", value: $low, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("High") {
                        TextField("none", value: $high, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Reference range")
                } footer: {
                    Text("Filled with a typical adult range. If your report prints a range, use that: your lab's range wins.")
                }
                Section("Notes") {
                    TextField("e.g. fasting, morning", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Add a result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(value == nil || (marker == nil && customName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .onAppear { applyDefaults() }
            .onChange(of: markerID) { applyDefaults() }
            .onChange(of: unit) { applyRange() }
        }
    }

    private func applyDefaults() {
        unit = marker?.units.first?.unit ?? ""
        applyRange()
    }

    private func applyRange() {
        guard let option = marker?.units.first(where: { $0.unit == unit }) else { return }
        let range = option.range(for: settings.sex)
        low = range.low
        high = range.high
    }

    private func save() {
        guard let value else { return }
        let name = marker?.name ?? customName.trimmingCharacters(in: .whitespaces)
        labs.add([LabResult(
            name: name, markerID: marker?.id ?? LabMarkers.match(name)?.id, value: value, unit: unit,
            referenceLow: low, referenceHigh: high, date: date, panel: marker?.panel, notes: notes
        )])
        dismiss()
    }
}

/// Check what was read from a PDF before saving it.
struct LabImportReviewView: View {
    @Binding var drafts: [LabDraft]
    @Environment(LabsModel.self) private var labs
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($drafts) { $draft in
                        Toggle(isOn: $draft.include) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.result.name)
                                    .font(.headline)
                                Text("\(draft.result.value.formatted(.number.precision(.fractionLength(0...2)))) \(draft.result.unit)"
                                     + (draft.result.rangeText.map { " · range \($0)" } ?? "")
                                     + " · " + draft.result.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                } footer: {
                    Text("Check each value against your report. Turn off anything that was read wrong, then save.")
                }
            }
            .navigationTitle("Check \(drafts.count) results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        labs.add(drafts.filter(\.include).map(\.result))
                        dismiss()
                    }
                    .disabled(!drafts.contains(where: \.include))
                }
            }
        }
    }
}
