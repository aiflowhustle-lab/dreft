import Foundation

enum DreftAccessState: String, Codable, Equatable {
    /// Active subscription, trial, grace period, billing retry, or legacy user.
    case fullAccess
    /// Never subscribed — read, browse, and export only; all writes require Pro.
    case locked
    /// Trial or subscription ended — read and export only.
    case readOnly
}
