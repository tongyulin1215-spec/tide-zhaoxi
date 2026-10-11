import Foundation

/// A value kept in one JSON file.
public protocol StoredValue: Codable, Equatable {
    init()
}

/// Reads and writes one value as a JSON file. An unreadable file is moved aside, never overwritten.
public final class DataStore<Value: StoredValue> {
    public enum LoadIssue: Equatable, Sendable {
        /// The file couldn't be read and was moved to this path; the app starts empty.
        case movedAside(URL)
        /// The file couldn't be read or moved; the store is read-only so it is never overwritten.
        case unreadable
    }

    public let fileURL: URL
    public private(set) var loadIssue: LoadIssue?
    public private(set) var isReadOnly = false
    /// Modification date of the file as of our last load or save.
    private var lastSeen: Date?

    struct ReadOnlyError: Error {}

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> Value {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return Value() }
        do {
            let value = try Self.decoder.decode(Value.self, from: Data(contentsOf: fileURL))
            lastSeen = modificationDate
            return value
        } catch {
            let stem = fileURL.deletingPathExtension().lastPathComponent
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(stem).broken-\(Int(Date().timeIntervalSince1970)).json")
            do {
                try fm.moveItem(at: fileURL, to: backup)
                loadIssue = .movedAside(backup)
            } catch {
                loadIssue = .unreadable
                isReadOnly = true
            }
            return Value()
        }
    }

    public func save(_ value: Value) throws {
        if isReadOnly { throw ReadOnlyError() }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: fileURL, options: .atomic)
        lastSeen = modificationDate
    }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    /// The file's value if someone else (the widget) changed it since our last load or save.
    public func loadIfChanged() -> Value? {
        guard let m = modificationDate, m != lastSeen,
              let value = try? Self.decoder.decode(Value.self, from: Data(contentsOf: fileURL)) else { return nil }
        lastSeen = m
        return value
    }
}

public typealias PlanStore = DataStore<PlanData>

extension PlanData: StoredValue {}

extension DataStore where Value == PlanData {
    /// The pre-widget location of the plan file.
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cre", isDirectory: true)
            .appendingPathComponent("data.json")
    }
}
