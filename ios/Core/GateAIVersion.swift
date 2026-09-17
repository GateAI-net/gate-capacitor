import Foundation

/// The Gate/AI SDK version.
///
/// Sent as the `X-SDK-Version` analytics header on all authenticated requests.
///
/// - Important: This value must be bumped on every release.
public enum GateAIVersion {
    /// The current SDK version string.
    public static let current = "1.2.0"
}
