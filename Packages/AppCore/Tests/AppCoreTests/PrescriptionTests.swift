import Testing
@testable import AppCore

struct PrescriptionTests {
    @Test func todaysTargetOrTheRange() {
        #expect(Prescription.sets(3, repsLow: 6, repsHigh: 10, targetReps: 7, rpe: 7) == "3 × 7")
        #expect(Prescription.sets(3, repsLow: 6, repsHigh: 10, targetReps: nil, rpe: 7) == "3 × 6–10")
        #expect(Prescription.sets(2, repsLow: 8, repsHigh: 8, targetReps: nil, rpe: nil) == "2 × 8")
    }

    @Test func dumbbellsArePerHand() {
        #expect(Prescription.load(24, unit: "kg", kind: .dumbbell) == "24 kg per hand")
        #expect(Prescription.load(82.5, unit: "kg", kind: .barbell) == "82.5 kg")
        #expect(Prescription.load(60, unit: "kg", kind: nil) == "60 kg")
    }
}
