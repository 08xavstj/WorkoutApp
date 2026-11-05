import SwiftUI
import UIKit

/// Daily front and side photos, a before/after slider and a timeline.
/// Photos stay inside the app and never leave the iPhone.
///
/// Pushed from Health › Records (`pushed: true`); a root sheet from the Log
/// tab, reminders and workoutapp://photos.
struct ProgressPhotosView: View {
    @Environment(ProgressPhotosModel.self) private var photos
    @Environment(\.dismiss) private var dismiss
    @State private var capturing: ProgressPhotosModel.Pose?
    @State private var comparePose: ProgressPhotosModel.Pose = .front
    @State private var compareDay: String?
    @State private var viewing: ProgressPhotosModel.Entry?
    /// True when pushed onto another NavigationStack.
    var pushed = false

    var body: some View {
        SheetNavigationStack(isSheet: !pushed) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    todayCard
                    if photos.days.count >= 2 { compareCard }
                    if !photos.days.isEmpty { timeline }
                    Text("Photos are saved only inside Tensile, encrypted on your iPhone. They're never added to your Photos library or sent anywhere.")
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
                if !pushed {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
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
            // Roughly where the 4:3 preview sits, below the top bar. The
            // picker fills the screen, so its view's size stands in for it.
            let width = picker.view.bounds.width > 0 ? picker.view.bounds.width : 390
            overlay.frame = CGRect(x: 0, y: 90, width: width, height: width * 4 / 3)
            overlay.autoresizingMask = [.flexibleWidth]
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
