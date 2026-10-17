import Foundation

/// The unit a gym's plates and stacks are labelled in.
public enum LoadUnit: String, Codable, Sendable, CaseIterable {
    case kg, lb

    public static let poundsPerKilogram = 2.20462

    /// Converts a value in this unit to kilograms.
    public func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value / Self.poundsPerKilogram
    }

    /// Converts kilograms to this unit.
    public func fromKilograms(_ kilograms: Double) -> Double {
        self == .kg ? kilograms : kilograms * Self.poundsPerKilogram
    }
}

public enum EquipmentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case barbell, ezBar, dumbbell, kettlebell, cable, machine, smithMachine
    case bench, squatRack, pullUpBar, dipStation, bands, bodyweight

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .barbell: "Barbell"
        case .ezBar: "EZ bar"
        case .dumbbell: "Dumbbells"
        case .kettlebell: "Kettlebells"
        case .cable: "Cable station"
        case .machine: "Machines"
        case .smithMachine: "Smith machine"
        case .bench: "Bench"
        case .squatRack: "Squat rack"
        case .pullUpBar: "Pull-up bar"
        case .dipStation: "Dip station"
        case .bands: "Bands"
        case .bodyweight: "Bodyweight"
        }
    }
}

/// A plate size and how many pairs of it the gym has.
public struct PlateCount: Codable, Sendable, Equatable, Hashable {
    public var weight: Double
    public var pairs: Int

    public init(weight: Double, pairs: Int) {
        self.weight = weight
        self.pairs = pairs
    }
}

/// A selectorized stack: start, step, max (e.g. cable 10...200 by 10).
public struct WeightStack: Codable, Sendable, Equatable {
    public var start: Double
    public var step: Double
    public var max: Double

    public init(start: Double, step: Double, max: Double) {
        self.start = start
        self.step = step
        self.max = max
    }

    public var values: [Double] {
        guard step > 0, max >= start else { return [start] }
        let count = Int(((max - start) / step).rounded(.down))
        return (0...Swift.min(count, 500)).map { start + Double($0) * step }
    }
}

/// Everything the trainer needs to know about where you lift.
/// All weights are in `unit`.
public struct GymProfile: Codable, Sendable, Equatable {
    public var name: String
    public var unit: LoadUnit
    public var equipment: Set<EquipmentKind>
    public var barbellWeight: Double
    public var ezBarWeight: Double
    public var smithBarWeight: Double
    public var plates: [PlateCount]
    public var dumbbells: [Double]
    public var kettlebells: [Double]
    public var cableStack: WeightStack
    public var machineStack: WeightStack

    public init(
        name: String,
        unit: LoadUnit,
        equipment: Set<EquipmentKind>,
        barbellWeight: Double,
        ezBarWeight: Double,
        smithBarWeight: Double,
        plates: [PlateCount],
        dumbbells: [Double],
        kettlebells: [Double],
        cableStack: WeightStack,
        machineStack: WeightStack
    ) {
        self.name = name
        self.unit = unit
        self.equipment = equipment
        self.barbellWeight = barbellWeight
        self.ezBarWeight = ezBarWeight
        self.smithBarWeight = smithBarWeight
        self.plates = plates
        self.dumbbells = dumbbells
        self.kettlebells = kettlebells
        self.cableStack = cableStack
        self.machineStack = machineStack
    }

    public func has(_ kind: EquipmentKind) -> Bool {
        kind == .bodyweight || equipment.contains(kind)
    }

    // MARK: Presets

    public static let commercialPounds = GymProfile(
        name: "Commercial gym",
        unit: .lb,
        equipment: Set(EquipmentKind.allCases),
        barbellWeight: 45,
        ezBarWeight: 25,
        smithBarWeight: 20,
        plates: [
            PlateCount(weight: 45, pairs: 4), PlateCount(weight: 35, pairs: 1), PlateCount(weight: 25, pairs: 2),
            PlateCount(weight: 10, pairs: 2), PlateCount(weight: 5, pairs: 2), PlateCount(weight: 2.5, pairs: 2)
        ],
        dumbbells: stride(from: 5.0, through: 100, by: 5).map { $0 },
        kettlebells: [18, 26, 35, 44, 53, 62, 70],
        cableStack: WeightStack(start: 10, step: 10, max: 200),
        machineStack: WeightStack(start: 10, step: 10, max: 300)
    )

