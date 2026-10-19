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
}
