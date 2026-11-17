import Foundation
import Vision
import AppCore

/// Reads the text in a picked screenshot with Vision, on the iPhone.
///
/// Nothing leaves the phone and the picture isn't kept: the image data is
/// used for this one call and dropped. Finding the scores in the text is
/// `AppleScoreScreenReader` in AppCore, which is tested.
nonisolated enum ScreenshotTextReader {
    /// The recognised lines with their places in the picture (fractions of
    /// its size, origin at the top left).
    @concurrent
    static func lines(in imageData: Data) async throws -> [AppleScoreScreenReader.Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Scores are bare numbers beside short labels: language correction has
        // nothing to work with and can change digits.
        request.usesLanguageCorrection = false
        let observations = try await request.perform(on: imageData, orientation: nil)
        return observations.map { observation in
            // Vision measures from the bottom left; the reader from the top left.
            let box = observation.boundingBox
            return AppleScoreScreenReader.Line(
                observation.transcript,
                box: AppleScoreScreenReader.Box(
                    x: Double(box.origin.x),
                    y: Double(1 - box.origin.y - box.height),
                    width: Double(box.width),
                    height: Double(box.height)
                )
            )
        }
    }
}
