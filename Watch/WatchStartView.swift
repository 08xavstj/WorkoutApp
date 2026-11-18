import SwiftUI

/// Today's session from the phone, if one is running, else an empty workout;
/// and Cardio, which opens the short activity list (`WatchCardioStartView`).
struct WatchStartView: View {
    @Environment(WatchWorkoutModel.self) private var model
    @Environment(WatchCardioModel.self) private var cardio
    @State private var showingCardio = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let session = model.snapshot, !session.isFinished {
                    Text(session.name)
                        .font(.headline)
                    Text("\(session.exercises.count) exercises · \(session.totalSets) sets")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.start(sessionID: session.id) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.lifting)
                    .buttonStyle(.borderedProminent)
                    // Double tap starts it (Series 9 and later); the cardio list has its own while it is open.
                    .handGestureShortcut(.primaryAction, isEnabled: !showingCardio)
                    .disabled(model.phase == .starting || cardio.phase == .starting)
                } else {
                    Text("No workout on your iPhone")
                        .font(.headline)
                    Text("Start one there, or record heart rate and calories from here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.start(sessionID: nil) }
                    } label: {
                        Label("Start empty", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(WatchTheme.strain)
                    .buttonStyle(.borderedProminent)
                    .handGestureShortcut(.primaryAction, isEnabled: !showingCardio)
                    .disabled(model.phase == .starting || cardio.phase == .starting)
                }
                // A run, a ride, a row: recorded with live heart-rate zones.
                Button {
                    showingCardio = true
                } label: {
                    Label("Cardio", systemImage: "figure.run")
                        .frame(maxWidth: .infinity)
                }
                .tint(WatchTheme.recovery)
                .disabled(model.phase == .starting || cardio.phase == .starting)
                .accessibilityIdentifier("watch-start-cardio")
                if model.phase == .starting || cardio.phase == .starting {
                    Text("Starting…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let problem = model.problem ?? cardio.problem {
                    Text(problem)
                        .font(.caption2)
                        .foregroundStyle(WatchTheme.heart)
                }
                // When the complications last got scores from the iPhone, so a
                // face showing "--" says why (`WatchFaceStore`, sent by `WatchSync`).
                Text(phoneDataLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("watch-phone-data")
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Tensile")
        .sheet(isPresented: $showingCardio) {
            WatchCardioStartView()
        }
        // "Start cardio in Tensile" (`StartCardioIntent`) opens the list.
        .onChange(of: cardio.pickerRequested, initial: true) {
            guard cardio.pickerRequested else { return }
            cardio.pickerRequested = false
            showingCardio = true
        }
    }

    private var phoneDataLine: String {
        guard let updated = WatchFaceStore.load()?.updated else {
            return "No scores from your iPhone yet. Open Tensile on your iPhone."
        }
        return "Scores from your iPhone: " + updated.formatted(date: Calendar.current.isDateInToday(updated) ? .omitted : .abbreviated, time: .shortened)
    }
}
