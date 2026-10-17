import Foundation

/// One entry from the bundled exercise database (yuhonas/free-exercise-db, public domain).
nonisolated struct Exercise: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let force: String?
    let level: String
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String
    let images: [String]

    /// Demonstration images are loaded from the dataset's GitHub repo instead of
    /// being bundled (the full image set is ~200 MB).
    var imageURLs: [URL] {
        images.compactMap { URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/\($0)") }
    }

    var primaryMuscleLabel: String {
        primaryMuscles.first?.capitalized ?? category.capitalized
    }
}

@Observable
final class ExerciseLibrary {
    private(set) var exercises: [Exercise] = []
    private(set) var loadError: String?

    var muscles: [String] {
        Array(Set(exercises.flatMap(\.primaryMuscles))).sorted()
    }

    init() {
        load()
    }

    func exercise(id: String) -> Exercise? {
        exercises.first { $0.id == id }
    }

    func search(_ text: String, muscle: String?) -> [Exercise] {
        exercises.filter { exercise in
            let matchesMuscle = muscle.map { exercise.primaryMuscles.contains($0) } ?? true
            let matchesText = text.isEmpty || exercise.name.localizedStandardContains(text)
            return matchesMuscle && matchesText
        }
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") else {
            loadError = "exercises.json is missing from the app bundle."
            return
        }
        do {
            let data = try Data(contentsOf: url)
            exercises = try JSONDecoder().decode([Exercise].self, from: data)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            loadError = "Couldn't read the exercise library: \(error.localizedDescription)"
        }
    }
}
