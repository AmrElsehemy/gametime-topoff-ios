import Foundation

/// An event as stored on the device: its name plus string properties, including the common fields.
public struct StoredEvent: Codable, Equatable, Sendable {
    public let name: String
    public let properties: [String: String]

    public init(name: String, properties: [String: String]) {
        self.name = name
        self.properties = properties
    }

    public var timestampMs: Int64? { properties["ts"].flatMap { Int64($0) } }
}

public protocol EventStoring: Sendable {
    func append(_ event: StoredEvent)
    func all() -> [StoredEvent]
    func clear()
    /// The file holding the events, if the store is file-backed (used to export a tester's log).
    var fileURL: URL? { get }
}

/// Keeps events in memory. Used in tests.
public final class InMemoryEventStore: EventStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [StoredEvent] = []

    public init() {}
    public var fileURL: URL? { nil }

    public func append(_ event: StoredEvent) {
        lock.withLock { events.append(event) }
    }

    public func all() -> [StoredEvent] { lock.withLock { events } }
    public func clear() { lock.withLock { events.removeAll() } }
}

/// One JSON object per line, appended to a file. The file is trimmed to its newest events when it
/// grows past `maxEvents`, so it can never grow without bound. Every failure is swallowed: analytics
/// must never be able to break the game.
public final class FileEventStore: EventStoring, @unchecked Sendable {
    public let fileURL: URL?
    private let maxEvents: Int
    private let lock = NSLock()
    private var count: Int?

    public init(fileURL: URL, maxEvents: Int = 5_000) {
        self.fileURL = fileURL
        self.maxEvents = max(10, maxEvents)
    }

    /// `Application Support/TopOff/events.jsonl`.
    public static func standardURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("TopOff", isDirectory: true).appendingPathComponent("events.jsonl")
    }

    public func append(_ event: StoredEvent) {
        lock.withLock {
            guard let fileURL, let data = try? JSONEncoder.sorted.encode(event) else { return }
            do {
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                var line = data
                line.append(0x0A)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let handle = try FileHandle(forWritingTo: fileURL)
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: fileURL, options: .atomic)
                }
                count = (count ?? readLines().count - 1) + 1
                if let count, count > maxEvents { trim() }
            } catch {
                // Never let a full disk or a permissions problem reach the player.
            }
        }
    }

    public func all() -> [StoredEvent] {
        lock.withLock { readLines().compactMap { try? JSONDecoder().decode(StoredEvent.self, from: Data($0.utf8)) } }
    }

    public func clear() {
        lock.withLock {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            count = 0
        }
    }

    private func readLines() -> [String] {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    /// Keeps the newest 80% so trimming does not happen on every write afterwards.
    private func trim() {
        guard let fileURL else { return }
        let lines = readLines()
        let kept = lines.suffix(maxEvents * 4 / 5)
        let text = kept.joined(separator: "\n") + "\n"
        try? text.write(to: fileURL, atomically: true, encoding: .utf8)
        count = kept.count
    }
}

extension JSONEncoder {
    /// Stable key order, so exported logs diff and compress well.
    static let sorted: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
