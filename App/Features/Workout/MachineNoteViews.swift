import SwiftUI
import AppCore

/// "Seat 4 · Pin 7" under an exercise's name, with a pencil to change it.
/// Shows nothing until the exercise has settings at this gym.
struct MachineNoteLine: View {
    let note: MachineNote?
    let onEdit: () -> Void

    var body: some View {
        if let note, let line = note.settingsLine ?? note.note {
            Button(action: onEdit) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "pencil")
                        .font(.footnote)
                        .foregroundStyle(Theme.liftingText)
                }
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Machine settings: \(line)")
            .accessibilityHint("Edit")
            if note.settingsLine != nil, let extra = note.note {
                Text(extra)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Seat, pin, handles, pad and a note for one exercise at the gym you're at.
struct MachineNoteEditor: View {
    let exerciseID: String
    let exerciseName: String
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State private var seat = ""
    @State private var pin = ""
    @State private var handles = ""
    @State private var pad = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("Seat", text: $seat, prompt: "e.g. 4")
                    field("Pin / hole", text: $pin, prompt: "e.g. 7")
                    field("Handles", text: $handles, prompt: "e.g. wide")
                    field("Pad / back", text: $pad, prompt: "e.g. 2")
                } header: {
                    Text(exerciseName)
                } footer: {
                    let name = gym.activeGym.name
                    Text("Saved for \(name) only. Leave a field empty to skip it.")
                }
                Section("Note") {
                    TextField("e.g. Use the machine by the window", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Machine settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
        }
    }

    private func load() {
        let saved = gym.machineNote(for: exerciseID)
        seat = saved?.seat ?? ""
        pin = saved?.pin ?? ""
        handles = saved?.handles ?? ""
        pad = saved?.pad ?? ""
        note = saved?.note ?? ""
    }

    private func save() {
        let edited = MachineNote(seat: seat, pin: pin, handles: handles, pad: pad, note: note)
        gym.setMachineNote(edited, for: exerciseID)
        dismiss()
    }
}
