import Foundation
import os.log

/// Logging levels for the Gate/AI SDK.
///
/// Log levels control the verbosity of SDK logging output. Levels are ordered from
/// most verbose (`.debug`) to least verbose (`.off`).
///
/// ## Usage
///
/// Configure the log level when creating your ``GateAIConfiguration``:
///
/// ```swift
/// let configuration = try GateAIConfiguration(
///     baseURLString: "https://yourteam.in.gate-ai.net",
///     teamIdentifier: "ABCDE12345",
///     logLevel: .debug  // Enable debug logging
/// )
/// ```
public enum GateAILogLevel: String, CaseIterable, Comparable, Sendable {
    /// Detailed diagnostic information for debugging.
    ///
    /// Includes full request/response bodies and headers (with sensitive values redacted).
    case debug = "DEBUG"

    /// General informational messages about SDK operations.
    ///
    /// Includes key events like initialization, authentication success, and token refresh.
    case info = "INFO"

    /// Warning messages for potentially problematic situations.
    case warning = "WARNING"

    /// Error messages for failures and exceptional conditions.
    case error = "ERROR"

    /// Disables all logging from the SDK.
    case off = "OFF"

    public static func < (lhs: GateAILogLevel, rhs: GateAILogLevel) -> Bool {
        let order: [GateAILogLevel] = [.debug, .info, .warning, .error, .off]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// Protocol for implementing custom loggers.
///
/// The Gate/AI SDK uses this protocol for all logging operations. You can provide your own
/// implementation to integrate with your app's logging system.
///
/// The default implementation (``GateAILogger``) uses `os.log` for system integration.
public protocol GateAILoggerProtocol {
    /// Logs a message at the specified level.
    ///
    /// - Parameters:
    ///   - level: The log level.
    ///   - message: The message to log.
    ///   - file: The source file (automatically populated).
    ///   - function: The function name (automatically populated).
    ///   - line: The line number (automatically populated).
    func log(_ level: GateAILogLevel, _ message: String, file: String, function: String, line: Int)

    /// Logs an outgoing HTTP request.
    ///
    /// - Parameters:
    ///   - request: The URL request being sent.
    ///   - body: Optional request body data.
    func logRequest(_ request: URLRequest, body: Data?)

    /// Logs an HTTP response.
    ///
    /// - Parameters:
    ///   - response: The URL response received (if any).
    ///   - data: Optional response data.
    ///   - error: Optional error that occurred.
    func logResponse(_ response: URLResponse?, data: Data?, error: Error?)

    /// Logs a debug message.
    func debug(_ message: String, file: String, function: String, line: Int)

    /// Logs an informational message.
    func info(_ message: String, file: String, function: String, line: Int)

    /// Logs a warning message.
    func warning(_ message: String, file: String, function: String, line: Int)

    /// Logs an error message.
    func error(_ message: String, file: String, function: String, line: Int)
}

// MARK: - Protocol Extension with Default Implementations

extension GateAILoggerProtocol {
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }

    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }

    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }

    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
}

/// The default logger implementation for the Gate/AI SDK.
///
/// `GateAILogger` integrates with the system's unified logging system (`os.log`) and
/// provides structured, privacy-conscious logging.
///
/// ## Features
///
/// - Automatically redacts sensitive headers (Authorization, DPoP, API keys, cookies)
/// - Formats JSON responses for readability
/// - Includes file, function, and line number context
/// - Thread-safe logging operations
/// - Configurable log levels
///
/// ## Privacy
///
/// The logger automatically redacts sensitive information from logs, including:
/// - Authorization headers
/// - DPoP proofs
/// - API keys
/// - Cookies
///
/// ## Viewing Logs
///
/// Logs appear in:
/// - Xcode console during development
/// - Console.app (filter by subsystem: "com.gate-ai.sdk")
/// - System log archives
public final class GateAILogger: GateAILoggerProtocol, @unchecked Sendable {
    /// The shared singleton logger instance used by the SDK.
    public static let shared = GateAILogger()

    private let osLog = OSLog(subsystem: "com.gate-ai.sdk", category: "GateAI")
    private let queue = DispatchQueue(label: "com.gate-ai.logger", qos: .utility)
    private let _logLevel = OSAllocatedUnfairLock(initialState: GateAILogLevel.off)

    private init() {}

    /// Sets the minimum log level for output.
    ///
    /// Messages below this level will be filtered out. The log level is typically set
    /// automatically based on your ``GateAIConfiguration/logLevel``.
    ///
    /// - Parameter level: The minimum level to log.
    public func setLogLevel(_ level: GateAILogLevel) {
        _logLevel.withLock { $0 = level }
    }

