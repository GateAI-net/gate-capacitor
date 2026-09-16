import Foundation

/// Structured details from a Gate/AI `429 rate_limited` response.
///
/// When a proxied request is rejected with HTTP 429, the proxy returns a JSON body describing
/// which limit was hit. Use ``parse(from:)`` to read it from the response data returned by
/// ``GateAIClient/performProxyRequest(path:method:body:additionalHeaders:)``:
///
/// ```swift
/// let (data, response) = try await client.performProxyRequest(
///     path: "openai/chat/completions",
///     method: .post,
///     body: requestBody,
///     additionalHeaders: ["Content-Type": "application/json"]
/// )
///
/// if response.statusCode == 429, let info = GateAIRateLimitInfo.parse(from: data) {
///     print("Rate limited (\(info.code)): \(info.message)")
///     if let resetsAt = info.resetsAt {
///         print("Capacity returns at \(resetsAt)")
///     }
/// }
/// ```
///
/// The ``window``, ``limit``, ``used``, and ``resetsAt`` fields are present only for
/// device-window rejections (codes such as `device_daily_requests_exceeded`); other
/// rejections (e.g. `global_rpm_exceeded`) carry only ``code`` and ``message``.
/// A `retry-after` response header may accompany some rejections.
public struct GateAIRateLimitInfo: Sendable, Equatable {
    /// The device usage window that rejected the request.
    ///
    /// Unknown values decode safely into ``unknown(_:)`` so future windows added by the
    /// server never break parsing; the raw value is preserved.
    public enum Window: Sendable, Equatable, Hashable {
        /// A calendar-day window (resets at midnight UTC).
        case daily

        /// A calendar-month window.
        case monthly

        /// A rolling 30-day window (capacity returns as the oldest usage ages out).
        case rolling30d

        /// A billing-cycle window anchored to ``GateAIClient/quotaAnchorDay``.
        case cycle

        /// A window value this SDK version doesn't know about. The raw server value is preserved.
        case unknown(String)

        /// Creates a window from its raw server value, mapping unrecognized values to ``unknown(_:)``.
        public init(rawValue: String) {
            switch rawValue {
            case "daily": self = .daily
            case "monthly": self = .monthly
            case "rolling_30d": self = .rolling30d
            case "cycle": self = .cycle
            default: self = .unknown(rawValue)
            }
        }

        /// The raw server value for this window (e.g. `"daily"`, `"rolling_30d"`).
        public var rawValue: String {
            switch self {
            case .daily: return "daily"
            case .monthly: return "monthly"
            case .rolling30d: return "rolling_30d"
            case .cycle: return "cycle"
            case .unknown(let rawValue): return rawValue
            }
        }
    }

    /// The rejection code identifying which limit was hit (e.g. `device_daily_requests_exceeded`).
    public let code: String

    /// A human-readable description of the rejection.
    public let message: String

    /// The device usage window that rejected the request. Present only for device-window rejections.
    public let window: Window?

    /// The configured limit for the rejecting window. Present only for device-window rejections.
    public let limit: Int?

    /// Usage counted against the window, excluding the rejected request.
    /// Present only for device-window rejections.
    public let used: Int?

    /// When capacity returns (for rolling windows, when the oldest usage ages out).
    /// Present only for device-window rejections.
    public let resetsAt: Date?

    /// Creates a rate-limit info value with the given fields.
    public init(code: String, message: String, window: Window?, limit: Int?, used: Int?, resetsAt: Date?) {
        self.code = code
        self.message = message
        self.window = window
        self.limit = limit
        self.used = used
        self.resetsAt = resetsAt
    }

    /// Parses rate-limit details from a 429 response body.
    ///
    /// - Parameter body: The response body data returned alongside the 429 status.
    ///
    /// - Returns: The parsed info, or `nil` when the body is not a parseable
    ///   `rate_limited` error (e.g. an upstream provider's own 429 body).
    public static func parse(from body: Data) -> GateAIRateLimitInfo? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              payload.error == "rate_limited",
              let code = payload.code else {
            return nil
        }

        return GateAIRateLimitInfo(
            code: code,
            message: payload.message ?? "",
            window: payload.window.map(Window.init(rawValue:)),
            limit: payload.limit,
            used: payload.used,
            resetsAt: payload.resetsAt.flatMap { ISO8601DateParsing.date(from: $0) }
        )
    }

    private struct Payload: Decodable {
        let error: String
        let code: String?
        let message: String?
        let window: String?
        let limit: Int?
        let used: Int?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case error
            case code
            case message
            case window
            case limit
            case used
            case resetsAt = "resets_at"
        }
    }
}

extension GateAIError {
    /// Structured rate-limit details when this error is a `429 rate_limited` server response.
    ///
    /// Returns a value only for ``GateAIError/server(statusCode:error:headers:)`` errors with
    /// status code 429 whose body was a parseable `rate_limited` error. Returns `nil` otherwise.
    public var rateLimitInfo: GateAIRateLimitInfo? {
        guard case let .server(statusCode, serverError, _) = self,
              statusCode == 429,
              let serverError,
              serverError.error == "rate_limited",
              let code = serverError.code else {
            return nil
        }

        return GateAIRateLimitInfo(
            code: code,
            message: serverError.message ?? "",
            window: serverError.window.map(GateAIRateLimitInfo.Window.init(rawValue:)),
            limit: serverError.limit,
            used: serverError.used,
            resetsAt: serverError.resetsAt.flatMap { ISO8601DateParsing.date(from: $0) }
        )
    }
}
