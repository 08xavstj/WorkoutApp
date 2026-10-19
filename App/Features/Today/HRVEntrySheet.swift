import SwiftUI
import SwiftData

struct HRVEntrySheet: View {
    let existing: HRVReading?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var source = "Garmin"
    @State private var showingCamera = false
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
                    Text(source == "Camera"
                         ? "Measured with your phone's camera just now."
                         : "Use last night's average from your watch's app (on Garmin: Garmin Connect → HRV Status). Enter it each morning for the most accurate recovery.")
                }
                Section {
                    Button {
                        focused = false
                        showingCamera = true
                    } label: {
                        Label("Measure with camera (1 minute)", systemImage: "camera.fill")
                    }
                } footer: {
                    Text("No HRV from your watch? Measure it with your fingertip over the camera. Use one method every morning: camera spot checks and overnight watch averages aren't comparable.")
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
                source = existing?.source ?? "Garmin"
                focused = true
            }
            .onChange(of: value) { oldValue, newValue in
                // Typing over a camera reading makes it a typed one.
                if focused, oldValue != nil, newValue != oldValue { source = "Garmin" }
            }
            .sheet(isPresented: $showingCamera) {
                CameraHRVView { rmssd in
                    value = rmssd
                    source = "Camera"
                }
            }
        }
    }

    private func save() {
        guard let value, value > 0 else { return }
        if let existing {
            existing.milliseconds = value
            existing.source = source
        } else {
            modelContext.insert(HRVReading(date: .now, milliseconds: value, source: source))
        }
        try? modelContext.save()
        dismiss()
    }
}
