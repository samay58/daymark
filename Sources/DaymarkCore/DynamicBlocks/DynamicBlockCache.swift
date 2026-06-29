import Foundation

public struct DynamicBlockCacheRecord: Codable, Equatable, Sendable {
    public var sourcePath: String
    public var commandHash: String
    public var rawCommand: String
    public var rendererName: String
    public var renderedOutputHash: String
    public var refreshedAt: String

    public init(
        sourcePath: String,
        commandHash: String,
        rawCommand: String,
        rendererName: String,
        renderedOutputHash: String,
        refreshedAt: String
    ) {
        self.sourcePath = sourcePath
        self.commandHash = commandHash
        self.rawCommand = rawCommand
        self.rendererName = rendererName
        self.renderedOutputHash = renderedOutputHash
        self.refreshedAt = refreshedAt
    }
}

public struct DynamicBlockCacheStore {
    private struct Envelope: Codable {
        var version: Int
        var records: [DynamicBlockCacheRecord]
    }

    private let fileManager: FileManager
    private let atomicWriter: AtomicFileWriter

    public init(fileManager: FileManager = .default, atomicWriter: AtomicFileWriter = AtomicFileWriter()) {
        self.fileManager = fileManager
        self.atomicWriter = atomicWriter
    }

    public func read(root: WorkspaceRoot) throws -> [DynamicBlockCacheRecord] {
        let url = cacheURL(root: root)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.records
    }

    public func record(
        patches: [DynamicBlockPatch],
        root: WorkspaceRoot,
        refreshedAt: Date = Date()
    ) throws {
        guard !patches.isEmpty else { return }

        let stamp = Self.timestamp(from: refreshedAt)
        let existing = (try? read(root: root)) ?? []
        var recordsByKey = Dictionary(uniqueKeysWithValues: existing.map { (Self.key(for: $0), $0) })
        for patch in patches {
            let record = DynamicBlockCacheRecord(
                sourcePath: patch.targetFilePath,
                commandHash: patch.commandHash,
                rawCommand: patch.rawCommand,
                rendererName: patch.command.rawValue,
                renderedOutputHash: ContentHasher.hash(patch.generatedMarkdown),
                refreshedAt: stamp
            )
            recordsByKey[Self.key(for: record)] = record
        }

        let records = recordsByKey.values.sorted {
            if $0.sourcePath == $1.sourcePath {
                return $0.commandHash < $1.commandHash
            }
            return $0.sourcePath < $1.sourcePath
        }
        let envelope = Envelope(version: 1, records: records)
        let data = try Self.encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else { return }
        let url = cacheURL(root: root)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try atomicWriter.write(json + "\n", to: url)
    }

    private func cacheURL(root: WorkspaceRoot) -> URL {
        root.expandedURL
            .appendingPathComponent(".daymark", isDirectory: true)
            .appendingPathComponent("dynamic-blocks.json")
    }

    private static func key(for record: DynamicBlockCacheRecord) -> String {
        "\(record.sourcePath)\n\(record.commandHash)"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static func timestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
