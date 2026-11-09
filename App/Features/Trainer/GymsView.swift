import SwiftUI
import AppCore

// Several gyms: your regular ones and travel gyms (a hotel, a friend's
// garage) that end on a date (`GymRegistry`). The planner uses the active
// gym's equipment.

/// Settings › Training › Gym equipment: your gyms, which one you're at, and
/// travel gyms.
struct GymsView: View {
    @Environment(GymStore.self) private var gym
    @State private var addingTravel = false
    @State private var reusing: SavedGym?
    @State private var renaming: SavedGym?
    @State private var draftName = ""
    @State private var deleting: SavedGym?
    @State private var newGymID: UUID?

    var body: some View {
        Form {
            Section {
                ForEach(gym.registry.regularGyms) { saved in
                    gymRow(saved, detail: GymSummary.equipment(saved.profile))
                }
                Button("Add a gym", systemImage: "plus.circle") { addRegular() }
            } header: {
                Text("Your gyms")
            } footer: {
                Text("Workouts use the equipment of the gym you're at. Tap a gym to train there.")
            }

            Section {
                ForEach(gym.currentTravelGyms) { saved in
                    gymRow(saved, detail: GymStore.untilText(saved.expiresAt) ?? "")
                }
                Button("Add a travel gym", systemImage: "suitcase") { addingTravel = true }
            } header: {
                Text("Travel")
            } footer: {
                Text("A travel gym ends on its date and you're back at your usual gym.")
            }

            if !gym.pastTravelGyms.isEmpty {
                Section("Past travel gyms") {
                    ForEach(gym.pastTravelGyms) { saved in
                        pastRow(saved)
                    }
                }
            }
        }
        .navigationTitle("Gym equipment")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $newGymID) { id in
            MyGymView(pushed: true, gymID: id)
        }
        .sheet(isPresented: $addingTravel) {
            AddTravelGymSheet()
        }
        .sheet(item: $reusing) { saved in
            TravelEndSheet(title: "Use \(saved.name) again") { end in
                gym.reuseTravelGym(saved.id, expiresAt: end)
            }
        }
        // `presenting:` hands the gym to the buttons even if the binding clears first.
        .alert("Rename gym", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { saved in
            TextField("Name", text: $draftName)
            Button("Save") { gym.rename(saved.id, to: draftName) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { saved in
            Button("Delete", role: .destructive) { gym.delete(saved.id) }
        } message: { _ in
            Text("Its machine settings go too. Past workouts keep the gym's name.")
        }
    }

    private var deleteTitle: String {
        let name = deleting?.name ?? "this gym"
        return "Delete \(name)?"
    }

    private func gymRow(_ saved: SavedGym, detail: String) -> some View {
        let isActive = saved.id == gym.activeGymID
        let hint: String = isActive ? "" : "Train at this gym"
        return Button {
            gym.activate(saved.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.name)
                        .foregroundStyle(Theme.primaryText)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.liftingText)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityHint(hint)
        .contextMenu { rowActions(saved) }
        .swipeActions(edge: .trailing) { rowActions(saved) }
    }

    @ViewBuilder
    private func rowActions(_ saved: SavedGym) -> some View {
        Button("Edit equipment", systemImage: "slider.horizontal.3") { newGymID = saved.id }
            .tint(Theme.lifting)
        Button("Rename", systemImage: "pencil") {
            draftName = saved.name
            renaming = saved
        }
        if gym.canDelete(saved.id) {
            Button("Delete", systemImage: "trash", role: .destructive) { deleting = saved }
        }
    }

    private func pastRow(_ saved: SavedGym) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name)
                Text(GymSummary.equipment(saved.profile))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Button("Use again") { reusing = saved }
                .buttonStyle(.borderless)
        }
        .contextMenu { rowActions(saved) }
        .swipeActions(edge: .trailing) { rowActions(saved) }
    }

    /// A new regular gym, from the standard set in your lifting unit; opens its equipment.
    private func addRegular() {
        var profile: GymProfile = gym.profile.unit == .kg ? .commercialKilograms : .commercialPounds
        let number = gym.registry.regularGyms.count + 1
        profile.name = "Gym \(number)"
        newGymID = gym.addRegularGym(name: profile.name, profile: profile)
    }
}

