import Foundation
import CoreServices

/// Native recursive file watcher over one or more directory trees, built on FSEvents.
/// Daymark uses it so edits made outside the app (terminal, Codex, Cursor) are noticed and
/// reconciled. Events are delivered on a private dispatch queue; callers hop to their own
/// isolation (for example the main actor) inside the callback.
///
/// `@unchecked Sendable`: the only mutable state is the FSEvents stream handle, which is
/// created, started, and stopped on `queue`. The escaping callback is invoked only on that
/// same queue. There is no cross-thread mutation to guard.
public final class FileWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let onChange: ([String]) -> Void
    private let queue = DispatchQueue(label: "com.daymark.filewatcher")
    private var stream: FSEventStreamRef?

    /// - Parameters:
    ///   - paths: directory roots to watch recursively.
    ///   - latency: coalescing window in seconds before events are delivered.
    ///   - onChange: called with the changed file paths. Invoked on a private queue.
    public init(paths: [String], latency: TimeInterval = 0.15, onChange: @escaping ([String]) -> Void) {
        self.paths = paths
        self.latency = latency
        self.onChange = onChange
    }

    deinit {
        teardown()
    }

    public func start() {
        queue.async { [weak self] in self?.startOnQueue() }
    }

    public func stop() {
        queue.sync { teardown() }
    }

    private func startOnQueue() {
        guard stream == nil, !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // C function pointer: no captures allowed, so `self` arrives via the context `info`.
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info, count > 0 else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(eventPaths, to: NSArray.self) as? [String]) ?? []
            if !changed.isEmpty {
                watcher.onChange(changed)
            }
        }

        // UseCFTypes makes `eventPaths` a CFArray<CFString>; without it the callback
        // receives a C `char**`, which the NSArray bridge below cannot read. We do not
        // set IgnoreSelf: the app's own atomic saves are filtered by a content guard in
        // the caller, and ignoring self-events would also break same-process testing.
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func teardown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
