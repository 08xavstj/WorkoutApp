import SwiftUI
import AppCore

/// Edit the equipment and weights the trainer is allowed to use.
struct MyGymView: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GymProfile.commercialPounds
    @State private var newDumbbell: Double?
    @State private var newKettlebell: Double?
    @State private var rangeFrom: Double = 5
    @State private var rangeTo: Double = 50
    @State private var rangeStep: Double = 5
    @State private var pendingUnit: LoadUnit?

    private let toggleable = EquipmentKind.allCases.filter { $0 != .bodyweight }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                    Picker("Plates and stacks are in", selection: Binding(
                        get: { draft.unit },
                        set: { newUnit in if newUnit != draft.unit { pendingUnit = newUnit } }
                    )) {
                        Text("Pounds (lb)").tag(LoadUnit.lb)
                        Text("Kilograms (kg)").tag(LoadUnit.kg)
                    }
                    Menu {
                        Button("Commercial gym (lb)") { apply(.commercialPounds) }
                        Button("Commercial gym (kg)") { apply(.commercialKilograms) }
                        Button("Home gym: dumbbells only") { apply(.homeDumbbells) }
                    } label: {
                        Label("Start from a preset", systemImage: "square.on.square")
                    }
                } footer: {
                    Text("The trainer only plans exercises you have equipment for, and rounds every weight to one you can actually load here.")
                }

                Section("Equipment") {
                    ForEach(toggleable) { kind in
                        Toggle(kind.label, isOn: Binding(
                            get: { draft.equipment.contains(kind) },
                            set: { isOn in
                                if isOn { draft.equipment.insert(kind) } else { draft.equipment.remove(kind) }
                            }
                        ))
                    }
                }

                if draft.has(.barbell) || draft.has(.ezBar) || draft.has(.smithMachine) {
                    Section {
                        if draft.has(.barbell) {
                            weightField("Barbell", value: $draft.barbellWeight)
                        }
                        if draft.has(.ezBar) {
                            weightField("EZ bar", value: $draft.ezBarWeight)
                        }
                        if draft.has(.smithMachine) {
                            weightField("Smith bar (counted weight)", value: $draft.smithBarWeight)
                        }
                    } header: {
                        Text("Bars")
                    }

                    Section {
                        ForEach(Array(draft.plates.indices), id: \.self) { index in
                            HStack {
                                TextField("Weight", value: $draft.plates[index].weight, format: .number)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 70)
                                Text(draft.unit.rawValue).foregroundStyle(Theme.secondaryText)
                                Spacer()
                                Stepper("\(draft.plates[index].pairs) pairs", value: $draft.plates[index].pairs, in: 0...20)
                                    .fixedSize()
                            }
                        }
                        .onDelete { offsets in draft.plates.remove(atOffsets: offsets) }
                        Button {
                            draft.plates.append(PlateCount(weight: draft.unit == .lb ? 1.25 : 0.5, pairs: 1))
                        } label: {
                            Label("Add plate size", systemImage: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text("Plates (pairs)")
                    } footer: {
                        Text("Add microplates (like 1.25 lb or 0.5 kg) if your gym has them; the trainer will use smaller jumps.")
                    }
                }

                if draft.has(.dumbbell) {
                    Section {
                        weightChips(draft.dumbbells) { weight in
                            draft.dumbbells.removeAll { $0 == weight }
                        }
                        HStack {
                            TextField("Add a weight", value: $newDumbbell, format: .number)
                                .keyboardType(.decimalPad)
                            Button("Add") {
                                if let value = newDumbbell, value > 0, !draft.dumbbells.contains(value) {
                                    draft.dumbbells.append(value)
                                    draft.dumbbells.sort()
                                }
                                newDumbbell = nil
                            }
                            .buttonStyle(.borderless)
                        }
                        HStack(alignment: .bottom) {
                            labeledNumber("From", $rangeFrom)
                            labeledNumber("To", $rangeTo)
                            labeledNumber("Step", $rangeStep)
                            Button("Add range") {
                                guard rangeStep > 0, rangeTo >= rangeFrom else { return }
                                // Adds to what's there (rounded so float steps don't make near-duplicates).
                                let range = stride(from: rangeFrom, through: rangeTo + 0.001, by: rangeStep).map { ($0 * 100).rounded() / 100 }
                                draft.dumbbells = Array(Set(draft.dumbbells + range)).sorted()
                            }
                            .buttonStyle(.borderless)
                        }
                    } header: {
                        Text("Dumbbells (\(draft.dumbbells.count) weights)")
                    } footer: {
                        Text("Weight per dumbbell. Use Add range for a full rack, or add odd sizes one at a time. Touch and hold a weight to remove it.")
                    }
                }

                if draft.has(.kettlebell) {
                    Section("Kettlebells") {
                        weightChips(draft.kettlebells) { weight in
                            draft.kettlebells.removeAll { $0 == weight }
                        }
                        HStack {
                            TextField("Add a kettlebell", value: $newKettlebell, format: .number)
                                .keyboardType(.decimalPad)
                            Button("Add") {
                                if let value = newKettlebell, value > 0, !draft.kettlebells.contains(value) {
                                    draft.kettlebells.append(value)
                                    draft.kettlebells.sort()
                                }
                                newKettlebell = nil
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if draft.has(.cable) {
                    stackSection("Cable stack", stack: $draft.cableStack)
                }
                if draft.has(.machine) {
                    stackSection("Machine stacks", stack: $draft.machineStack)
                }

                Section("What the trainer will use") {
                    Text(WorkoutPlanner(gym: draft).gymSummary())
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    if draft.has(.barbell), let jump = draft.smallestJump(from: draft.barbellWeight + 90, on: .barbell) {
                        LabeledContent("Smallest barbell jump", value: "\(jump.formatted()) \(draft.unit.rawValue)")
                    }
                }
            }
            .navigationTitle("My Gym")
            .confirmationDialog(
                "Switch to \(pendingUnit == .kg ? "kilograms" : "pounds")?",
                isPresented: Binding(get: { pendingUnit != nil }, set: { if !$0 { pendingUnit = nil } }),
                titleVisibility: .visible
            ) {
                if let unit = pendingUnit {
                    Button("Use standard \(unit.rawValue) plates and dumbbells") { switchUnit(to: unit, standard: true) }
                    Button("Convert my current weights") { switchUnit(to: unit, standard: false) }
                }
                Button("Cancel", role: .cancel) { pendingUnit = nil }
            } message: {
                Text("Plates and dumbbells come in different sizes in kg and lb.")
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        draft.plates.removeAll { $0.weight <= 0 }
                        gym.save(draft)
                        dismiss()
                    }
                }
            }
            .onAppear { draft = gym.profile }
        }
    }

    /// Switches unit. Plates and dumbbells come in different sizes in kg and lb,
    /// so either load the standard set for the new unit or convert the numbers.
    private func switchUnit(to unit: LoadUnit, standard: Bool) {
        if standard {
            let preset: GymProfile = unit == .kg ? .commercialKilograms : .commercialPounds
            draft.barbellWeight = preset.barbellWeight
            draft.ezBarWeight = preset.ezBarWeight
            draft.smithBarWeight = preset.smithBarWeight
            draft.plates = preset.plates
            draft.dumbbells = preset.dumbbells
            draft.kettlebells = preset.kettlebells
            draft.cableStack = preset.cableStack
            draft.machineStack = preset.machineStack
        } else {
            let from = draft.unit
            func convert(_ value: Double) -> Double {
                (unit.fromKilograms(from.toKilograms(value)) * 4).rounded() / 4
            }
            draft.barbellWeight = convert(draft.barbellWeight)
            draft.ezBarWeight = convert(draft.ezBarWeight)
            draft.smithBarWeight = convert(draft.smithBarWeight)
            draft.plates = draft.plates.map { PlateCount(weight: convert($0.weight), pairs: $0.pairs) }
            draft.dumbbells = draft.dumbbells.map(convert)
            draft.kettlebells = draft.kettlebells.map(convert)
            draft.cableStack.start = convert(draft.cableStack.start)
            draft.cableStack.step = convert(draft.cableStack.step)
            draft.cableStack.max = convert(draft.cableStack.max)
            draft.machineStack.start = convert(draft.machineStack.start)
            draft.machineStack.step = convert(draft.machineStack.step)
            draft.machineStack.max = convert(draft.machineStack.max)
        }
        draft.unit = unit
    }

    private func apply(_ preset: GymProfile) {
        let name = draft.name
        draft = preset
        if !name.isEmpty { draft.name = name }
    }

    private func weightField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: value, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(draft.unit.rawValue).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func labeledNumber(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.secondaryText)
            TextField(title, value: value, format: .number).keyboardType(.decimalPad)
        }
    }

    private func stackSection(_ title: String, stack: Binding<WeightStack>) -> some View {
        Section {
            weightField("Lightest", value: stack.start)
            weightField("Step", value: stack.step)
            weightField("Heaviest", value: stack.max)
        } header: {
            Text(title)
        } footer: {
            Text("Many stacks go up in 5s or 10s; some have add-on weights. Set the smallest step you can make.")
        }
    }

    private func weightChips(_ weights: [Double], remove: @escaping (Double) -> Void) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(weights, id: \.self) { weight in
                    // Touch and hold to remove, so scrolling can't delete a weight by accident.
                    Text(weight.formatted())
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.cardRaised, in: .capsule)
                        .contextMenu {
                            Button("Remove \(weight.formatted())", systemImage: "trash", role: .destructive) { remove(weight) }
                        }
                        .accessibilityAction(named: "Remove") { remove(weight) }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
