import Foundation

struct VaultAlert: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct VaultScanIssue: Equatable {
    let path: String
    let message: String
}

struct VaultBatchWriteResult {
    var failures: [(path: String, error: Error)] = []

    var hasFailures: Bool { !failures.isEmpty }

    var summaryMessage: String {
        guard hasFailures else { return "" }
        var lines = failures.prefix(4).map { "\($0.path): \($0.error.localizedDescription)" }
        if failures.count > 4 {
            lines.append("…and \(failures.count - 4) more.")
        }
        return lines.joined(separator: "\n")
    }

    static func combined(_ results: VaultBatchWriteResult...) -> VaultBatchWriteResult {
        VaultBatchWriteResult(failures: results.flatMap(\.failures))
    }
}

enum VaultErrorMessages {
    static let noActiveVault = "Choose or create a vault before working with files."
}

enum VaultPathPolicy {
    /// Returns a user-facing reason when `url` should not be opened as a vault root.
    static func unsuitableVaultMessage(for url: URL) -> String? {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        #if os(iOS)
        if VaultSecurityAccess.isInsideAppContainer(standardized) {
            return nil
        }
        #endif

        let home = NSHomeDirectory()

        let blockedPaths = [
            home,
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Downloads",
            "\(home)/Library",
            "/",
            "/Users",
            "/System",
            "/Library",
            "/Applications",
            "/private/var"
        ]

        if blockedPaths.contains(path) {
            let name = url.lastPathComponent
            return """
            “\(name)” is too broad to use as a vault. Dreft would try to index every folder inside it.

            Open a dedicated folder instead (for example Documents/valeria), or use Create new vault.
            """
        }
        return nil
    }
}
