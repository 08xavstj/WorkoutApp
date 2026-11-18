import Foundation
import HealthKit
import AppCore

nonisolated extension HealthKitClient {
    /// Overnight breathing rate by morning, from one device
    /// (`OneDeviceBaseline`), for the illness watch's breathing flag and the
    /// Biology tab's breathing-rate history.
    ///
    /// Oura writes one average a night to Apple Health, the watch many
    /// readings a night (docs/research/oura-ring-2026-11.md §2, §4.3): they
    /// used to be averaged together. Now each reading is filed by device
    /// (`SleepSource.tracker`) and the night's mean kept per device, with the
    /// ring's nights also filled from the direct link (`OuraCache`). Neither
    /// device has a published PSG validation of breathing rate (§5), so it is
    /// only ever compared with the same device's own usual.
    ///
    /// - Parameters:
    ///   - days: nights to read, ending with the morning of `today`.
    @concurrent
    func nightlyBreathingRate(days: Int, today: Date) async -> OneDeviceBaseline.Choice {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: today)
        if let demo = DemoHealth.active {
            var watch: [Date: Double] = [:]
            for value in demo.dailySeries(.respiratoryRate, days: days) { watch[calendar.startOfDay(for: value.date)] = value.value }
            return OneDeviceBaseline.choose(ring: [:], watch: watch, latest: morning)
        }
        // Readings from 6 pm before the first night to 6 pm on the last morning
        // (the window `Oura.morning(of:)` files under each morning).
        let start = morning.addingTimeInterval(-Double(days) * 86_400 - 6 * 3600)
        let end = morning.addingTimeInterval(18 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.respiratoryRate), predicate: predicate)],
            sortDescriptors: []
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples = (try? await descriptor.result(for: store)) ?? []
        let readings: [(date: Date, value: Double, device: BaselineDevice)] = samples.map { sample in
            let source = sample.sourceRevision.source
            let tracker = SleepSource.tracker(bundleID: source.bundleIdentifier, sourceName: source.name, deviceModel: sample.device?.model)
            let device: BaselineDevice = tracker == .ring ? .ring : .watch
            return (date: sample.startDate, value: sample.quantity.doubleValue(for: unit), device: device)
        }
        let means = OneDeviceBaseline.nightlyMeans(readings, calendar: calendar)
        var ring = means.ring
        // Nights the ring has in the direct link's download but not in Health (sharing off, not synced yet).
        let oldest = calendar.date(byAdding: .day, value: -(days - 1), to: morning) ?? morning
        for (night, value) in OuraCache.shared.nightlyBreathingRate() where night >= oldest && ring[night] == nil {
            ring[night] = value
        }
        return OneDeviceBaseline.choose(ring: ring, watch: means.watch, latest: morning)
    }
}
