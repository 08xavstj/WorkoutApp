import SwiftUI
import AppCore

/// Home blood pressure: log cuff readings, run the 7-day home check, and see
/// your average against the ACC/AHA categories.
struct BloodPressureView: View {
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var readings: [BloodPressureReading] = []
    @State private var isLoading = true
    @State private var showingEntry = false

    private var check: HomeBloodPressure.WeekCheck {
        HomeBloodPressure.weekCheck(readings.map(\.asCore))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    weekCard
                    Button {
                        showingEntry = true
                    } label: {
                        Label("Add a reading", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(LinearGradient(colors: [Theme.heart, Theme.lifting], startPoint: .leading, endPoint: .trailing), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    BloodPressureGuide()
                    readingsList
                    Text("Only cuff readings are used. Watch and ring blood pressure estimates aren't accurate enough to judge blood pressure, and guidelines advise against using them for that (AHA/ACC 2025). This is a log, not a diagnosis: talk to your doctor about your readings.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Blood pressure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingEntry, onDismiss: { Task { await load() } }) {
                BloodPressureEntrySheet()
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard let health else { isLoading = false; return }
        readings = (try? await health.bloodPressureReadings(days: 90)) ?? []
        isLoading = false
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "7-day home check", color: Theme.heart)
            if let systolic = check.systolic, let diastolic = check.diastolic, let category = check.category {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(systolic.rounded()))/\(Int(diastolic.rounded()))")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                    Text("mmHg average")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Chip(text: category.rawValue, color: Self.color(for: category))
                Text(HomeBloodPressure.advice(category))
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ProgressView(value: Double(min(check.readingsUsed, HomeBloodPressure.recommendedReadings)),
                             total: Double(HomeBloodPressure.recommendedReadings))
                    .tint(Theme.heart)
                Text(check.isReliable
                     ? "\(check.readingsUsed) readings over \(check.days) days (day 1 left out). That's enough for a reliable home average."
                     : "\(check.readingsUsed) of \(HomeBloodPressure.recommendedReadings) readings so far. Keep going morning and evening; the average is more reliable with 12 or more.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text(isLoading ? "Loading…" : "No cuff readings in the last 7 days. Start a home check: two readings each morning and evening for a week.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }

    @ViewBuilder
    private var readingsList: some View {
        if !readings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardLabel(text: "Readings", color: Theme.heart)
                    .padding(.bottom, 8)
                ForEach(readings.prefix(40)) { reading in
                    let category = HomeBloodPressure.category(systolic: reading.systolic, diastolic: reading.diastolic)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reading.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                .font(.subheadline)
                                .foregroundStyle(Theme.primaryText)
                            Text([reading.arm.map { "\($0) arm" }, reading.source].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text("\(Int(reading.systolic.rounded()))/\(Int(reading.diastolic.rounded()))")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Self.color(for: category))
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.separator).frame(height: 0.5)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(category.rawValue)
                }
            }
            .card()
        }
    }

    static func color(for category: HomeBloodPressure.Category) -> Color {
        switch category {
        case .normal: Theme.recoveryHighText
        case .elevated: Theme.recoveryModerateText
        case .stage1, .stage2, .severe: Theme.recoveryLowText
        }
    }
}

/// How to measure at home so the numbers mean something.
struct BloodPressureGuide: View {
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                step("1", "No caffeine, smoking or exercise for 30 minutes, and empty your bladder.")
                step("2", "Sit with your back supported and feet flat for 5 minutes. Don't talk.")
                step("3", "Cuff on bare skin of your upper arm, at heart height, arm resting on a table.")
                step("4", "Take two readings a minute apart, and log both.")
                step("5", "Do this morning (before medication and food) and evening, for 7 days.")
                Text("Day 1 is left out because readings run high at first; the rest are averaged. Use a validated upper-arm cuff (validatebp.org lists them). Based on the 2025 AHA/ACC guideline's home monitoring advice.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        } label: {
            Label("How to measure at home", systemImage: "list.number")
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
        }
        .card()
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.heart, in: .circle)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Type in one cuff reading; it's saved to Apple Health.
struct BloodPressureEntrySheet: View {
    @Environment(\.healthClient) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var systolic: Int?
    @State private var diastolic: Int?
    @State private var pulse: Int?
    @State private var date = Date.now
    @State private var arm = "Left"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var severeAdvice: String?

    private var isValid: Bool {
        guard let systolic, let diastolic else { return false }
        return (70...260).contains(systolic) && (40...160).contains(diastolic) && systolic > diastolic
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Systolic (top)") {
                        TextField("120", value: $systolic, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Diastolic (bottom)") {
                        TextField("80", value: $diastolic, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Pulse (optional)") {
                        TextField("bpm", value: $pulse, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Reading (mmHg)")
                } footer: {
                    if let systolic, let diastolic, !isValid {
                        Text(systolic <= diastolic ? "The top number should be higher than the bottom one." : "Check the numbers: they look out of range.")
                    }
                }
                Section {
                    DatePicker("Time", selection: $date, in: ...Date.now)
                    Picker("Arm", selection: $arm) {
                        Text("Left").tag("Left")
                        Text("Right").tag("Right")
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Use the same arm each time (the one that reads higher, if you've checked both).")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.recoveryLowText)
                }
            }
            .navigationTitle("Add blood pressure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .alert("Very high reading", isPresented: Binding(get: { severeAdvice != nil }, set: { if !$0 { severeAdvice = nil; dismiss() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(severeAdvice ?? "")
            }
        }
    }

    private func save() async {
        guard let systolic, let diastolic, isValid else { return }
        guard let health else {
            errorMessage = "Apple Health isn't available on this device."
            return
        }
        isSaving = true
        defer { isSaving = false }
        await health.requestAuthorizationIfNeeded()
        do {
            try await health.saveBloodPressure(systolic: Double(systolic), diastolic: Double(diastolic),
                                               pulse: pulse.map(Double.init), date: date, arm: arm)
        } catch {
            errorMessage = "Couldn't save to Apple Health. Allow Tensile to write blood pressure in the Health app (profile → Apps → Tensile)."
            return
        }
        let category = HomeBloodPressure.category(systolic: Double(systolic), diastolic: Double(diastolic))
        if category == .severe {
            severeAdvice = HomeBloodPressure.advice(.severe)
        } else {
            dismiss()
        }
    }
}