    public func log(_ level: GateAILogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let currentLogLevel = _logLevel.withLock { $0 }
        guard level >= currentLogLevel && currentLogLevel != .off else { return }

        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let formattedMessage = "[\(level.rawValue)] \(fileName):\(line) \(function) - \(message)"

        queue.async {
            // Use os_log for system integration
            switch level {
            case .debug:
                // Debug messages can carry request/response payloads; mark them private so
                // they are not persisted in the clear in the unified log / sysdiagnose.
                os_log("%{private}@", log: self.osLog, type: .debug, formattedMessage)
            case .info:
                os_log("%{public}@", log: self.osLog, type: .info, formattedMessage)
            case .warning:
                os_log("%{public}@", log: self.osLog, type: .default, formattedMessage)
            case .error:
                os_log("%{public}@", log: self.osLog, type: .error, formattedMessage)
            case .off:
                break
            }

            // Note: os_log output appears in Xcode console and Console.app
            // No need for additional print() as it would create duplicates
        }
    }

    public func logRequest(_ request: URLRequest, body: Data? = nil) {
        let currentLogLevel = _logLevel.withLock { $0 }
        guard currentLogLevel <= .debug else { return }

        var logMessage = "🔵 HTTP REQUEST\n"
        logMessage += "URL: \(request.url?.absoluteString ?? "nil")\n"
        logMessage += "Method: \(request.httpMethod ?? "nil")\n"

        if let headers = request.allHTTPHeaderFields, !headers.isEmpty {
            logMessage += "Headers:\n"
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                // Redact sensitive headers
                let redactedValue = shouldRedactHeader(key) ? "[REDACTED]" : value
                logMessage += "  \(key): \(redactedValue)\n"
            }
        }

        if let body = body {
            if let bodyString = String(data: body, encoding: .utf8) {
                logMessage += "Body: \(redactSensitiveBody(bodyString))"
            } else {
                logMessage += "Body: <\(body.count) bytes of binary data>"
            }
        }

        log(.debug, logMessage)
    }

    public func logResponse(_ response: URLResponse?, data: Data?, error: Error?) {
        let currentLogLevel = _logLevel.withLock { $0 }
        guard currentLogLevel <= .debug else { return }

        var logMessage = ""

        if let error = error {
            logMessage += "🔴 HTTP ERROR\n"
            logMessage += "Error: \(error.localizedDescription)\n"
            if let urlError = error as? URLError {
                logMessage += "Code: \(urlError.code.rawValue)\n"
            }
        } else {
            logMessage += "🟢 HTTP RESPONSE\n"
        }

        if let httpResponse = response as? HTTPURLResponse {
            logMessage += "Status: \(httpResponse.statusCode)\n"
            logMessage += "URL: \(httpResponse.url?.absoluteString ?? "nil")\n"

            if !httpResponse.allHeaderFields.isEmpty {
                logMessage += "Headers:\n"
                for (key, value) in httpResponse.allHeaderFields.sorted(by: { "\($0.key)" < "\($1.key)" }) {
                    let keyString = "\(key)"
                    let valueString = "\(value)"
                    let redactedValue = shouldRedactHeader(keyString) ? "[REDACTED]" : valueString
                    logMessage += "  \(keyString): \(redactedValue)\n"
                }
            }
        }

        if let data = data {
            if let responseString = String(data: data, encoding: .utf8) {
                // Try to pretty-print JSON
                if let jsonData = responseString.data(using: .utf8),
                   let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
                   let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                   let prettyString = String(data: prettyData, encoding: .utf8) {
                    logMessage += "Body:\n\(redactSensitiveBody(prettyString))"
                } else {
                    logMessage += "Body: \(redactSensitiveBody(responseString))"
                }
            } else {
                logMessage += "Body: <\(data.count) bytes of binary data>"
            }
        }

        let level: GateAILogLevel = error != nil ? .error : .debug
        log(level, logMessage)
    }

    private func shouldRedactHeader(_ headerName: String) -> Bool {
        let sensitiveHeaders = [
            "authorization",
            "dpop",
            "x-api-key",
            "cookie",
            "set-cookie"
        ]
        return sensitiveHeaders.contains(headerName.lowercased())
    }

    /// Redacts credential values from a request/response body before it is logged.
    /// The `/token` request body carries `dev_token`, and its response carries
    /// `access_token`; without this these secrets would land in the unified log.
    private func redactSensitiveBody(_ body: String) -> String {
        let sensitiveKeys = [
            "dev_token",
            "access_token",
            "refresh_token",
            "dpop",
            "client_secret",
            "assertion"
        ]
        var result = body
        for key in sensitiveKeys {
            // JSON: "key": "value"
            result = result.replacingOccurrences(
                of: "(\"\(key)\"\\s*:\\s*)\"[^\"]*\"",
                with: "$1\"[REDACTED]\"",
                options: [.regularExpression, .caseInsensitive]
            )
            // form-urlencoded: key=value
            result = result.replacingOccurrences(
                of: "(\(key)=)[^&\\s]*",
                with: "$1[REDACTED]",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }
}

