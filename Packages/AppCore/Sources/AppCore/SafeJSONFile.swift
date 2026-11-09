import Foundation

/// A JSON file a store keeps its data in, written so that a bad read can never
/// turn into an empty save that wipes the user's data.
///
/// - Writes are atomic (a crash mid-write leaves the old file) and, on iPhone,
///   protected "until first unlock": encrypted at rest, but readable when iOS
///   launches the app in the background while the phone is locked (Apple,
///   *Encrypting your app's files*). With complete protection a background
///   launch read nothing, the store started empty and its next save
///   overwrote the real file.
/// - A missing file (first launch) is told apart from one that exists but
///   can't be read right now (`unavailable`: the store must not save, and
///   tries again later) and from one that can't be decoded (`corrupt`).
/// - Before each save the previous file is kept as `<name>.bak`. A file that
///   won't decode is moved aside to `<name>.corrupt-<time>` (never deleted)
///   and the backup is used if it decodes.
public struct SafeJSONFile: Sendable {
    public enum ReadState: String, Sendable, Equatable {
        /// No file yet: start empty; saving is fine.
        case missing
        /// Read and decoded.
        case loaded
        /// The file didn't decode; the last good copy was used and put back.
        case restoredFromBackup
        /// Neither the file nor its backup decodes. The bad file was moved
        /// aside, so starting empty and saving loses nothing on disk.
        case corrupt
        /// The file exists but couldn't be read (e.g. the phone is locked):
        /// don't save, load again when data is available.
        case unavailable

        /// Whether a store may write after this read.
        public var canSave: Bool { self != .unavailable }
    }

    public struct Loaded<Value> {
        public var value: Value?
        public var state: ReadState
    }

    public let url: URL
    public let writingOptions: Data.WritingOptions

    public init(url: URL, writingOptions: Data.WritingOptions = SafeJSONFile.defaultWritingOptions) {
        self.url = url
        self.writingOptions = writingOptions
    }

    /// Atomic and, on Apple devices, protected until first unlock.
    public static var defaultWritingOptions: Data.WritingOptions {
        #if os(iOS) || os(watchOS) || os(visionOS) || os(tvOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }

    /// The last good version, written before each save.
    public var backupURL: URL { url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".bak") }

    /// Where an undecodable file is moved, stamped so none is ever overwritten.
    func corruptURL(at date: Date) -> URL {
        let stamp = Int(date.timeIntervalSince1970)
        return url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".corrupt-\(stamp)")
    }

    // MARK: Reading

    public func load<Value: Decodable>(_ type: Value.Type, decoder: JSONDecoder = JSONDecoder(), now: Date = .now) -> Loaded<Value> {
        let manager = FileManager.default
        // Atomic writes never leave the file missing, so a missing file was
        // never written or was deleted on purpose (a reset): start empty.
        guard manager.fileExists(atPath: url.path(percentEncoded: false)) else { return Loaded(value: nil, state: .missing) }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return Loaded(value: nil, state: .unavailable)
        }
        if let value = try? decoder.decode(type, from: data) {
            return Loaded(value: value, state: .loaded)
        }
        // Move the bad file aside first: if that fails, saving could overwrite it.
        let aside = corruptURL(at: now)
        do {
            try manager.moveItem(at: url, to: aside)
        } catch {
            return Loaded(value: nil, state: .unavailable)
        }
        let restored = fromBackup(type, decoder: decoder, otherwise: .corrupt)
        // A backup that can't be read right now: put the file back, so the next
        // read doesn't find it missing and start empty.
        if restored.state == .unavailable { try? manager.moveItem(at: aside, to: url) }
        return restored
    }

    private func fromBackup<Value: Decodable>(_ type: Value.Type, decoder: JSONDecoder, otherwise: ReadState) -> Loaded<Value> {
        guard FileManager.default.fileExists(atPath: backupURL.path(percentEncoded: false)) else { return Loaded(value: nil, state: otherwise) }
        guard let data = try? Data(contentsOf: backupURL) else { return Loaded(value: nil, state: .unavailable) }
        guard let value = try? decoder.decode(type, from: data) else { return Loaded(value: nil, state: otherwise) }
        // Put the good copy back in place, so the next launch reads it even if nothing is saved first.
        try? data.write(to: url, options: writingOptions)
        return Loaded(value: value, state: .restoredFromBackup)
    }

    // MARK: Writing

    /// Keeps the current file as the backup, then writes `value` atomically.
    public func save<Value: Encodable>(_ value: Value, encoder: JSONEncoder = JSONEncoder()) throws {
        let data = try encoder.encode(value)
        try write(data)
    }

    /// Same as `save` for data that is already encoded.
    public func write(_ data: Data) throws {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The file on disk is the last good one: a store only saves after a
        // read that allowed it, and an undecodable file was moved aside.
        if let current = try? Data(contentsOf: url), current != data {
            try? current.write(to: backupURL, options: writingOptions)
        }
        try data.write(to: url, options: writingOptions)
    }
}

extension SafeJSONFile.Loaded: Sendable where Value: Sendable {}