    public static let commercialKilograms = GymProfile(
        name: "Commercial gym",
        unit: .kg,
        equipment: Set(EquipmentKind.allCases),
        barbellWeight: 20,
        ezBarWeight: 10,
        smithBarWeight: 10,
        plates: [
            PlateCount(weight: 25, pairs: 4), PlateCount(weight: 20, pairs: 2), PlateCount(weight: 15, pairs: 1),
            PlateCount(weight: 10, pairs: 2), PlateCount(weight: 5, pairs: 2), PlateCount(weight: 2.5, pairs: 2),
            PlateCount(weight: 1.25, pairs: 2)
        ],
        dumbbells: stride(from: 2.0, through: 50, by: 2).map { $0 },
        kettlebells: [8, 12, 16, 20, 24, 28, 32],
        cableStack: WeightStack(start: 5, step: 5, max: 100),
        machineStack: WeightStack(start: 5, step: 5, max: 150)
    )

    public static let homeDumbbells = GymProfile(
        name: "Home gym",
        unit: .lb,
        equipment: [.dumbbell, .bench, .pullUpBar, .bands],
        barbellWeight: 45,
        ezBarWeight: 25,
        smithBarWeight: 20,
        plates: [],
        dumbbells: stride(from: 5.0, through: 52.5, by: 2.5).map { $0 },
        kettlebells: [],
        cableStack: WeightStack(start: 10, step: 10, max: 200),
        machineStack: WeightStack(start: 10, step: 10, max: 300)
    )
}

// MARK: - Loading math

public struct LoadOption: Sendable, Equatable {
    public var total: Double
    /// Plates for ONE side of the bar, largest first. Empty for non-plate equipment.
    public var platesPerSide: [Double]
}

extension GymProfile {
    /// Every weight you can actually set up on this equipment, ascending.
    /// Dumbbell and kettlebell weights are per hand / per bell.
    public func achievableLoads(for kind: EquipmentKind) -> [Double] {
        switch kind {
        case .barbell: plateLoads(bar: barbellWeight)
        case .ezBar: plateLoads(bar: ezBarWeight)
        case .smithMachine: plateLoads(bar: smithBarWeight)
        case .dumbbell: dumbbells.sorted()
        case .kettlebell: kettlebells.sorted()
        case .cable: cableStack.values
        case .machine: machineStack.values
        default: []
        }
    }

    /// The heaviest achievable load at or below `target` (or the lightest one if
    /// even that is heavier than the target). Nil when the equipment has no loads.
    public func load(atMost target: Double, on kind: EquipmentKind) -> Double? {
        let loads = achievableLoads(for: kind)
        guard let first = loads.first else { return nil }
        return loads.last { $0 <= target + 0.001 } ?? first
    }

    /// The smallest achievable load heavier than `current` - the next jump in weight.
    public func nextLoad(above current: Double, on kind: EquipmentKind) -> Double? {
        achievableLoads(for: kind).first { $0 > current + 0.001 }
    }

    /// The smallest increase available from `current`.
    public func smallestJump(from current: Double, on kind: EquipmentKind) -> Double? {
        nextLoad(above: current, on: kind).map { $0 - current }
    }

    /// How to load a bar to `total`, using the plates the gym actually has.
    public func plateBreakdown(total: Double, on kind: EquipmentKind) -> [Double]? {
        let bar: Double
        switch kind {
        case .barbell: bar = barbellWeight
        case .ezBar: bar = ezBarWeight
        case .smithMachine: bar = smithBarWeight
        default: return nil
        }
        let perSide = (total - bar) / 2
        guard perSide >= -0.001 else { return nil }
        if perSide < 0.001 { return [] }
        let sizes = plates.filter { $0.pairs > 0 && $0.weight > 0 }.sorted { $0.weight > $1.weight }
        var best: [Double]?
        func search(_ index: Int, _ remaining: Int, _ chosen: [Double]) {
            if best != nil { return }
            if remaining == 0 { best = chosen; return }
            guard index < sizes.count else { return }
            let size = sizes[index]
            let unit = Int((size.weight * 100).rounded())
            let maxCount = Swift.min(size.pairs, remaining / unit)
            for count in stride(from: maxCount, through: 0, by: -1) {
                search(index + 1, remaining - count * unit, chosen + Array(repeating: size.weight, count: count))
                if best != nil { return }
            }
        }
        search(0, Int((perSide * 100).rounded()), [])
        return best
    }

    /// All bar totals reachable with the plate inventory (per-side sums × 2 + bar).
    private func plateLoads(bar: Double) -> [Double] {
        var sums: Set<Int> = [0] // hundredths, one side
        for plate in plates where plate.pairs > 0 && plate.weight > 0 {
            let unit = Int((plate.weight * 100).rounded())
            var next = sums
            for sum in sums {
                for count in 1...plate.pairs {
                    next.insert(sum + unit * count)
                }
            }
            sums = next
        }
        return sums.map { bar + 2 * Double($0) / 100 }.sorted()
    }
}
