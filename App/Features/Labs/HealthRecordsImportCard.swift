import SwiftUI
import AppCore
import os

/// Labs › "Import from Health Records": the only place the clinical-records
/// permission sheet is asked for (`HealthKitClient+HealthRecords`). Quiet
/// until tapped; with no connected clinic it says where to connect one.
struct HealthRecordsImportCard: View {
    @Environment(LabsModel.self) private var labs
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @State private var isImporting = false
    @State private var lastImport: LabsModel.HealthRecordsImport?
    @State private var failed = false

    var body: some View {
        if let health, health.supportsHealthRecords {
            VStack(alignment: .leading, spacing: 10) {
                CardLabel(text: "Health Records", color: Theme.sleep)
                Text(labs.importedCount > 0
                     ? "\(labs.importedCount) result\(labs.importedCount == 1 ? "" : "s") here came from Health Records. Import again after a new report."
                     : "If your clinic or lab sends results to the Health app, Tensile can bring them in, read-only and on this iPhone. iOS asks first, on its own permission sheet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastImport {
                    Text(lastImport.text)
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("health-records-result")
                }
                if failed {
                    Text("Couldn't read Health Records. Try again later.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.recoveryModerateText)
                }
                Button {
                    Task { await runImport(health) }
                } label: {
                    HStack(spacing: 8) {
                        if isImporting { ProgressView() }
                        Label("Import from Health Records", systemImage: "cross.case")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isImporting)
                .accessibilityIdentifier("labs-import-health-records")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func runImport(_ health: HealthKitClient) async {
        isImporting = true
        failed = false
        defer { isImporting = false }
        do {
            try await health.requestHealthRecordsAccess()
            let records = try await health.labResultRecords()
            lastImport = labs.importHealthRecords(records, sex: settings.sex)
        } catch {
            HealthKitClient.log.error("Health Records import failed: \(error.localizedDescription, privacy: .public)")
            failed = true
        }
    }
}
