import AppCore
import SwiftData
import SwiftUI

/// Settings › Data & privacy › Export: CSV files and a JSON copy of the data,
/// built on the phone and handed to the share sheet (which includes Save to
/// Files). Nothing is uploaded (spec B5, competitor-features-2026-11.md).
struct DataExportSettingsSection: View {
    @Environment(\.modelContext) private var context
    @Environment(\.healthClient) private var health
    @Environment(GymStore.self) private var gym
    @Environment(DailyMetricsModel.self) private var metrics
    @State private var working: DataExport.Kind?
    @State private var file: ExportedFile?
    @State private var problem: String?

    var body: some View {
        Section {
            ForEach(DataExport.Kind.allCases) { kind in
                Button {
                    Task { await export(kind) }
                } label: {
                    HStack(spacing: 12) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title).foregroundStyle(Theme.primaryText)
                                Text(kind.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                            }
                        } icon: {
                            Image(systemName: kind.systemImage).foregroundStyle(Theme.secondaryText)
                        }
                        Spacer(minLength: 0)
                        if working == kind { ProgressView() }
                    }
                }
                .disabled(working != nil)
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(Theme.recoveryModerateText)
            }
        } header: {
            // The sheet hangs on the header, one view that is always there:
            // on the Section, a Form applies it to every row.
            Text("Export")
                .sheet(item: $file, onDismiss: DataExport.removeFiles) { file in
                    ExportReadySheet(file: file)
                }
        } footer: {
            Text("Files are made on this iPhone and go only where you send them; the copy on this iPhone is deleted when you close it. Weights are in kilograms, with pounds alongside if you lift in pounds; dates are ISO 8601. The data copy holds your own data, so keep it somewhere private.")
        }
        .onAppear { DataExport.removeLeftoversOnce() }
    }

    private func export(_ kind: DataExport.Kind) async {
        working = kind
        problem = nil
        defer { working = nil }
        do {
            let url: URL
            switch kind {
            case .sets: url = try DataExport.setsFile(context: context, unit: gym.liftingUnit)
            case .cardio: url = try await DataExport.cardioFile(health: health, miles: Self.usesMiles)
            case .scores: url = try DataExport.scoresFile(metrics: metrics)
            case .backup: url = try DataExport.backupFile(context: context)
            }
            file = ExportedFile(url: url, title: kind.title)
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Miles where distances are in miles (the US and the UK), as elsewhere in the app.
    static var usesMiles: Bool {
        let system = Locale.current.measurementSystem
        return system == .us || system == .uk
    }
}

/// A file ready to share.
struct ExportedFile: Identifiable {
    let url: URL
    let title: String
    var id: URL { url }
}

/// "Ready": the file's name and size, and the share button.
struct ExportReadySheet: View {
    let file: ExportedFile
    @Environment(\.dismiss) private var dismiss

    private var size: String {
        let bytes = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Int64(bytes).formatted(.byteCount(style: .file))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.text")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text(file.url.lastPathComponent)
                        .font(.headline)
                        .foregroundStyle(Theme.primaryText)
                        .multilineTextAlignment(.center)
                    Text(size)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                ShareLink(item: file.url) {
                    Label("Share or save to Files", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle(file.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
