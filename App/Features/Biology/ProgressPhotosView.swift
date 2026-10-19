import SwiftUI
import UIKit

/// Daily front and side photos, a before/after slider, a timeline and the
/// weekly Claude analysis. Photos stay inside the app.
struct ProgressPhotosView: View {
    @Environment(ProgressPhotosModel.self) private var photos
    @Environment(UserSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var capturing: ProgressPhotosModel.Pose?
    @State private var comparePose: ProgressPhotosModel.Pose = .front
    @State private var compareDay: String?
    @State private var viewing: ProgressPhotosModel.Entry?
    let runAnalysis: () async -> Void

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todayCard
                    if photos.days.count >= 2 { compareCard }
                    analysisCard(weekly: $settings.weeklyPhotoAnalysis)
                    if !photos.days.isEmpty { timeline }
                    Text("Photos are saved only inside WorkoutApp, encrypted on your iPhone, and never added to your Photos library. For the weekly analysis, the photos being compared are sent to Claude through the app's secure server for that one request and aren't stored there.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.peach, Theme.Wash.lavender, Theme.Wash.sky])
            }
            .background(Theme.background)
            .navigationTitle("Progress photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(item: $capturing) { pose in
                CameraCapture(guide: photos.latest(pose).flatMap { photos.image($0) }) { image in
                    if let image { photos.save(image, pose: pose) }
                    capturing = nil
                }
                .ignoresSafeArea()
            }
            .sheet(item: $viewing) { entry in
                PhotoViewer(entry: entry)
            }
        }
    }

    // MARK: Today

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "Today", color: Theme.lifting)
            HStack(spacing: 12) {
                ForEach(ProgressPhotosModel.Pose.allCases) { pose in
                    Button {
                        capturing = pose
                    } label: {
                        ZStack {
                            if let entry = photos.todayEntry(pose), let image = photos.thumbnail(entry) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                RoundedRectangle(cornerRadius: 18).fill(Theme.cardRaised)
                                VStack(spacing: 6) {
                                    Image(systemName: "camera.fill").font(.title2)
                                    Text(pose.title).font(.subheadline.weight(.semibold))
                                }
                                .foregroundStyle(Theme.lifting)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 18))
                        .overlay(alignment: .bottomLeading) {
                            if photos.todayEntry(pose) != nil {
                                Label("\(pose.title) · retake", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.black.opacity(0.35), in: .capsule)
                                    .padding(8)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photos.todayEntry(pose) == nil ? "Take \(pose.title.lowercased()) photo" : "Retake \(pose.title.lowercased()) photo")
                }
            }
            Text("Same spot, same light, ideally each morning before eating. The camera shows a faint outline of your last photo to line up with.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
        .card(tint: Theme.lifting)
    }

    // MARK: Compare

    private var compareCard: some View {
        let latestDay = photos.days.first
        let earlierDays = photos.days.dropFirst()
        let before = (compareDay ?? earlierDays.last).flatMap { photos.entry(day: $0, pose: comparePose) }
        let after = latestDay.flatMap { photos.entry(day: $0, pose: comparePose) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Compare", color: Theme.sleep)
                Spacer()
                Picker("Pose", selection: $comparePose) {
                    ForEach(ProgressPhotosModel.Pose.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            if let before, let after, let beforeImage = photos.image(before), let afterImage = photos.image(after) {
                CompareSlider(before: beforeImage, after: afterImage)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 18))
                HStack {
                    Text(label(before.day)).font(.caption.weight(.semibold))
                    Spacer()
                    Text(label(after.day)).font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Take a \(comparePose.title.lowercased()) photo on two different days to compare.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            Picker("Compare with", selection: Binding(get: { compareDay ?? earlierDays.last ?? "" }, set: { compareDay = $0 })) {
                ForEach(Array(earlierDays), id: \.self) { Text(label($0)).tag($0) }
            }
        }
        .card(tint: Theme.sleep)
    }

    // MARK: Analysis

    private func analysisCard(weekly: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Weekly analysis", color: Theme.oxygen)
                Spacer()
                if photos.isAnalyzing { ProgressView() }
            }
            if let analysis = photos.latestAnalysis {
                Text(analysis.date.formatted(date: .abbreviated, time: .omitted) + " · compared " + analysis.comparedDays.map(label).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text(analysis.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.primaryText)
            } else {
                Text("Once you have photos at least 5 days apart, Claude compares them each week with your goal, weight trend, calories, protein and training, and suggests what to adjust.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            if let error = photos.analysisError {
                Text(error).font(.caption).foregroundStyle(Theme.recoveryModerateText)
            }
            Toggle("Analyze automatically each week", isOn: weekly)
                .font(.subheadline)
            Button {
                Task { await runAnalysis() }
            } label: {
                Label("Analyze now", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.oxygen)
            .disabled(photos.isAnalyzing || photos.comparisonDays() == nil)
            if photos.analyses.count > 1 {
                DisclosureGroup("Earlier analyses") {
                    ForEach(photos.analyses.sorted { $0.date > $1.date }.dropFirst()) { analysis in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(analysis.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption.weight(.semibold))
                            Text(analysis.text).font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .font(.subheadline)
            }
        }
        .card(tint: Theme.oxygen)
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Timeline")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(photos.days, id: \.self) { day in
                    ForEach(ProgressPhotosModel.Pose.allCases) { pose in
                        if let entry = photos.entry(day: day, pose: pose), let image = photos.thumbnail(entry) {
                            Button {
                                viewing = entry
                            } label: {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .aspectRatio(3 / 4, contentMode: .fill)
                                    .clipShape(.rect(cornerRadius: 12))
                                    .overlay(alignment: .bottomLeading) {
                                        Text("\(shortLabel(day)) · \(pose.title)")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .padding(4)
                                            .background(.black.opacity(0.35), in: .rect(cornerRadius: 6))
                                            .padding(4)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func date(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func label(_ day: String) -> String {
        date(day)?.formatted(date: .abbreviated, time: .omitted) ?? day
    }

    private func shortLabel(_ day: String) -> String {
        date(day)?.formatted(.dateTime.month(.abbreviated).day()) ?? day
    }
}

/// Before/after with a draggable divider.
struct CompareSlider: View {
    let before: UIImage
    let after: UIImage
    @State private var split = 0.5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Image(uiImage: after)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                Image(uiImage: before)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: geo.size.width * split)
                    }
                Rectangle()
                    .fill(.white)
                    .frame(width: 3)
                    .shadow(radius: 3)
                    .offset(x: geo.size.width * split - 1.5)
                Circle()
                    .fill(.white)
                    .frame(width: 34, height: 34)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)).foregroundStyle(.black))
                    .shadow(radius: 4)
                    .offset(x: geo.size.width * split - 17)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                split = min(1, max(0, value.location.x / max(geo.size.width, 1)))
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Before and after comparison")
        .accessibilityAdjustableAction { direction in
            split = direction == .increment ? min(1, split + 0.1) : max(0, split - 0.1)
        }
    }
}

/// Full-size photo with delete.
private struct PhotoViewer: View {
    let entry: ProgressPhotosModel.Entry
    @Environment(ProgressPhotosModel.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            Group {
                if let image = photos.image(entry) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    ContentUnavailableView("Photo missing", systemImage: "photo")
                }
            }
            .navigationTitle(entry.date.formatted(date: .abbreviated, time: .omitted) + " · " + entry.pose.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    photos.delete(entry)
                    dismiss()
                }
            } message: {
                Text("It's only stored in this app, so it can't be recovered.")
            }
        }
    }
}

/// The system camera (photos aren't saved to the Photos library), with a
/// faint outline of the last photo to line up with.
struct CameraCapture: UIViewControllerRepresentable {
    let guide: UIImage?
    let completion: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return picker }
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        if let guide {
            let overlay = UIImageView(image: guide)
            overlay.contentMode = .scaleAspectFit
            overlay.alpha = 0.28
            overlay.isUserInteractionEnabled = false
            let bounds = UIScreen.main.bounds
            // Roughly where the 4:3 preview sits, below the top bar.
            overlay.frame = CGRect(x: 0, y: 90, width: bounds.width, height: bounds.width * 4 / 3)
            picker.cameraOverlayView = overlay
        }
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }
    }
}
