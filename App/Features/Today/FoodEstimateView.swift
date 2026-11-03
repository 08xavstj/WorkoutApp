import SwiftUI
import PhotosUI
import AppCore

/// "Estimate a meal": describe it and/or add a photo, Claude estimates
/// calories, protein, carbs, fat and fibre, and the result can be logged to
/// Apple Health as an estimate. For meals you wouldn't otherwise log;
/// Cronometer stays the record (nutrition.md option C).
struct FoodEstimateView: View {
    @Environment(UserSettings.self) private var settings
    @Environment(\.healthClient) private var health
    @Environment(AppRefresher.self) private var refresher
    @Environment(\.dismiss) private var dismiss
    @State private var model = FoodEstimateModel()
    @State private var description = ""
    @State private var photo: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var mealTime = Date.now
    @State private var logged = false
    @State private var logError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inputCard
                    resultCard
                    Text("Estimates from a photo get calories and protein about as close as a dietitian would but miss by more than 10% on most nutrients, mostly under, and do worst on large or mixed plates (O'Hara 2025). One line about the portion helps the most. Days logged only as estimates don't count toward your measured maintenance.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .lockedToScreenWidth()
            }
            .background(alignment: .top) {
                TopGlow(colors: [Theme.Wash.mint, Theme.Wash.butter, Theme.Wash.peach], height: 300)
            }
            .background(Theme.background)
            .navigationTitle("Estimate a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraCapture(guide: nil) { image in
                    if let image { photo = image }
                    showingCamera = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        photo = image
                    }
                    pickerItem = nil
                }
            }
        }
    }

    // MARK: Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardLabel(text: "What did you eat?", color: Theme.nutrition)
            TextField("e.g. grilled chicken, about 200 g, with a cup of rice", text: $description, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .background(Theme.cardRaised, in: .rect(cornerRadius: 12))
            photoRow
            DatePicker("Eaten at", selection: $mealTime, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                .font(.subheadline)
            Button {
                logged = false
                logError = nil
                Task { await model.estimate(description: description, photo: photo, settings: settings) }
            } label: {
                HStack {
                    if model.phase == .estimating { ProgressView().tint(.white) }
                    Text(model.phase == .estimating ? "Estimating…" : "Estimate")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient(colors: Theme.nutritionColors, startPoint: .leading, endPoint: .trailing), in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(model.phase == .estimating || (description.trimmingCharacters(in: .whitespaces).isEmpty && photo == nil))
            if settings.supabaseURL.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("Needs the Claude coach set up in Settings (Supabase URL and key).")
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryModerateText)
            }
        }
        .card(tint: Theme.nutrition)
    }

    private var photoRow: some View {
        HStack(spacing: 10) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityLabel("Meal photo")
                Button("Remove photo") { self.photo = nil }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Button {
                    showingCamera = true
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.nutrition)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.nutrition)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Result

    @ViewBuilder
    private var resultCard: some View {
        switch model.phase {
        case .idle, .estimating:
            EmptyView()
        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.recoveryLowText)
                .fixedSize(horizontal: false, vertical: true)
                .card()
        case .result(let estimate):
            result(estimate)
        }
    }

    private func result(_ estimate: EstimatedIntake.Estimate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardLabel(text: "Estimate", color: Theme.nutrition)
                Spacer()
                Chip(text: "\(estimate.confidence.capitalized) confidence", color: estimate.confidence == "high" ? Theme.recoveryHigh : Theme.recoveryModerate)
            }
            Text(estimate.summary)
                .font(.headline)
                .foregroundStyle(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text(estimate.calorieRangeText)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .foregroundStyle(Theme.primaryText)
            macros(estimate)
            if let assumptions = estimate.assumptions, !assumptions.isEmpty {
                Text("Assumed: \(assumptions)")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(EstimatedIntake.caveat)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.recoveryModerateText)
                .fixedSize(horizontal: false, vertical: true)
            logButton(estimate)
        }
        .card(tint: Theme.nutrition)
    }

    private func macros(_ estimate: EstimatedIntake.Estimate) -> some View {
        HStack(spacing: 14) {
            macro("Protein", estimate.proteinGrams, Theme.nutrition)
            macro("Carbs", estimate.carbsGrams, Theme.strain)
            macro("Fat", estimate.fatGrams, Theme.lifting)
            macro("Fibre", estimate.fibreGrams, Theme.recoveryHigh)
        }
    }

    private func macro(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(Int(grams.rounded())) g")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func logButton(_ estimate: EstimatedIntake.Estimate) -> some View {
        if logged {
            Label("Logged to Apple Health as an estimate", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.recoveryHighText)
        } else {
            Button {
                Task { await logEstimate(estimate) }
            } label: {
                Text("Log to Apple Health as an estimate")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.ink, in: .capsule)
            }
            .buttonStyle(.plain)
            .disabled(health == nil)
            if let logError {
                Text(logError)
                    .font(.caption)
                    .foregroundStyle(Theme.recoveryLowText)
            }
        }
    }

    private func logEstimate(_ estimate: EstimatedIntake.Estimate) async {
        guard let health else { return }
        do {
            try await model.log(estimate, at: mealTime, health: health)
            logged = true
            refresher.refreshSoon()
        } catch {
            logError = "Couldn't save: \(error.localizedDescription)"
        }
    }
}
