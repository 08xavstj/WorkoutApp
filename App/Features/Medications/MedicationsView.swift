import SwiftUI
import AppCore

/// Medications: today's doses (tick them off), your list, and what each one
/// means for training and recovery.
struct MedicationsView: View {
    @Environment(MedicationsModel.self) private var meds
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Medication?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !meds.todayDoses.isEmpty {
                        SectionTitle(text: "Today")
                        TodayDosesList()
                            .card(tint: Theme.lifting)
                    }
                    if !meds.notes.isEmpty {
                        MedicationNotesCard(notes: meds.notes)
                    }
                    SectionTitle(text: "Medications & supplements")
                    if meds.creatine == nil {
                        CreatineSuggestionCard()
                    }
                    if meds.medications.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add what you take")
                                .font(.headline)
                                .foregroundStyle(Theme.primaryText)
                            Text("You'll get a reminder at each dose with a Taken button, a Lock Screen tracker for today's doses, and notes on how each medication affects heart rate, HRV, sleep and training.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .card()
                    }
                    ForEach(meds.medications) { medication in
                        NavigationLink {
                            MedicationDetailView(medication: medication)
                        } label: {
                            MedicationRow(medication: medication)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        editing = Medication(name: "", times: [8 * 60])
                    } label: {
                        Label("Add medication", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(LinearGradient(colors: [Theme.lifting, Theme.sleep], startPoint: .leading, endPoint: .trailing), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    Text("Health effects come from published research and FDA drug labels. They're for training decisions only; never change a medication without your doctor.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.rose, Theme.Wash.lavender, Theme.Wash.sky])
            }
            .background(Theme.background)
            .navigationTitle("Medications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { medication in
                MedicationEditor(medication: medication)
            }
            .onAppear { meds.reload() }
            .onChange(of: router.dosesVersion) { meds.reload() }
        }
    }
}

/// One tap to add creatine with a daily reminder.
private struct CreatineSuggestionCard: View {
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: "bolt.fill", color: Theme.strain, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Take creatine?")
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text("Get a daily 5 g reminder with a Taken button. It works best when you don't miss days.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            Button("Add") { meds.setCreatineReminder(on: true) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.strain)
        }
        .card(tint: Theme.strain)
    }
}

/// Today's doses with a tap-to-take check.
struct TodayDosesList: View {
    @Environment(MedicationsModel.self) private var meds

