import AVFoundation
import AppCore
import Foundation

/// Reads the back camera with the flashlight on and records the average colour
/// of each frame. Runs on its own queue; the model polls it.
// AVCaptureSession and the frame buffer are only touched on `queue` or under
// `lock`, hence @unchecked Sendable.
nonisolated final class PPGCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    struct Frame: Sendable {
        var time: Double
        var red: Double
        var green: Double
        var blue: Double
    }

    enum CaptureError: Error {
        case noCamera, notAllowed, setupFailed
    }

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "workoutapp.ppg")
    private let lock = NSLock()
    private var frames: [Frame] = []
    private var device: AVCaptureDevice?

    /// Asks for camera access (once) and starts recording with the light on.
    func start() async throws {
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else { throw CaptureError.notAllowed }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CaptureError.noCamera
        }
        device = camera
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.configure(camera)
                    self.session.startRunning()
                    try self.setTorch(on: true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        queue.async {
            try? self.setTorch(on: false)
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Frames recorded so far.
    func snapshot() -> [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    func reset() {
        lock.lock()
        frames.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    /// Stops auto-exposure and white balance from "correcting" the pulse away.
    func lockExposure() {
        queue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            device.unlockForConfiguration()
        }
    }

    private func configure(_ camera: AVCaptureDevice) throws {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CaptureError.setupFailed }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CaptureError.setupFailed }
        session.addOutput(output)

        // The smallest format that runs at 60 fps (timing resolution matters for HRV).
        try camera.lockForConfiguration()
        defer { camera.unlockForConfiguration() }
        let fast = camera.formats
            .filter { format in format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 60 } }
            .min { area($0) < area($1) }
        if let fast {
            camera.activeFormat = fast
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 60)
            camera.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 60)
        }
    }

    private func area(_ format: AVCaptureDevice.Format) -> Int32 {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return size.width * size.height
    }

    private func setTorch(on: Bool) throws {
        guard let device, device.hasTorch else { return }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if on {
            try device.setTorchModeOn(level: 1.0)
        } else {
            device.torchMode = .off
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        // Average the middle half of the picture, every 4th pixel (BGRA).
        var red = 0, green = 0, blue = 0, count = 0
        var y = height / 4
        while y < height * 3 / 4 {
            var x = width / 4
            let row = pixels + y * rowBytes
            while x < width * 3 / 4 {
                let pixel = row + x * 4
                blue += Int(pixel[0])
                green += Int(pixel[1])
                red += Int(pixel[2])
                count += 1
                x += 4
            }
            y += 4
        }
        guard count > 0 else { return }
        let scale = 1 / (255 * Double(count))
        let frame = Frame(time: time, red: Double(red) * scale, green: Double(green) * scale, blue: Double(blue) * scale)
        lock.lock()
        frames.append(frame)
        lock.unlock()
    }
}

/// A 60-second fingertip HRV reading: waits for a finger over the lens, then
/// records, then analyses (see `PPGAnalyzer`).
@Observable
final class CameraHRVModel {
    enum Phase: Equatable {
        case idle
        case waitingForFinger
        case measuring
        case analysing
        case done(PPGAnalyzer.Result)
        case failed(String)
    }

    static let duration = 60.0

    private(set) var phase: Phase = .idle
    private(set) var progress = 0.0
    private(set) var waveform: [Double] = []
    private(set) var fingerOn = false
    @ObservationIgnored private let capture = PPGCapture()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var measureStart: Double?
    @ObservationIgnored private var fingerSince: Double?
    @ObservationIgnored private var fingerLostSince: Double?

    func start() async {
        progress = 0
        waveform = []
        measureStart = nil
        fingerSince = nil
        fingerLostSince = nil
        capture.reset()
        do {
            try await capture.start()
        } catch PPGCapture.CaptureError.notAllowed {
            phase = .failed("Camera access is off. Turn it on in Settings → Tensile → Camera.")
            return
        } catch {
            phase = .failed("The camera couldn't start. Try again.")
            return
        }
        phase = .waitingForFinger
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled else { return }
                if await self.tick() { return }
            }
        }
    }

    func cancel() {
        loop?.cancel()
        capture.stop()
        if phase != .analysing { phase = .idle }
    }

    /// One update; true when finished.
    private func tick() async -> Bool {
        let frames = capture.snapshot()
        guard let last = frames.last else { return false }
        let recent = frames.suffix(10)
        let red = recent.map(\.red).reduce(0, +) / Double(recent.count)
        let green = recent.map(\.green).reduce(0, +) / Double(recent.count)
        let blue = recent.map(\.blue).reduce(0, +) / Double(recent.count)
        fingerOn = PPGAnalyzer.fingerDetected(red: red, green: green, blue: blue)

        switch phase {
        case .waitingForFinger:
            if fingerOn {
                if fingerSince == nil { fingerSince = last.time }
                // Settle for 1.5 s, then fix exposure and start the clock.
                if let since = fingerSince, last.time - since >= 1.5 {
                    capture.lockExposure()
                    measureStart = last.time + 0.5
                    phase = .measuring
                }
            } else {
                fingerSince = nil
            }
        case .measuring:
            guard let start = measureStart else { return false }
            let measured = frames.filter { $0.time >= start }
            waveform = PPGAnalyzer.preview(Self.samples(measured))
            progress = min(1, max(0, (last.time - start) / Self.duration))
            if fingerOn {
                fingerLostSince = nil
            } else {
                if fingerLostSince == nil { fingerLostSince = last.time }
                if let lost = fingerLostSince, last.time - lost > 2 {
                    // Start over once the finger is back.
                    phase = .waitingForFinger
                    fingerSince = nil
                    fingerLostSince = nil
                    progress = 0
                    waveform = []
                    return false
                }
            }
            if last.time - start >= Self.duration {
                capture.stop()
                phase = .analysing
                let samples = Self.samples(measured)
                let outcome = await Self.analyze(samples)
                switch outcome {
                case .success(let result): phase = .done(result)
                case .failure(let failure): phase = .failed(Self.message(for: failure))
                }
                return true
            }
        default:
            break
        }
        return false
    }

    /// Brightness per frame: red, unless the red channel is saturated by the
    /// flashlight, in which case green carries the pulse better.
    private static func samples(_ frames: [PPGCapture.Frame]) -> [PPGAnalyzer.Sample] {
        guard let first = frames.first else { return [] }
        let meanRed = frames.map(\.red).reduce(0, +) / Double(frames.count)
        let useGreen = meanRed > 0.95
        return frames.map { PPGAnalyzer.Sample(time: $0.time - first.time, value: useGreen ? $0.green : $0.red) }
    }

    @concurrent
    nonisolated private static func analyze(_ samples: [PPGAnalyzer.Sample]) async -> Result<PPGAnalyzer.Result, PPGAnalyzer.Failure> {
        PPGAnalyzer.analyze(samples)
    }

    private static func message(for failure: PPGAnalyzer.Failure) -> String {
        switch failure {
        case .tooShort:
            "The reading was too short. Keep your finger on the lens for the full minute."
        case .notEnoughBeats, .tooNoisy:
            "Couldn't find a steady pulse. Rest your fingertip lightly over the lens and flash (don't press hard), keep your hand still and supported, and try again."
        }
    }
}
