import SwiftUI
import AppCore

/// Log drinks one by one for any day: what kind, how much, how strong.
/// The total in standard drinks feeds recovery, the illness watch, the
/// alcohol patterns on Biology and the coach.
struct AlcoholLogView: View {
    @Environment(CheckInStore.self) private var store
    @State private var day: Date
    @State private var showingAdd = false

    init(day: Date = .now) {
        _day = State(initialValue: Calendar.current.startOfDay(for: day))
    }

    private var calendar: Calendar { .current }
    private var entries: [AlcoholEntry] {
        (store.evening(on: day)?.alcohol ?? []).sorted { ($0.minutes ?? 0) < ($1.minutes ?? 0) }
    }
    private var total: Double { entries.reduce(0) { $0 + $1.standardDrinks } }

    var body: some View {
        Form {
            // One day control (a Yesterday/Today switch and a date picker did the same job).
            Section {
                DatePicker("Day", selection: Binding(get: { day }, set: { day = calendar.startOfDay(for: $0) }),
                           in: ...Date.now, displayedComponents: .date)
            }

            Section {
                if entries.isEmpty {
                    Text("No drinks logged for this day.")
                        .foregroundStyle(Theme.secondaryText)
                }
                ForEach(entries) { entry in
                    AlcoholRow(entry: entry)
                }
                .onDelete { offsets in
                    let ids = offsets.map { entries[$0].id }
                    update { $0.removeAll { ids.contains($0.id) } }
                }
                Button {
                    showingAdd = true
                } label: {
                    Label("Add a drink", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
            } header: {
                Text(dayTitle)
            } footer: {
                if !entries.isEmpty {
                    Text("\(total.formatted(.number.precision(.fractionLength(1)))) standard drinks. One standard drink is 14 g of alcohol: 12 oz of 5% beer, 5 oz of 12% wine or 1.5 oz of 40% spirits (NIAAA).")
                }
            }

            Section {
                Text("Alcohol lowers overnight HRV and raises resting heart rate, more with each drink, even in fit people (Pietilä et al., JMIR Ment Health 2018), and from about two drinks it cuts dream (REM) sleep (Ebrahim et al., Alcohol Clin Exp Res 2013). Logging the night it happens lets recovery explain the next morning.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        // "Drinks", as on the Log row that opens it.
        .navigationTitle("Drinks")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAdd) {
            AddDrinkSheet { entry in update { $0.append(entry) } }
                .presentationDetents([.large])
        }
    }

    /// "Today", "Yesterday" or "Monday 3 November", so the list says which day it is.
    private var dayTitle: String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func update(_ change: (inout [AlcoholEntry]) -> Void) {
        var evening = store.evening(on: day) ?? EveningCheckIn(day: day)
        var list = evening.alcohol ?? []
        change(&list)
        evening.alcohol = list
        evening.syncDrinksFromAlcohol()
        store.save(evening)
    }
}

private struct AlcoholRow: View {
    let entry: AlcoholEntry

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: icon, color: Theme.sleep, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.label)
                    .font(.subheadline.weight(.semibold))
                Text("\(DrinkVolume.text(entry.millilitres)) · \(entry.abv.formatted(.number.precision(.fractionLength(0...1))))%\(entry.minutes.map { " · " + DrinkVolume.clock($0) } ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(entry.standardDrinks.formatted(.number.precision(.fractionLength(1))))
                    .font(.headline.monospacedDigit())
                Text("std")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch entry.kind {
        case .wine, .sparkling: "wineglass.fill"
        case .spirits, .cocktail, .sake: "takeoutbag.and.cup.and.straw.fill"
        default: "mug.fill"
        }
    }
}

/// Pick a kind, a serving (or type the amount), the strength and the time.
private struct AddDrinkSheet: View {
    let onAdd: (AlcoholEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind: AlcoholEntry.Kind = .beer
    @State private var amount: Double = DrinkVolume.display(355)
    @State private var abv: Double = AlcoholEntry.Kind.beer.typicalABV
    @State private var count = 1
    @State private var time = Date.now
    @State private var addTime = true

    private var millilitres: Double { DrinkVolume.toMillilitres(amount) }
    private var preview: AlcoholEntry { AlcoholEntry(kind: kind, millilitres: millilitres, abv: abv) }

    var body: some View {
        NavigationStack {
            Form {
                Section("What") {
                    Picker("Drink", selection: $kind) {
                        ForEach(AlcoholEntry.Kind.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: kind) { _, new in
                        abv = new.typicalABV
                        amount = DrinkVolume.display(new.servings.first?.millilitres ?? 355)
                    }
                }
                Section {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(kind.servings, id: \.name) { serving in
                                let selected = abs(millilitres - serving.millilitres) < 1
                                Text(serving.name)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 36)
                                    .foregroundStyle(selected ? .white : Theme.primaryText)
                                    .background(selected ? Theme.sleep : Theme.cardRaised, in: .capsule)
                                    .contentShape(.capsule)
                                    .onTapGesture { amount = DrinkVolume.display(serving.millilitres) }
                                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: $amount, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 90)
                        Text(DrinkVolume.unitLabel)
                            .foregroundStyle(Theme.secondaryText)
                    }
                    HStack {
                        Text("Strength")
                        Spacer()
                        TextField("ABV", value: $abv, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 70)
                        Text("% ABV")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Stepper("How many: \(count)", value: $count, in: 1...12)
                } header: {
                    Text("How much")
                } footer: {
                    Text("The strength is on the can or label. Typical \(kind.label.lowercased()) is about \(kind.typicalABV.formatted())%.")
                }
                Section {
                    Toggle("Add the time", isOn: $addTime)
                    if addTime {
                        DatePicker("Finished at", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Drinks close to bedtime affect sleep and next-morning HRV the most.")
                }
                Section {
                    LabeledContent("Standard drinks", value: (preview.standardDrinks * Double(count)).formatted(.number.precision(.fractionLength(1))))
                        .font(.headline)
                }
            }
            .navigationTitle("Add a drink")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(millilitres <= 0 || abv <= 0)
                }
            }
        }
    }

    private func add() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        var minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        // A drink after midnight belongs to the evening before.
        if minutes < 5 * 60 { minutes += 24 * 60 }
        for _ in 0..<count {
            onAdd(AlcoholEntry(kind: kind, millilitres: millilitres, abv: abv, minutes: addTime ? minutes : nil))
        }
        dismiss()
    }
}

/// Fluid ounces in the US, millilitres elsewhere.
enum DrinkVolume {
    static let millilitresPerOunce = 29.5735
    static var usesOunces: Bool { Locale.current.measurementSystem == .us }
    static var unitLabel: String { usesOunces ? "oz" : "mL" }

    static func display(_ millilitres: Double) -> Double {
        usesOunces ? (millilitres / millilitresPerOunce * 10).rounded() / 10 : millilitres.rounded()
    }

    static func toMillilitres(_ value: Double) -> Double {
        usesOunces ? value * millilitresPerOunce : value
    }

    static func text(_ millilitres: Double) -> String {
        "\(display(millilitres).formatted(.number.precision(.fractionLength(0...1)))) \(unitLabel)"
    }

    static func clock(_ minutes: Int) -> String {
        let wrapped = minutes % (24 * 60)
        let date = Calendar.current.startOfDay(for: .now).addingTimeInterval(TimeInterval(wrapped * 60))
        return date.formatted(date: .omitted, time: .shortened)
    }
}
