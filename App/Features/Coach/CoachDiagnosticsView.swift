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
                // In the list, not the top-left corner, where it read like a back button.
                Section {
                    Button(copied ? "Copied" : "Copy status for a bug report", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        UIPasteboard.general.string = report
                        copied = true
                    }
                }
                Section("Model") {
                    row("Apple Intelligence", OnDeviceCoach.availabilityMessage ?? "Available")
                    row("Runs", "On this iPhone only")
                }
                Section("Last request") {
                    row("Kind", kindText)
                    row("Prompt length", diagnostics.lastPromptCharacters.map { "\($0) characters" } ?? "No prompt sent")
                    row("Finished", diagnostics.lastFinishedAt.map { $0.formatted(date: .omitted, time: .standard) } ?? "Not yet")
                    row("Retried after a refusal", diagnostics.retriedAfterRefusal ? "Yes, with training-only facts" : "No")
                }
                if let explanation = diagnostics.refusalExplanation {
                    Section("Why the model declined (its own words)") {
                        Text(explanation)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                Section("Last error") {
                    Text(diagnostics.lastError ?? "None")
                        .font(diagnostics.lastError == nil ? .body : .footnote.monospaced())
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// The last request's kind in plain words ("(no model)" read as jargon).
    private var kindText: String {
        guard let mode = diagnostics.lastMode else { return "None yet" }
        if mode.contains("(no model)") { return "Answered from your data, without the model" }
        return mode.prefix(1).uppercased() + mode.dropFirst()
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
            "Retried after refusal: \(diagnostics.retriedAfterRefusal ? "yes" : "no")",
        ]
        if let explanation = diagnostics.refusalExplanation { lines.append("Model's explanation: \(explanation)") }
        if let prompt = diagnostics.lastPrompt { lines.append("Prompt:\n\(prompt)") }
        return lines.joined(separator: "\n")
    }
}
