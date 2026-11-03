import Testing
@testable import AppCore

struct LabMarkersTests {
    @Test(arguments: [
        ("LDL Cholesterol Calc", "ldl"),
        ("HDL-C", "hdl"),
        ("Cholesterol, Total", "totalCholesterol"),
        ("Hemoglobin A1c", "hba1c"),
        ("Glucose, Fasting", "glucose"),
        ("25-Hydroxyvitamin D", "vitaminD"),
        ("Ferritin", "ferritin"),
        ("TSH", "tsh"),
        ("Testosterone, Total", "testosterone"),
        ("hs-CRP", "crp"),
        ("Lp(a)", "lpa"),
        ("Lipoprotein (a)", "lpa"),
        ("Folate, Serum", "folate"),
        ("Magnesium", "magnesium"),
        ("Uric Acid", "uricAcid"),
        ("Apolipoprotein B", "apoB"),
    ])
    func matchesPrintedNames(name: String, id: String) {
        #expect(LabMarkers.match(name)?.id == id)
    }

    @Test func doesNotMatchOtherTests() {
        #expect(LabMarkers.match("Non-HDL Cholesterol") == nil)
        #expect(LabMarkers.match("Cholesterol/HDL Ratio") == nil)
        #expect(LabMarkers.match("Sodium") == nil)
    }

    @Test func rangesBySexAndStatus() throws {
        let ferritin = try #require(LabMarkers.marker(id: "ferritin")?.units.first)
        #expect(ferritin.range(for: .female).low == 11)
        #expect(ferritin.range(for: .male).low == 24)
        let hdl = try #require(LabMarkers.marker(id: "hdl")?.units.first)
        #expect(hdl.range(for: .female).low == 50)
        #expect(hdl.range(for: .female).high == nil)
        #expect(LabMarkers.status(value: 45, low: 50, high: nil) == .low)
        #expect(LabMarkers.status(value: 120, low: nil, high: 100) == .high)
        #expect(LabMarkers.status(value: 80, low: 70, high: 99) == .inRange)
        #expect(LabMarkers.status(value: 80, low: nil, high: nil) == nil)
    }

    @Test func ferritinHasAnAthleteFloorInsideTheLabRange() {
        // Sim et al. 2019: under 30 µg/L is low for someone who trains, both sexes, even though
        // the lab range starts at 24 (men) or 11 (women).
        #expect(LabMarkers.athleteLow(markerID: "ferritin", unit: "ng/mL") == 30)
        #expect(LabMarkers.athleteLow(markerID: "ferritin", unit: "µg/L") == 30)
        #expect(LabMarkers.status(value: 25, low: 24, high: 336) == .inRange)
        let note = LabMarkers.trainingNote(markerID: "ferritin", value: 25, unit: "ng/mL")
        #expect(note?.contains("Low for someone who trains") == true)
        #expect(note?.contains("inflammation") == true)
        #expect(note?.contains("not a diagnosis") == true)
        #expect(LabMarkers.trainingNote(markerID: "ferritin", value: 40, unit: "ng/mL") == nil)
        #expect(LabMarkers.trainingNote(markerID: "ldl", value: 10, unit: "mg/dL") == nil)
    }

    @Test func newMarkersHaveGuidelineThresholds() throws {
        // Lp(a): > 50 mg/dL or > 125 nmol/L is high (Kronenberg 2022); test once.
        let lpa = try #require(LabMarkers.marker(id: "lpa"))
        #expect(lpa.panel == "Lipids")
        #expect(lpa.units.first { $0.unit == "mg/dL" }?.range(for: .male).high == 50)
        #expect(lpa.units.first { $0.unit == "nmol/L" }?.range(for: .female).high == 125)
        #expect(lpa.retest?.contains("Once in a lifetime") == true)
        // Folate ≥ 4 ng/mL; magnesium 1.7-2.3 mg/dL; uric acid 3.7-8.0 men / 2.7-6.1 women.
        #expect(LabMarkers.marker(id: "folate")?.units.first?.range(for: .male).low == 4)
        let magnesium = try #require(LabMarkers.marker(id: "magnesium")?.units.first)
        #expect(magnesium.range(for: .female).low == 1.7)
        #expect(magnesium.range(for: .female).high == 2.3)
        let uric = try #require(LabMarkers.marker(id: "uricAcid")?.units.first)
        #expect(uric.range(for: .male).high == 8.0)
        #expect(uric.range(for: .female).high == 6.1)
        #expect(LabMarkers.marker(id: "uricAcid")?.about.contains("6.8") == true)
    }

    @Test func retestCadence() {
        // ApoB every 1-2 years and after a bulk (Johannesen 2021); others as the research round says.
        #expect(LabMarkers.marker(id: "apoB")?.retest?.contains("1-2 years") == true)
        #expect(LabMarkers.marker(id: "apoB")?.retest?.contains("bulk") == true)
        #expect(LabMarkers.marker(id: "ferritin")?.retest?.contains("Yearly") == true)
        #expect(LabMarkers.marker(id: "crp")?.retest?.contains("2 weeks") == true)
        #expect(LabMarkers.marker(id: "creatinine")?.retest == nil)
        // Nothing in the catalog reads like a diagnosis.
        #expect(LabMarkers.all.allSatisfy { !$0.about.contains("you have") })
        #expect(LabMarkers.marker(id: "hba1c")?.about.contains("repeat test") == true)
    }
}
