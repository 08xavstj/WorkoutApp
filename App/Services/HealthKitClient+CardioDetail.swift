import AppCore
import CoreLocation
import Foundation
import HealthKit
import os

/// Everything the cardio summary page shows for one workout: the workout's
/// own totals, its GPS route (outdoors), heart rate from a minute before to
/// a few minutes after (for the recovery), and the cardio fitness estimate
/// Apple Health saved from it, if any.
nonisolated struct CardioWorkoutDetail: Sendable {
    var uuid: UUID
    var name: String
    /// Tensile's own cardio activity (`HealthKitClient.watchCardioMetadataKey`); nil for other apps' workouts.
    var activity: CardioActivity?
    /// Running, walking or hiking: speed is shown as a pace.
    var showsPace: Bool
    var start: Date
    var end: Date
    /// Time moving, without pauses (HKWorkout's `duration`).
    var activeSeconds: TimeInterval
    var distanceMeters: Double?
    var activeKcal: Double?
    /// Metres climbed as the recording app saved it (Apple's Workout app does);
    /// nil when it didn't, and the route's own climb is used instead.
    var elevationAscended: Double?
    var route: [RoutePoint]
    var heartRate: [HeartRateSample]
    /// VO₂ max (ml/kg/min) Apple Health estimated from this workout.
    var vo2Max: Double?
    var sourceName: String?
    /// Run, ride, sport... (`ActivityKind`), for best efforts.
    var kind: ActivityKind = .other
}

nonisolated extension HealthKitClient {
    /// The workout with this ID and what was recorded around it, or nil if it is gone.
    @concurrent
    func cardioWorkoutDetail(id: UUID) async throws -> CardioWorkoutDetail? {
        if let demo = DemoHealth.active { return demo.cardioWorkoutDetail(id: id) }
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))],
            sortDescriptors: []
        ).result(for: store)
        guard let workout = workouts.first else { return nil }

        // The route: one or more route samples attached to the workout, in order.
        let routes = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store).compactMap { $0 as? HKWorkoutRoute }
        var points: [RoutePoint] = []
        for route in routes {
            points += try await routePoints(route)
        }

        // Heart rate from a minute before to five after, for the one-minute recovery.
        let window = HKQuery.predicateForSamples(
            withStart: workout.startDate.addingTimeInterval(-60), end: workout.endDate.addingTimeInterval(300)
        )
        let unit = HKUnit.count().unitDivided(by: .minute())
        let heartSamples = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: window)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
        // One device's readings: a ring's minute-by-minute heart rate mixed in
        // with the watch's would zig-zag between two sensors. The watch wins
        // during exercise (docs/research/oura-ring-2026-11.md).
        let fromWatch = heartSamples.filter { $0.device?.model?.localizedCaseInsensitiveContains("watch") == true }
        let chosen = fromWatch.isEmpty ? heartSamples : fromWatch
        let heartRate = chosen.map { HeartRateSample(date: $0.startDate, bpm: $0.quantity.doubleValue(for: unit)) }

        let vo2 = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(
                type: HKQuantityType(.vo2Max),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate.addingTimeInterval(3 * 3600))
            )],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store).last
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        let distance = Self.workoutDistanceTypes.lazy
            .compactMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
            .first { $0 > 0 }
        let activity = (workout.metadata?[Self.watchCardioMetadataKey] as? String).flatMap(CardioActivity.init(rawValue:))
        let paceTypes: [HKWorkoutActivityType] = [.running, .walking, .hiking]
        return CardioWorkoutDetail(
            uuid: workout.uuid,
            name: activity?.title ?? Self.name(for: workout.workoutActivityType),
            activity: activity,
            showsPace: activity.map { $0.movement == .onFoot } ?? paceTypes.contains(workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            activeSeconds: workout.duration,
            distanceMeters: distance,
            activeKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
            elevationAscended: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
            route: points,
            heartRate: heartRate,
            vo2Max: vo2?.quantity.doubleValue(for: vo2Unit),
            sourceName: workout.device?.name ?? workout.sourceRevision.source.name,
            kind: Self.activityKind(for: workout.workoutActivityType, tensile: activity)
        )
    }

    /// Every fix of one route sample (HKWorkoutRouteQuery delivers them in batches).
    func routePoints(_ route: HKWorkoutRoute) async throws -> [RoutePoint] {
        let collected = OSAllocatedUnfairLock(initialState: [RoutePoint]())
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let batch = (locations ?? []).map { location in
                    RoutePoint(
                        latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                        altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                        time: location.timestamp, horizontalAccuracy: location.horizontalAccuracy
                    )
                }
                collected.withLock { $0 += batch }
                if done {
                    continuation.resume(returning: collected.withLock { $0 })
                }
            }
            store.execute(query)
        }
    }
}

nonisolated extension DemoHealth {
    /// A demo workout's detail, with a made-up loop for runs and rides so
    /// the screenshots show the map. The loop is a generic lakeside oval.
    func cardioWorkoutDetail(id: UUID) -> CardioWorkoutDetail? {
        guard let workout = cardio.first(where: { $0.id == id }), workout.end <= now else { return nil }
        let duration = workout.end.timeIntervalSince(workout.start)
        let meters = (workout.km ?? 18) * 1000
        let heart = heartRate(from: workout.start.addingTimeInterval(-60), to: workout.end.addingTimeInterval(300))
        // An oval of the workout's length, one fix every 2 s, with a hill on one side.
        let count = Int(duration / 2)
        let radiusNorth = meters / (2 * .pi) * 0.7
        let radiusEast = meters / (2 * .pi) * 1.3
        let center = (latitude: 47.3505, longitude: 8.5390)
        let perDegree = 111_320.0
        let points: [RoutePoint] = (0...count).map { index in
            let fraction = Double(index) / Double(max(count, 1))
            // Slower up the hill (first half), faster down it.
            let angle = 2 * .pi * (fraction + 0.04 * sin(2 * .pi * fraction))
            let north = radiusNorth * sin(angle)
            let east = radiusEast * cos(angle)
            return RoutePoint(
                latitude: center.latitude + north / perDegree,
                longitude: center.longitude + east / (perDegree * cos(center.latitude * .pi / 180)),
                altitude: 410 + 22 * sin(angle - .pi / 2) + 22,
                time: workout.start.addingTimeInterval(Double(index) * 2),
                horizontalAccuracy: 5
            )
        }
        return CardioWorkoutDetail(
            uuid: workout.id, name: workout.name, activity: nil, showsPace: workout.name == "Run",
            start: workout.start, end: workout.end, activeSeconds: duration, distanceMeters: meters,
            activeKcal: workout.kcal, elevationAscended: nil, route: points, heartRate: heart,
            vo2Max: workout.name == "Run" ? 47.2 : nil, sourceName: "Apple Watch",
            kind: workout.name == "Ride" ? .ride : .run
        )
    }
}
