import SwiftUI
import UIKit
import AppCore

/// What the on-device coach did last: model availability, the last error in
/// full, and the size of the last prompt, with a Copy button so a problem
/// can be reported exactly as it happened. Opened from the Coach tab's menu.
struct CoachDiagnosticsView: View {
    let diagnostics: OnDeviceCoach.Diagnostics
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Model") {
                    row("Apple Intelligence", OnDeviceCoach.availabilityMessage ?? "Available")
                    row("Runs", "On this iPhone only")
                }
                Section("Last request") {
                    row("Kind", diagnostics.lastMode ?? "None yet")
                    row("Prompt length", diagnostics.lastPromptCharacters.map { "\($0) characters" } ?? "–")
                    row("Finished", diagnostics.lastFinishedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "–")
                }
                Section("Last error") {
                    Text(diagnostics.lastError ?? "None")
                        .font(.footnote.monospaced())
                        .foregroundStyle(diagnostics.lastError == nil ? Theme.secondaryText : Theme.recoveryLow)
                        .textSelection(.enabled)
                }
                if let prompt = diagnostics.lastPrompt {
                    Section("Last prompt") {
                        Text(prompt)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Coach status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = report
                        copied = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Theme.primaryText)
            Spacer()
            Text(value)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Plain text for a bug report.
    private var report: String {
        var lines = [
            "Tensile coach status",
            "Apple Intelligence: \(OnDeviceCoach.availabilityMessage ?? "available")",
            "Last request: \(diagnostics.lastMode ?? "none")",
            "Prompt length: \(diagnostics.lastPromptCharacters.map(String.init) ?? "-")",
            "Error: \(diagnostics.lastError ?? "none")",
        ]
        if let prompt = diagnostics.lastPrompt { lines.append("Prompt:\n\(prompt)") }
        return lines.joined(separator: "\n")
    }
}
