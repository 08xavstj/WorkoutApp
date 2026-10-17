import SwiftUI
import SwiftData

struct HRVEntrySheet: View {
    let existing: HRVReading?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. 52", value: $value, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .font(.title2.weight(.semibold))
                } header: {
                    Text("Last night's HRV (ms)")
                } footer: {
                    Text("In Garmin Connect, open HRV Status and use last night's average. Enter it each morning for the most accurate recovery.")
                }
                if let existing {
                    Section {
                        Button("Delete today's entry", role: .destructive) {
                            modelContext.delete(existing)
                            try? modelContext.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Overnight HRV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((value ?? 0) <= 0)
                }
            }
            .onAppear {
                value = existing?.milliseconds
                focused = true
            }
        }
    }

    private func save() {
        guard let value, value > 0 else { return }
        if let existing {
            existing.milliseconds = value
        } else {
            modelContext.insert(HRVReading(date: .now, milliseconds: value))
        }
        try? modelContext.save()
        dismiss()
    }
}