    var body: some View {
        VStack(spacing: 10) {
            ForEach(meds.todayDoses) { dose in
                let taken = meds.isTaken(dose)
                Button {
                    meds.toggle(dose)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: taken ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(taken ? Theme.recoveryHigh : Theme.secondaryText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(dose.name)
                                .font(.headline)
                                .strikethrough(taken)
                                .foregroundStyle(Theme.primaryText)
                            Text([dose.dose, dose.time.formatted(date: .omitted, time: .shortened)].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        if taken, let at = meds.taken[dose.id] {
                            Text("Taken \(at.formatted(date: .omitted, time: .shortened))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.recoveryHighText)
                        } else if dose.time < .now {
                            Chip(text: "Due", color: Theme.lifting)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dose.name), \(taken ? "taken" : "not taken")")
            }
        }
    }
}

struct MedicationNotesCard: View {
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardLabel(text: "Keep in mind", color: Theme.sleep)
            ForEach(notes, id: \.self) { note in
                Label {
                    Text(note).font(.subheadline).foregroundStyle(Theme.primaryText)
                } icon: {
                    Image(systemName: "pills.fill").foregroundStyle(Theme.lifting)
                }
            }
        }
        .card(tint: Theme.sleep)
    }
}

private struct MedicationRow: View {
    let medication: Medication

    var body: some View {
        let drug = MedicationKnowledge.match(medication.name)
        HStack(spacing: 12) {
            IconBadge(systemName: "pills.fill", color: medication.isActive ? Theme.lifting : Theme.secondaryText, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(medication.name + (medication.dose.isEmpty ? "" : " · \(medication.dose)"))
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
                Text(medication.times.isEmpty ? "As needed" : medication.times.map(timeText).joined(separator: ", "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                if let drug {
                    Chip(text: drug.name, color: Theme.sleep)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
        }
        .card()
    }
}

func timeText(_ minutes: Int) -> String {
    Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
}

/// Add or edit a medication.
struct MedicationEditor: View {
    @State var medication: Medication
    @Environment(MedicationsModel.self) private var meds
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Metoprolol, Vyvanse)", text: $medication.name)
                        .textInputAutocapitalization(.words)
                    TextField("Dose (e.g. 25 mg)", text: $medication.dose)
                    if let drug = MedicationKnowledge.match(medication.name) {
                        Label("Recognised: \(drug.name)", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.recoveryHighText)
                            .font(.subheadline)
                    }
                }
                Section {
                    ForEach(medication.times.indices, id: \.self) { index in
                        DatePicker("Dose \(index + 1)", selection: timeBinding(index), displayedComponents: .hourAndMinute)
                    }
                    .onDelete { medication.times.remove(atOffsets: $0) }
                    Button("Add a time", systemImage: "plus") {
                        medication.times.append(min(23 * 60, (medication.times.last ?? 8 * 60) + 4 * 60))
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("Each time sends a notification with a Taken button. Remove all times for as-needed medications.")
                }
                Section {
                    DatePicker("Started", selection: $medication.startDate, displayedComponents: .date)
                    Toggle("Currently taking", isOn: $medication.isActive)
                    TextField("Notes", text: $medication.notes, axis: .vertical)
                } footer: {
                    Text("The start date lets the app explain shifts in your heart rate and HRV baseline.")
                }
                if meds.medications.contains(where: { $0.id == medication.id }) {
                    Section {
                        Button("Delete medication", role: .destructive) {
                            meds.delete(medication)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(medication.name.isEmpty ? "Add medication" : medication.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        medication.name = medication.name.trimmingCharacters(in: .whitespaces)
                        medication.times = Array(Set(medication.times)).sorted()
                        meds.save(medication)
                        dismiss()
                    }
                    .disabled(medication.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(medication.times[index] * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                medication.times[index] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

/// What a medication does to the things the app measures, with sources and the FDA label.
struct MedicationDetailView: View {
    let medication: Medication
    @Environment(MedicationsModel.self) private var meds
    @State private var label: DrugLabel?
    @State private var labelState = "Loading the FDA label…"
    @State private var editing: Medication?

    var body: some View {
        let current = meds.medications.first { $0.id == medication.id } ?? medication
        let drug = MedicationKnowledge.match(current.name)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(current.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(Theme.primaryText)
                    Text([current.dose, current.times.isEmpty ? "As needed" : current.times.map(timeText).joined(separator: ", ")]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(Theme.secondaryText)
                    if let drug { Chip(text: drug.name, color: Theme.sleep) }
                }
                if let drug {
                    VStack(alignment: .leading, spacing: 12) {
                        CardLabel(text: "Effects on your data", color: Theme.lifting)
                        ForEach(drug.effects, id: \.text) { effect in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(effect.metric.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primaryText)
                                Text(effect.text)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    }
                    .card(tint: Theme.lifting)
                    VStack(alignment: .leading, spacing: 10) {
                        CardLabel(text: "Recommendations", color: Theme.recoveryHigh)
                        ForEach(drug.recommendations, id: \.self) { tip in
                            Label {
                                Text(tip).font(.subheadline).foregroundStyle(Theme.primaryText)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.recoveryHigh)
                            }
                        }
                    }
                    .card(tint: Theme.recoveryHigh)
                    VStack(alignment: .leading, spacing: 6) {
                        CardLabel(text: "Research")
                        ForEach(drug.sources, id: \.self) { source in
                            Text("• " + source)
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .card()
                } else {
                    Text("This medication isn't in the app's research notes yet, so no training adjustments are made. The FDA label below lists its known side effects.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .card()
                }
                VStack(alignment: .leading, spacing: 10) {
                    CardLabel(text: "FDA drug label")
                    if let label {
                        if let boxed = label.boxedWarning {
                            labelSection("Boxed warning", boxed, color: Theme.recoveryLow)
                        }
                        if let warnings = label.warnings {
                            labelSection("Warnings", warnings, color: Theme.recoveryModerate)
                        }
                        if let adverse = label.adverseReactions {
                            labelSection("Side effects", adverse, color: Theme.secondaryText)
                        }
                        Text("Source: openFDA (api.fda.gov), \(label.title).")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        Text(labelState)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .card()
                Text("Not medical advice. Don't start, stop or change a medication without your doctor or pharmacist.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Edit") { editing = current }
        }
        .sheet(item: $editing) { MedicationEditor(medication: $0) }
        .task(id: current.name) {
            do {
                label = try await DrugLabelClient.fetch(current.name)
                if label == nil { labelState = "No FDA label found for this name (supplements and non-US names often aren't listed)." }
            } catch {
                labelState = "Couldn't reach the FDA database. Check your connection."
            }
        }
    }

    /// Label text is long and clinical, so each section starts collapsed.
    private func labelSection(_ title: String, _ text: String, color: Color) -> some View {
        DisclosureGroup {
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textColor(for: color))
        }
        .tint(Theme.secondaryText)
    }
}
