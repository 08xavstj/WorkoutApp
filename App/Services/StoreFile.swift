import Foundation
import AppCore
import os

/// Where the app's JSON stores live, on top of `SafeJSONFile` (atomic writes,
/// protected until first unlock, a `.bak` of the last good file, and no save
/// after a read that failed). Every store keeps a `canSave` flag from its last
/// read and offers `reloadIfUnavailable()`, which the app calls when the phone
/// is unlocked (`protectedDataDidBecomeAvailable`) and when it comes to the
/// foreground (`RootView`).
extension SafeJSONFile {
    /// A file in Application Support.
    nonisolated static func appSupport(_ name: String) -> SafeJSONFile {
        SafeJSONFile(url: URL.applicationSupportDirectory.appending(path: name))
    }

    /// Console: category "storage".
    nonisolated static let log = Logger(subsystem: "com.lontraindustries.workoutapp", category: "storage")

    /// Loads and logs anything other than a clean read or a first launch.
    nonisolated func loadLogged<Value: Decodable>(_ type: Value.Type, decoder: JSONDecoder = JSONDecoder()) -> Loaded<Value> {
        let loaded = load(type, decoder: decoder)
        if loaded.state != .loaded && loaded.state != .missing {
            let name = url.lastPathComponent
            let state = loaded.state.rawValue
            Self.log.error("\(name, privacy: .public): \(state, privacy: .public)")
        }
        return loaded
    }

    /// Saves unless the last read said not to; logs failures.
    nonisolated func saveLogged<Value: Encodable>(_ value: Value, canSave: Bool, encoder: JSONEncoder = JSONEncoder()) {
        let name = url.lastPathComponent
        guard canSave else {
            Self.log.error("\(name, privacy: .public): not saved, the file couldn't be read yet")
            return
        }
        do {
            try save(value, encoder: encoder)
        } catch {
            Self.log.error("\(name, privacy: .public): save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
