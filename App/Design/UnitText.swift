import Foundation

/// Temperatures in the unit the iPhone is set to (Settings › General ›
/// Language & Region › Temperature). Values are stored in °C; only the text
/// changes.
nonisolated enum UnitText {
    /// True when the iPhone shows temperatures in °F. Read from how the system
    /// formats a temperature, so it follows the Temperature setting, not just the region.
    static var usesFahrenheit: Bool {
        // Without `.providedUnit`, the formatter converts to the user's preferred unit.
        let formatter = MeasurementFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.unitStyle = .short
        return formatter.string(from: Measurement(value: 0, unit: UnitTemperature.celsius)).contains("F")
    }

    /// "°C" or "°F".
    static var temperatureSymbol: String { usesFahrenheit ? "°F" : "°C" }

    /// An absolute temperature in the shown unit.
    static func temperature(fromCelsius celsius: Double) -> Double {
        usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
    }

    /// A temperature difference in the shown unit (no +32 for a difference).
    static func temperatureDelta(fromCelsius delta: Double) -> Double {
        usesFahrenheit ? delta * 9 / 5 : delta
    }

    /// Air temperature, whole degrees with the unit: "19°C" or "66°F".
    static func weather(_ celsius: Double) -> String {
        "\(Int(temperature(fromCelsius: celsius).rounded()))\(temperatureSymbol)"
    }

    /// Air temperature, whole degrees, unit left off for a second figure in the same line ("Feels 17°").
    static func weatherShort(_ celsius: Double) -> String {
        "\(Int(temperature(fromCelsius: celsius).rounded()))°"
    }
}
