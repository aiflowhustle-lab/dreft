import Foundation
#if os(macOS)
import CoreServices
#endif

/// Watches the active vault folder and debounces external file changes.
final class VaultFilesystemWatcher {
    private var onChange: (() -> Void)?
    private var debounceTask: Task<Void, Never>?
    private let debounceMilliseconds: UInt64 = 450

    #if os(macOS)
    private var stream: FSEventStreamRef?
    private var watchedPath: String?
    #endif

    func start(watching vaultURL: URL, onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange

        #if os(macOS)
        watchedPath = vaultURL.path
        let pathsToWatch = [vaultURL.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info else { return }
                let watcher = Unmanaged<VaultFilesystemWatcher>.fromOpaque(info).takeUnretainedValue()
                watcher.handleFSEvents(
                    eventCount: numEvents,
                    paths: eventPaths,
                    flags: eventFlags
                )
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        #else
        _ = vaultURL
        #endif
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        onChange = nil

        #if os(macOS)
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        watchedPath = nil
        #endif
    }

    #if os(macOS)
    private func handleFSEvents(
        eventCount: Int,
        paths: UnsafeRawPointer,
        flags: UnsafePointer<FSEventStreamEventFlags>
    ) {
        _ = flags
        guard eventCount > 0 else { return }

        let pathArray = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as NSArray
        for index in 0..<eventCount {
            guard let path = pathArray[index] as? String else { continue }
            if path.hasSuffix(".dreft") || path.contains("/.dreft/") {
                continue
            }
            scheduleCallback()
            return
        }
    }
    #endif

    private func scheduleCallback() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.debounceMilliseconds ?? 450) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
}