/// A short equipment line for a gym row: "Barbell, Dumbbells, Cable station +4".
enum GymSummary {
    static func equipment(_ profile: GymProfile) -> String {
        let kinds = EquipmentKind.allCases.filter { $0 != .bodyweight && profile.equipment.contains($0) }
        guard !kinds.isEmpty else { return "Bodyweight only" }
        let shown = kinds.prefix(3).map(\.label).joined(separator: ", ")
        return kinds.count > 3 ? "\(shown) +\(kinds.count - 3)" : shown
    }
}

// MARK: - Travel gyms

/// "Add a travel gym": a quick preset, a name and when it ends. It becomes the
/// active gym right away.
struct AddTravelGymSheet: View {
    @Environment(GymStore.self) private var gym
    @Environment(\.dismiss) private var dismiss
    @State private var preset: TravelGymPreset = .hotel
    @State private var name = TravelGymPreset.hotel.name
    @State private var end = TravelEnd.sunday
    @State private var customDate = Date.now.addingTimeInterval(3 * 86_400)
    /// Called after the gym is added (the builder rebuilds its plan).
    var onAdded: () -> Void = {}

    var body: some View {
        NavigationStack {
            Form {
                Section("What's there") {
                    ForEach(TravelGymPreset.allCases) { option in
                        presetRow(option)
                    }
                }
                Section {
                    TextField("Name", text: $name)
                } header: {
                    Text("Name")
                } footer: {
                    Text("You can fine-tune the equipment later in Settings › Gym equipment.")
                }
                TravelEndSection(end: $end, customDate: $customDate)
            }
            .navigationTitle("Travel gym")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { add() }
                }
            }
        }
    }

    private func presetRow(_ option: TravelGymPreset) -> some View {
        Button {
            // Keep a name you typed; follow the preset otherwise.
            if name.isEmpty || TravelGymPreset.allCases.contains(where: { $0.name == name }) { name = option.name }
            preset = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.systemImage)
                    .foregroundStyle(Theme.liftingText)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.name).foregroundStyle(Theme.primaryText)
                    Text(option.detail).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 8)
                if option == preset {
                    Image(systemName: "checkmark").foregroundStyle(Theme.liftingText)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(option == preset ? .isSelected : [])
    }

    private func add() {
        // In the unit you lift in, so loads match your history.
        var profile = preset.profile(unit: gym.profile.unit)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.name = trimmed.isEmpty ? preset.name : trimmed
        gym.addTravelGym(name: profile.name, profile: profile, expiresAt: end.date(custom: customDate))
        onAdded()
        dismiss()
    }
}

/// When a travel gym ends.
enum TravelEnd: Hashable, CaseIterable {
    case sunday, threeDays, week, custom

    var label: String {
        switch self {
        case .sunday: "Until Sunday"
        case .threeDays: "3 days"
        case .week: "1 week"
        case .custom: "Pick a date"
        }
    }

    /// The end of the last day (`TravelGymDates`).
    func date(custom: Date, now: Date = .now) -> Date {
        switch self {
        case .sunday: TravelGymDates.endOfSunday(after: now)
        case .threeDays: TravelGymDates.end(days: 3, from: now)
        case .week: TravelGymDates.end(days: 7, from: now)
        case .custom: TravelGymDates.endOfDay(max(custom, now))
        }
    }
}

/// "Until Sunday / 3 days / 1 week / Pick a date".
struct TravelEndSection: View {
    @Binding var end: TravelEnd
    @Binding var customDate: Date

