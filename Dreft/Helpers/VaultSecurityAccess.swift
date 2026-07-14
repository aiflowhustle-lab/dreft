import Foundation

/// Resolves sandbox-safe vault URLs and keeps security-scoped access alive.
enum VaultSecurityAccess {
    private static var activeURLs: [String: URL] = [:]

    static func resolvedURL(for vault: WorkspaceVault) -> URL {
        if let cached = activeURLs[vault.id] {
            return cached
        }

        if let bookmark = vault.securityScopedBookmark,
           let url = resolveBookmark(bookmark) {
            _ = url.startAccessingSecurityScopedResource()
            activeURLs[vault.id] = url.standardizedFileURL
            return url
        }

        let pathURL = URL(fileURLWithPath: vault.path, isDirectory: true).standardizedFileURL
        if isInsideAppContainer(pathURL) {
            activeURLs[vault.id] = pathURL
            return pathURL
        }

        if pathURL.startAccessingSecurityScopedResource() {
            activeURLs[vault.id] = pathURL
        }
        return pathURL
    }

    static func createBookmark(for url: URL) -> Data? {
        let standardized = url.standardizedFileURL
        #if os(macOS)
        return try? standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try? standardized.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }

    static func beginAccess(vaultID: String, url: URL, bookmark: Data? = nil) {
        let standardized = url.standardizedFileURL
        if shouldPersistBookmark(for: standardized) || bookmark != nil {
            _ = standardized.startAccessingSecurityScopedResource()
        }
        activeURLs[vaultID] = standardized
    }

    static func restoreAccess(for vaults: [WorkspaceVault]) {
        for vault in vaults {
            _ = resolvedURL(for: vault)
        }
    }

    static func resolveBookmark(_ data: Data) -> URL? {
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        #else
        let options: URL.BookmarkResolutionOptions = [.withoutUI]
        #endif
        return try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    @discardableResult
    static func beginParentAccess(bookmark: Data) -> URL? {
        guard let url = resolveBookmark(bookmark) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    static func shouldPersistBookmark(for url: URL) -> Bool {
        !isInsideAppContainer(url)
    }

    static func isInsideAppContainer(_ url: URL) -> Bool {
        let path = canonicalSandboxPath(url)
        let containerRoots = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
            FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
        ].map { canonicalSandboxPath($0) }
        return containerRoots.contains { path.hasPrefix($0) }
    }

    /// Normalizes sandbox paths so `/private/var/...` and `/var/...` compare equal on iOS.
    static func canonicalSandboxPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.hasPrefix("/private") {
            path = String(path.dropFirst("/private".count))
        }
        return path
    }

    static func refreshBookmarkIfNeeded(for vault: inout WorkspaceVault, url: URL) {
        guard shouldPersistBookmark(for: url) else {
            vault.securityScopedBookmark = nil
            return
        }
        if vault.securityScopedBookmark == nil {
            vault.securityScopedBookmark = createBookmark(for: url)
        }
    }
}
