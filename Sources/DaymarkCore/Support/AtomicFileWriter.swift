import Foundation

public struct AtomicFileWriter {
    public init() {}

    /// Writes `contents` to `url` atomically, creating intermediate directories as needed.
    /// The write goes to a temp file and is renamed into place, so readers never see a
    /// partially written note and a crash mid-write cannot truncate the existing file.
    public func write(_ contents: String, to url: URL, fileManager: FileManager = .default) throws {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Data(contents.utf8).write(to: url, options: [.atomic])
    }
}
