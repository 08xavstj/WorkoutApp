import SwiftUI
import WidgetKit

@main
struct WorkoutWidgetBundle: WidgetBundle {
    var body: some Widget {
        HRVWidget()
        MedsLiveActivityWidget()
    }
}

/// Colors for the widget (the app's Theme isn't part of this target).
enum WidgetPalette {
    static let ink = Color(red: 0.07, green: 0.09, blue: 0.15)
    static let secondary = Color(red: 0.42, green: 0.45, blue: 0.50)
    static let green = Color(red: 0.13, green: 0.76, blue: 0.42)
    static let lime = Color(red: 0.79, green: 0.93, blue: 0.30)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let red = Color(red: 1.0, green: 0.23, blue: 0.36)
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let pink = Color(red: 0.94, green: 0.27, blue: 0.48)
    static let indigo = Color(red: 0.36, green: 0.36, blue: 0.94)
    static let peach = Color(red: 1.0, green: 0.83, blue: 0.69)
    static let sky = Color(red: 0.73, green: 0.87, blue: 1.0)

    static func recovery(_ score: Int?) -> Color {
        guard let score else { return secondary }
        return score < 34 ? red : (score < 67 ? amber : green)
    }
}
