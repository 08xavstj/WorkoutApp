import Foundation

/// The kind of device that recorded a sleep sample.
public enum SleepTracker: String, Sendable, Codable, CaseIterable {
    /// An Oura ring (its Apple Health samples, or Oura's own data via the direct link).
    case ring
    case watch
    /// The iPhone's sleep schedule, another app, or unknown.
    case other
}

/// Whose sleep to use when more than one device recorded the night.
///
/// - `ring` (the default): Oura's night when it has one, else the rest. In
///   the one study that tested both against lab polysomnography, Oura Ring
///   Gen3 staged sleep more consistently than Apple Watch Series 8 (stage
///   sensitivity about 76-80% against 50-86%), and Apple Watch under-counted
///   deep sleep and over-counted light sleep, while both got total sleep
///   about right (Robbins et al., Sensors 2024;24:6532; 35 healthy adults,
///   one night, older models, and the lead author advises Oura, so modest
///   evidence). Mainly it's the user's choice.
/// - `watch`: Apple Watch's night when it has one.
/// - `combined`: every source merged (the app's behaviour before this setting).
///
/// Taking one device's whole night keeps the stages from one algorithm:
/// mixing two devices' stages minute by minute would mix two scorers.
public enum SleepSourcePreference: String, Sendable, Codable, CaseIterable, Identifiable {
    case ring
    case watch
    case combined

    public var id: String { rawValue }

    /// Settings default.
    public static let standard: SleepSourcePreference = .ring

    public var title: String {
        switch self {
        case .ring: "Oura ring first"
        case .watch: "Apple Watch first"
        case .combined: "Combine all"
        }
    }

    public var detail: String {
        switch self {
        case .ring: "Uses the ring's night when it has one, else the watch's."
        case .watch: "Uses the watch's night when it has one, else the ring's."
        case .combined: "Merges every device's sleep."
        }
    }

    /// The tracker this preference puts first; nil for `combined`.
    public var preferred: SleepTracker? {
        switch self {
        case .ring: .ring
        case .watch: .watch
        case .combined: nil
        }
    }
}

public enum SleepSource {
    /// Oura's app identifier in Apple Health.
    public static let ouraBundlePrefix = "com.ouraring"

    /// What recorded a sample, from its Apple Health source and device.
    /// - Parameters:
    ///   - bundleID: the writing app's bundle identifier.
    ///   - sourceName: the source's display name.
    ///   - deviceModel: the device's model ("Watch"), if the sample names one.
    public static func tracker(bundleID: String?, sourceName: String?, deviceModel: String?) -> SleepTracker {
        let bundle = bundleID?.lowercased() ?? ""
        let name = sourceName?.lowercased() ?? ""
        if bundle.hasPrefix(ouraBundlePrefix) || name.contains("oura") { return .ring }
        if deviceModel?.lowercased().contains("watch") == true { return .watch }
        return .other
    }

    /// The preferred tracker's night is used only when it covers at least this
    /// share of the longest night another tracker recorded. A ring that died
    /// at 2 am, was taken off, or logged only an evening doze shouldn't replace
    /// the watch's full night. The share is the app's choice.
    public static let minimumPreferredShare = 0.7

    /// One night's samples, keeping only the preferred tracker's when it
    /// recorded that night (`minimumPreferredShare`); every sample otherwise.
    public static func pick(_ samples: [SleepSample], prefer preference: SleepSourcePreference) -> [SleepSample] {
        guard let preferred = preference.preferred else { return samples }
        func asleepSeconds(_ tracker: SleepTracker?) -> TimeInterval {
            samples.filter { $0.tracker == tracker && $0.stage.isAsleep }
                .reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start)) }
        }
        let theirs = asleepSeconds(preferred)
        guard theirs > 0 else { return samples }
        let others = Set(samples.map(\.tracker)).subtracting([preferred]).map(asleepSeconds).max() ?? 0
        guard theirs >= others * minimumPreferredShare else { return samples.filter { $0.tracker != preferred } }
        return samples.filter { $0.tracker == preferred }
    }

    /// `pick` for several nights at once: samples grouped by `night`.
    public static func pick(_ samples: [SleepSample], prefer preference: SleepSourcePreference,
                            night: (SleepSample) -> Date) -> [SleepSample] {
        guard preference.preferred != nil else { return samples }
        var byNight: [Date: [SleepSample]] = [:]
        for sample in samples { byNight[night(sample), default: []].append(sample) }
        return byNight.keys.sorted().flatMap { pick(byNight[$0] ?? [], prefer: preference) }
    }
}
