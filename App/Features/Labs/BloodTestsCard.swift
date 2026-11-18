import SwiftUI
import AppCore

/// Health › Records › Lab results, at the top: the blood tests that matter
/// most for heart and metabolic risk, when each is next due, and an optional
/// reminder (`BloodTestSchedule`; evidence-audit-2026-11.md, Gaps, item 2).
/// Blood pressure keeps its own 7-day home check in Log.
struct BloodTestsCard: View {
    @Environment(LabsModel.self) private var labs
    @Environment(UserSettings.self) private var settings
    @AppStorage(Reminders.bloodTestRemindersKey) private var remindersOn = false
    @State private var editing: BloodTestSchedule.Check?

    var body: some View {
        let schedule = labs.bloodTestSchedule(age: settings.age)
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Heart and blood sugar tests", color: Theme.sleep)
            if !settings.ageIsSet {
                Text("Add your age in Settings › Profile to see which of these are due.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(schedule.enumerated()), id: \.element.id) { index, due in
                    if index > 0 { Divider() }
                    BloodTestRow(due: due) { editing = due.check }
                }
            }
            Toggle(isOn: $remindersOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remind me when one is due")
                        .font(.subheadline)
                        .foregroundStyle(Theme.primaryText)
                    Text("One notification on the due date.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .tint(Theme.sleep)
            .accessibilityIdentifier("labs-blood-test-reminders")
            .onChange(of: remindersOn) { _, on in
                Task {
                    if on, !(await Reminders.requestPermission()) { remindersOn = false }
                    await Reminders.scheduleBloodTestReminders(schedule)
                }
            }
            Text("From guidelines for adults (ACC/AHA, the European Atherosclerosis Society, the American Diabetes Association). Not a diagnosis; your doctor may advise a different schedule.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .accessibilityIdentifier("labs-blood-tests")
        .sheet(item: $editing) { check in
            BloodTestDateSheet(check: check)
        }
        // Results or dates changed: move the reminders with them.
        .task(id: reminderKey(schedule)) {
            await Reminders.scheduleBloodTestReminders(schedule)
        }
    }

    private func reminderKey(_ schedule: [BloodTestSchedule.Due]) -> String {
        schedule.map { "\($0.check.rawValue):\($0.dueDate?.timeIntervalSinceReferenceDate ?? -1)" }.joined(separator: "|")
    }
}

/// One check: its name, when it's next due, and "Had it done?" for a test
/// whose numbers aren't in the app.
private struct BloodTestRow: View {
    let due: BloodTestSchedule.Due
    let editDate: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(due.check.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.primaryText)
                    if due.isDue {
                        Chip(text: "Due", color: Theme.recoveryModerate)
                    }
                }
                Text(due.line)
                    .font(.caption)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)
            Button("Had it done?", action: editDate)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityIdentifier("labs-blood-test-date-\(due.check.rawValue)")
        }
        .padding(.vertical, 8)
    }

    /// "Last Mar 2024 · next Mar 2029 · every 5 years"
    private var detail: String {
        var parts: [String] = []
        if let last = due.lastTested { parts.append("Last " + last.formatted(.dateTime.month(.abbreviated).year())) }
        if let next = due.dueDate, !due.isDue { parts.append("next " + next.formatted(.dateTime.month(.abbreviated).year())) }
        parts.append(due.intervalText.prefix(1).lowercased() + due.intervalText.dropFirst())
        let text = parts.joined(separator: " · ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// "I had this test on …" for a test whose results aren't typed in: it counts
/// for the due date only.
private struct BloodTestDateSheet: View {
    let check: BloodTestSchedule.Check
    @Environment(LabsModel.self) private var labs
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("If you have the numbers, add them as results instead: the schedule then uses them too, and a result outside the range brings the next test forward.")
                }
                if labs.typedTestDate(check) != nil {
                    Section {
                        Button("Remove this date", role: .destructive) {
                            labs.setTested(check.rawValue, on: nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(check.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        labs.setTested(check.rawValue, on: date)
                        dismiss()
                    }
                    .accessibilityIdentifier("labs-blood-test-date-save")
                }
            }
            .onAppear { date = labs.typedTestDate(check) ?? .now }
        }
        .presentationDetents([.medium])
    }
}
