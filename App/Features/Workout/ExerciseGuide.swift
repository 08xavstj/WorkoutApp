import SwiftUI

/// How to do an exercise: the library's photos and steps, plus a link to form
/// videos. Opened by tapping an exercise in a live workout or the builder.
struct ExerciseGuideSheet: View {
    let exerciseID: String
    let name: String
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let exercise = library.exercise(id: exerciseID) {
                    ExerciseDetailView(exercise: exercise)
                } else {
                    ExerciseGuideFallback(name: name)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Form videos are a YouTube search, not bundled or picked by the app: the
/// app has no licence to host videos, and a search always has current ones.
enum ExerciseVideos {
    static func searchURL(for name: String) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) exercise proper form")]
        return components?.url
    }
}

/// "Watch form videos" row, opening YouTube search results for the exercise.
struct FormVideoLink: View {
    let name: String

    var body: some View {
        if let url = ExerciseVideos.searchURL(for: name) {
            VStack(alignment: .leading, spacing: 8) {
                Link(destination: url) {
                    HStack {
                        Label("Watch form videos", systemImage: "play.rectangle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens YouTube search results for \(name)")
                Text("Videos come from YouTube creators and aren't checked by Tensile. Coaches with a recognised qualification are the safest bet.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
}

/// For an exercise the library doesn't have (none today, but saved workouts
/// can outlive library changes): just the video link.
private struct ExerciseGuideFallback: View {
    let name: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("There's no written guide for this exercise yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                FormVideoLink(name: name)
            }
            .padding()
            .lockedToScreenWidth()
        }
        .background(Theme.background)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