    var body: some View {
        Section {
            Picker("Ends", selection: $end) {
                ForEach(TravelEnd.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            if end == .custom {
                DatePicker("Last day", selection: $customDate, in: Date.now..., displayedComponents: .date)
            }
        } header: {
            Text("Until")
        } footer: {
            let until = GymStore.untilText(end.date(custom: customDate)) ?? ""
            Text("Training here \(until), then back to your usual gym.")
        }
    }
}

/// A new end date for a past travel gym ("Use again").
struct TravelEndSheet: View {
    let title: String
    let onDone: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var end = TravelEnd.sunday
    @State private var customDate = Date.now.addingTimeInterval(3 * 86_400)

    var body: some View {
        NavigationStack {
            Form {
                TravelEndSection(end: $end, customDate: $customDate)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onDone(end.date(custom: customDate))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Switching

/// The gym you're training at, as a menu: your gyms, current travel gyms,
/// "Add a travel gym". `onChange` runs after a switch (rebuild the plan).
struct GymSwitcherMenu: View {
    @Environment(GymStore.self) private var gym
    @State private var addingTravel = false
    var onChange: () -> Void = {}

    var body: some View {
        Menu {
            Section("Training at") {
                ForEach(gym.registry.regularGyms + gym.currentTravelGyms) { saved in
                    Toggle(isOn: Binding(
                        get: { saved.id == gym.activeGymID },
                        set: { isOn in
                            guard isOn, saved.id != gym.activeGymID else { return }
                            gym.activate(saved.id)
                            onChange()
                        }
                    )) {
                        Text(saved.name)
                    }
                }
            }
            Button("Add a travel gym", systemImage: "suitcase") { addingTravel = true }
        } label: {
            Label(gym.activeGym.name, systemImage: gym.activeGym.isTemporary ? "suitcase" : "dumbbell")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.liftingText)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Gym: \(gym.activeGym.name)")
        .accessibilityHint("Switch gym")
        .sheet(isPresented: $addingTravel) {
            AddTravelGymSheet(onAdded: onChange)
        }
    }
}

/// "Training at: Hotel gym · until Sun" while a travel gym is active; tap for your gyms.
struct TravelGymChip: View {
    @Environment(GymStore.self) private var gym
    @State private var showingGyms = false

    var body: some View {
        if gym.activeGym.isTemporary {
            Button { showingGyms = true } label: {
                Label(text, systemImage: "suitcase")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.liftingText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.lifting.opacity(0.13), in: .capsule)
                    .frame(minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your gyms")
            .frame(maxWidth: .infinity, alignment: .leading)
            .sheet(isPresented: $showingGyms) {
                NavigationStack {
                    GymsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingGyms = false }
                            }
                        }
                }
            }
        }
    }

    private var text: String {
        let name = gym.activeGym.name
        guard let until = GymStore.untilText(gym.activeGym.expiresAt) else { return "Training at: \(name)" }
        return "Training at: \(name) · \(until)"
    }
}

/// When a travel gym has ended: you're back at your usual gym; keep the
/// travel gym for next time or delete it.
struct TravelGymEndedPrompt: ViewModifier {
    @Environment(GymStore.self) private var gym

    func body(content: Content) -> some View {
        // Captured now, so Delete still knows the gym if the alert clears it first.
        let endedID = gym.endedTravelGym?.id
        return content
            .alert(title, isPresented: Binding(
                get: { gym.endedTravelGym != nil },
                set: { if !$0 { gym.keepEndedTravelGym() } }
            )) {
                Button("Keep for next time") { gym.keepEndedTravelGym() }
                Button("Delete", role: .destructive) {
                    if let endedID { gym.delete(endedID) }
                }
            } message: {
                Text(message)
            }
    }

    private var title: String {
        let name = gym.endedTravelGym?.name ?? "Travel gym"
        return "\(name) has ended"
    }

    private var message: String {
        let home = gym.activeGym.name
        return "You're back at \(home). Keep the travel gym under Past travel gyms to use it again?"
    }
}

extension View {
    /// Asks what to do with a travel gym that just ended (`TravelGymEndedPrompt`).
    func travelGymEndedPrompt() -> some View {
        modifier(TravelGymEndedPrompt())
    }
}
