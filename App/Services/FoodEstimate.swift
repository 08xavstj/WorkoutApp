import Foundation
import UIKit
import AppCore

/// Quick-estimate food logging: a description and/or one photo goes to the
/// `food-estimate` Edge Function (Claude; the API key stays on the server)
/// and the estimate is written to Apple Health under this app's source,
/// flagged as an estimate (`EstimatedIntake`; docs/research/nutrition.md
/// option C and "how accurate").
@Observable
final class FoodEstimateModel {
    enum Phase: Equatable {
        case idle
        case estimating
        case result(EstimatedIntake.Estimate)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    @ObservationIgnored private let cloud: CloudCoach

    /// A fresh client shares the Supabase session through the Keychain, so
    /// it's the same signed-in user (and quota) as the coach.
    init(cloud: CloudCoach = CloudCoach()) {
        self.cloud = cloud
    }

    nonisolated private struct Reply: Decodable {
        var estimate: EstimatedIntake.Estimate
        var caveat: String?
    }

    /// Photos are sent at up to 1024 px on the long side and under 1 MB.
    nonisolated static let maxPhotoBytes = 1_000_000

    func estimate(description: String, photo: UIImage?, settings: UserSettings) async {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || photo != nil else {
            phase = .failed("Describe the meal or add a photo.")
            return
        }
        phase = .estimating
        let encoded = photo.flatMap(Self.jpegBase64)
        do {
            let reply = try await cloud.estimateFood(description: text, photoBase64: encoded, settings: settings)
            guard let data = reply.data(using: .utf8), let decoded = try? JSONDecoder().decode(Reply.self, from: data) else {
                phase = .failed("The estimate couldn't be read. Try again.")
                return
            }
            guard decoded.estimate.isPlausible else {
                phase = .failed("That estimate didn't look right (\(Int(decoded.estimate.calories)) kcal). Add a line about the portion and try again.")
                return
            }
            phase = .result(decoded.estimate)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func reset() {
        phase = .idle
    }

    /// Writes the estimate to Apple Health as dietary samples at `date`.
    func log(_ estimate: EstimatedIntake.Estimate, at date: Date, health: HealthKitClient) async throws {
        try await health.saveDietaryEstimate(estimate, at: date)
    }

    /// JPEG under 1 MB, base64: resized to 1024 px, then compressed harder if needed.
    nonisolated static func jpegBase64(_ image: UIImage) -> String? {
        let resized = ProgressPhotosModel.resized(image, maxSide: 1024)
        for quality in [0.7, 0.5, 0.35, 0.2] {
            if let data = resized.jpegData(compressionQuality: quality), data.count <= maxPhotoBytes {
                return data.base64EncodedString()
            }
        }
        return nil
    }
}
