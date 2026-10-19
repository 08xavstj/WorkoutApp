import SwiftUI
import AppCore

/// One-minute HRV reading with a fingertip over the back camera and flash.
struct CameraHRVView: View {
    /// Called with RMSSD (ms) when the user keeps the reading.
    let onResult: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model = CameraHRVModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch model.phase {
                    case .idle:
                        instructions
                        startButton("Start")
                    case .waitingForFinger, .measuring:
                        live
                    case .analysing:
                        ProgressView("Working out your HRV…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    case .done(let result):
                        resultCard(result)
                    case .failed(let message):
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.primaryText)
                            .card(tint: Theme.recoveryModerate)
                        startButton("Try again")
                    }
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(Theme.background)
            .navigationTitle("Measure HRV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear { model.cancel() }
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardLabel(text: "How it works", color: Theme.recoveryHigh)
            step("hand.point.up.left.fill", "Rest a fingertip lightly over the back camera and the flash. Don't press hard.")
            step("figure.seated.side.left", "Sit or lie still and breathe normally for one minute. Rest your hand on something.")
            step("sunrise.fill", "Measure at the same time each morning, before coffee or exercise, in the same position.")
            step("arrow.triangle.2.circlepath", "Stick to one method. Camera readings are a 1-minute spot check, while watches average HRV overnight, so the numbers aren't comparable.")
            Text("The camera sees tiny colour changes as blood pulses through your finger and times each beat. In a study, 1-minute phone-camera readings closely matched ECG (Plews et al., IJSPP 2017).")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func step(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(Theme.recoveryHighText)
        }
    }

    private func startButton(_ title: String) -> some View {
        Button {
            Task { await model.start() }
        } label: {
            Label(title, systemImage: "camera.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient(colors: [Theme.recoveryHighText, Theme.oxygen], startPoint: .leading, endPoint: .trailing), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.fingerOn ? Theme.recoveryHigh : Theme.recoveryModerate)
                    .frame(width: 10, height: 10)
                Text(model.phase == .waitingForFinger
                     ? (model.fingerOn ? "Finger found. Hold still…" : "Cover the camera and flash with your fingertip")
                     : (model.fingerOn ? "Measuring. Keep still and breathe normally." : "Finger moved. Cover the lens again."))
                    .font(.headline)
                    .foregroundStyle(Theme.primaryText)
            }
            .accessibilityElement(children: .combine)
            PulseWaveform(values: model.waveform)
                .stroke(Theme.heart, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(height: 120)
                .padding(.vertical, 8)
                .background(Theme.card, in: .rect(cornerRadius: 16))
                .accessibilityHidden(true)
            ProgressView(value: model.progress)
                .tint(Theme.recoveryHigh)
            Text(model.phase == .measuring
                 ? "\(Int((CameraHRVModel.duration * (1 - model.progress)).rounded())) s left"
                 : "The minute starts once your finger is steady.")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private func resultCard(_ result: PPGAnalyzer.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Your reading", color: Theme.recoveryHigh)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(result.rmssd.rounded()))")
                    .font(.largeTitle.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.primaryText)
                Text("ms HRV (RMSSD)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("Heart rate \(Int(result.meanHeartRate.rounded())) bpm · \(result.cleanIntervals) clean beats · quality \(result.quality)%")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            if result.quality < 70 {
                Text("Quite a few beats were unclear. If this looks off, measure again with your hand resting still.")
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
            Button {
                onResult(result.rmssd.rounded())
                dismiss()
            } label: {
                Text("Use this reading")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Theme.recoveryHighText, in: .capsule)
            }
            .buttonStyle(.plain)
            Button("Measure again") { Task { await model.start() } }
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .card(tint: Theme.recoveryHigh)
    }
}

/// The live pulse trace (values -1...1, oldest first).
nonisolated struct PulseWaveform: Shape {
    var values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
        let step = rect.width / CGFloat(values.count - 1)
        for (index, value) in values.enumerated() {
            let point = CGPoint(x: rect.minX + CGFloat(index) * step, y: rect.midY - CGFloat(value) * rect.height * 0.42)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
