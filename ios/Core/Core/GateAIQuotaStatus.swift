import Foundation

/// The device's remaining usage quota, reported by the Gate/AI proxy on successful responses.
///
/// When a gate has device usage windows configured, successful proxied responses include
/// quota headers describing the tightest window per metric:
///
/// - `X-Quota-Requests-Remaining`: Remaining requests (integer)
/// - `X-Quota-Requests-Limit`: The request budget of the binding window (integer)
/// - `X-Quota-Requests-Reset`: When the binding window for requests resets (ISO8601)
/// - `X-Quota-Tokens-Remaining`: Remaining tokens (integer)
/// - `X-Quota-Tokens-Limit`: The token budget of the binding window (integer)
/// - `X-Quota-Tokens-Reset`: When the binding window for tokens resets (ISO8601)
///
/// Use ``HTTPURLResponse/gateAIQuotaStatus`` to read the parsed status from a proxy response:
///
/// ```swift
/// let (data, response) = try await client.performProxyRequest(
///     path: "openai/chat/completions",
///     method: .post,
///     body: requestBody,
///     additionalHeaders: ["Content-Type": "application/json"]
/// )
///
/// if let quota = response.gateAIQuotaStatus, let fraction = quota.requestsUsedFraction {
///     ProgressView(value: fraction) // e.g. a usage meter in your UI
/// }
/// ```
///
/// All fields are optional; a header the server did not send (or that could not be parsed)
/// yields `nil` for the corresponding field.
public struct GateAIQuotaStatus: Sendable, Equatable {
    /// The number of requests remaining in the tightest configured window, if reported.
    public let requestsRemaining: Int?

    /// The request budget of the binding window, if reported.
    public let requestsLimit: Int?

    /// The number of tokens remaining in the tightest configured window, if reported.
    public let tokensRemaining: Int?

    /// The token budget of the binding window, if reported.
    public let tokensLimit: Int?

    /// When the binding window for requests resets and request capacity returns, if reported.
    public let requestsResetAt: Date?

    /// When the binding window for tokens resets and token capacity returns, if reported.
    public let tokensResetAt: Date?

    /// Requests already used in the binding window (`limit − remaining`), when both are reported.
    public var requestsUsed: Int? {
        guard let requestsLimit, let requestsRemaining else { return nil }
        return max(0, requestsLimit - requestsRemaining)
    }

    /// Tokens already used in the binding window (`limit − remaining`), when both are reported.
    public var tokensUsed: Int? {
        guard let tokensLimit, let tokensRemaining else { return nil }
        return max(0, tokensLimit - tokensRemaining)
    }

    /// Fraction of the request budget consumed (0...1), suitable for a progress bar.
    public var requestsUsedFraction: Double? {
        guard let requestsLimit, requestsLimit > 0, let used = requestsUsed else { return nil }
        return min(1, Double(used) / Double(requestsLimit))
    }

    /// Fraction of the token budget consumed (0...1), suitable for a progress bar.
    public var tokensUsedFraction: Double? {
        guard let tokensLimit, tokensLimit > 0, let used = tokensUsed else { return nil }
        return min(1, Double(used) / Double(tokensLimit))
    }

    /// Creates a quota status with the given values.
    ///
    /// - Parameters:
    ///   - requestsRemaining: Remaining requests, or `nil`.
    ///   - requestsLimit: The binding window's request budget, or `nil`.
    ///   - tokensRemaining: Remaining tokens, or `nil`.
    ///   - tokensLimit: The binding window's token budget, or `nil`.
    ///   - requestsResetAt: When the binding window for requests resets, or `nil`.
    ///   - tokensResetAt: When the binding window for tokens resets, or `nil`.
    public init(
        requestsRemaining: Int?,
        requestsLimit: Int? = nil,
        tokensRemaining: Int?,
        tokensLimit: Int? = nil,
        requestsResetAt: Date?,
        tokensResetAt: Date?
    ) {
        self.requestsRemaining = requestsRemaining
        self.requestsLimit = requestsLimit
        self.tokensRemaining = tokensRemaining
        self.tokensLimit = tokensLimit
        self.requestsResetAt = requestsResetAt
        self.tokensResetAt = tokensResetAt
    }

    /// Parses a quota status from a dictionary of response header fields.
    ///
    /// Header names are matched case-insensitively. Returns `nil` when none of the
    /// `X-Quota-*` headers are present.
    ///
    /// - Parameter headers: The HTTP response header fields.
    public init?(headers: [String: String]) {
        let requestsRaw = headers[caseInsensitive: "X-Quota-Requests-Remaining"]
        let requestsLimitRaw = headers[caseInsensitive: "X-Quota-Requests-Limit"]
        let tokensRaw = headers[caseInsensitive: "X-Quota-Tokens-Remaining"]
        let tokensLimitRaw = headers[caseInsensitive: "X-Quota-Tokens-Limit"]
        let requestsResetRaw = headers[caseInsensitive: "X-Quota-Requests-Reset"]
        let tokensResetRaw = headers[caseInsensitive: "X-Quota-Tokens-Reset"]

        guard requestsRaw != nil || tokensRaw != nil || requestsLimitRaw != nil
            || tokensLimitRaw != nil || requestsResetRaw != nil || tokensResetRaw != nil else {
            return nil
        }

        self.requestsRemaining = requestsRaw.flatMap { Int($0) }
        self.requestsLimit = requestsLimitRaw.flatMap { Int($0) }
        self.tokensRemaining = tokensRaw.flatMap { Int($0) }
        self.tokensLimit = tokensLimitRaw.flatMap { Int($0) }
        self.requestsResetAt = requestsResetRaw.flatMap { ISO8601DateParsing.date(from: $0) }
        self.tokensResetAt = tokensResetRaw.flatMap { ISO8601DateParsing.date(from: $0) }
    }

    /// Parses a quota status from an HTTP response.
    ///
    /// Returns `nil` when none of the `X-Quota-*` headers are present.
    ///
    /// - Parameter response: The HTTP response returned by the proxy.
    public init?(response: HTTPURLResponse) {
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String {
                headers[key] = value
            }
        }
        self.init(headers: headers)
    }
}

extension HTTPURLResponse {
    /// The device usage quota reported by the Gate/AI proxy, if present.
    ///
    /// Parses the `X-Quota-Requests-Remaining`, `X-Quota-Requests-Limit`,
    /// `X-Quota-Requests-Reset`, `X-Quota-Tokens-Remaining`, `X-Quota-Tokens-Limit`,
    /// and `X-Quota-Tokens-Reset` headers (case-insensitively). Returns `nil` when the response
    /// carries none of them — for example when the gate has no device usage windows configured.
    public var gateAIQuotaStatus: GateAIQuotaStatus? {
        GateAIQuotaStatus(response: self)
    }
}
