import Foundation

/// Errors that can occur when using the Gate/AI SDK.
///
/// All errors thrown by the SDK are instances of `GateAIError`. The error provides
/// localized descriptions suitable for logging or displaying to users.
///
/// ## Topics
///
/// ### Configuration Errors
///
/// - ``configuration(_:)``
///
/// ### Attestation Errors
///
/// - ``attestationUnavailable``
/// - ``attestationFailed(_:)``
/// - ``secureEnclaveUnavailable``
///
/// ### Network Errors
///
/// - ``network(underlying:)``
/// - ``server(statusCode:error:headers:)``
/// - ``decoding(underlying:)``
/// - ``invalidResponse``
///
/// ### Token Errors
///
/// - ``tokenMissing``
public enum GateAIError: Error, LocalizedError, Sendable {
    /// A configuration error occurred.
    ///
    /// This error is thrown when invalid configuration values are provided, such as:
    /// - An empty bundle identifier
    /// - An invalid team identifier format
    /// - An invalid base URL
    ///
    /// - Parameter message: A detailed description of the configuration problem.
    case configuration(String)

    /// App Attest is not available on this device.
    ///
    /// This error occurs when attempting to use App Attest on a device that doesn't support it,
    /// or in the simulator without a development token configured.
    case attestationUnavailable

    /// Device attestation failed.
    ///
    /// This error occurs when the App Attest process fails, such as:
    /// - The attestation key is invalid
    /// - The server rejects the attestation
    /// - The device is not eligible for attestation
    ///
    /// - Parameter message: A detailed description of the attestation failure.
    case attestationFailed(String)

    /// The Secure Enclave is not available on this device.
    ///
    /// This error is thrown when attempting to create cryptographic keys in the Secure Enclave
    /// on a device that doesn't have one.
    case secureEnclaveUnavailable

    /// A network request failed.
    ///
    /// This error wraps underlying network errors such as connection failures, timeouts,
    /// or other URLSession errors.
    ///
    /// - Parameter underlying: The original error from the network layer.
    case network(underlying: Error)

    /// The server returned an error response.
    ///
    /// This error is thrown when the Gate/AI server returns a non-success HTTP status code.
    /// It includes the status code, optional structured error information, and response headers.
    ///
    /// - Parameters:
    ///   - statusCode: The HTTP status code (e.g., 401, 403, 429, 500).
    ///   - error: Optional structured error information from the server.
    ///   - headers: The HTTP response headers, useful for extracting values like `DPoP-Nonce`.
    case server(statusCode: Int, error: ServerErrorResponse?, headers: [String: String]?)

    /// Failed to decode the server response.
    ///
    /// This error occurs when the server returns data that cannot be decoded into the expected type.
    ///
    /// - Parameter underlying: The original decoding error.
    case decoding(underlying: Error)

    /// The server returned an invalid or unexpected response.
    ///
    /// This error is thrown when the response cannot be cast to `HTTPURLResponse` or
    /// is otherwise malformed.
    case invalidResponse

    /// No access token is available.
    ///
    /// This error occurs when attempting to use an access token that hasn't been acquired yet.
    case tokenMissing

    public var errorDescription: String? {
        switch self {
        case .configuration(let message):
            return message
        case .attestationUnavailable:
            return "App Attest is not supported on this device."
        case .attestationFailed(let message):
            return "Device attestation failed: \(message)"
        case .secureEnclaveUnavailable:
            return "Secure Enclave is not available."
        case .network(let underlying):
            return "Network request failed: \(underlying.localizedDescription)"
        case .server(let status, let error, _):
            if let error {
                return "Server returned \(status): \(error.errorDescription ?? error.error)"
            }
            return "Server returned status code \(status)."
        case .decoding(let underlying):
            return "Failed to decode server response: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .tokenMissing:
            return "No access token is available."
        }
    }
}

/// Structured error information returned by the Gate/AI server.
///
/// When the server returns an error response, it may include structured information
/// with an error code and optional human-readable description.
///
/// Common error codes include:
/// - `invalid_request`: The request was malformed or missing required parameters
/// - `invalid_token`: The access token is expired or invalid
/// - `device_blocked`: The device has been blocked by the tenant
/// - `rate_limited`: Too many requests have been made
/// - `nonce_expired`: The DPoP nonce has expired
public struct ServerErrorResponse: Codable, Sendable {
    /// The error code identifying the type of error.
    public let error: String

    /// An optional human-readable description of the error.
    public let errorDescription: String?

    /// The rejection code for `rate_limited` errors (e.g. `device_daily_requests_exceeded`).
    public let code: String?

    /// A human-readable message for `rate_limited` errors.
    public let message: String?

    /// The raw usage window for device-window `rate_limited` errors
    /// (`daily`, `monthly`, `rolling_30d`, or `cycle`).
    public let window: String?

    /// The configured limit for device-window `rate_limited` errors.
    public let limit: Int?

    /// Usage counted against the window (excluding the rejected request)
    /// for device-window `rate_limited` errors.
    public let used: Int?

    /// The raw ISO8601 timestamp at which capacity returns, for device-window `rate_limited` errors.
    public let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case code
        case message
        case window
        case limit
        case used
        case resetsAt = "resets_at"
    }
}
