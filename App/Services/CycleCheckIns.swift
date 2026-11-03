import Foundation
import AppCore

extension CheckInStore {
    /// Days since a morning check-in last logged "On my period" (0 = today),
    /// looking back `days` mornings; nil when none was logged. Feeds the
    /// illness watch's cycle allowance (`IllnessWatch.cycleWindowDays`).
    func daysSinceLastPeriod(now: Date = .now, days: Int = 40) -> Int? {
        let calendar = Calendar.current
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            if morning(on: day)?.cycle == .period { return offset }
        }
        return nil
    }
}
