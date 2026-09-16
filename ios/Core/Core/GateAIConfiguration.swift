import Foundation

public struct GateAIConfiguration: Sendable {
    public let baseURL: URL
    public let bundleIdentifier: String
    public let teamIdentifier: String
    public let developmentToken: String?
    public let logLevel: GateAILogLevel

    /// Primary initializer with URL validation
    ///
    /// - Parameters:
    ///   - baseURL: The Gate/AI tenant URL (e.g., https://yourteam.in.gate-ai.net)
    ///   - bundleIdentifier: Your app's bundle identifier. Must not be empty.
    ///   - teamIdentifier: Your Apple Team ID. Must be exactly 10 alphanumeric characters (e.g., "ABCDE12345").
    ///   - logLevel: Logging verbosity level. Defaults to `.off`.
    /// - Throws: `GateAIError.configuration` if any validation fails.
    public init(
        baseURL: URL,
        bundleIdentifier: String,
        teamIdentifier: String,
        logLevel: GateAILogLevel = .off
    ) throws {
        // Validate bundle identifier
        guard !bundleIdentifier.isEmpty else {
            throw GateAIError.configuration("bundleIdentifier cannot be empty.")
        }
        try Self.validateTeamIdentifier(teamIdentifier)

        // Enforce TLS: bearer tokens and DPoP proofs must never travel in cleartext.
        // Allow plain http only for localhost, to support local proxy development.
        let scheme = baseURL.scheme?.lowercased()
        let host = baseURL.host?.lowercased()
        let isLocalHTTP = scheme == "http" && (host == "localhost" || host == "127.0.0.1")
        guard scheme == "https" || isLocalHTTP else {
            throw GateAIError.configuration("baseURL must use https. Provided scheme: '\(baseURL.scheme ?? "none")'.")
        }

        self.baseURL = baseURL
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.developmentToken = Self.resolveDevelopmentToken()
        self.logLevel = logLevel
    }

    /// Convenience initializer that accepts a String for the base URL
    ///
    /// - Parameters:
    ///   - baseURLString: The Gate/AI tenant URL as a string (e.g., "https://yourteam.in.gate-ai.net")
    ///   - bundleIdentifier: Your app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier` if available.
    ///   - teamIdentifier: Your Apple Team ID. Must be exactly 10 alphanumeric characters (e.g., "ABCDE12345").
    ///   - logLevel: Logging verbosity level. Defaults to `.off`.
    /// - Throws: `GateAIError.configuration` if the URL is invalid or any validation fails.
    public init(
        baseURLString: String,
        bundleIdentifier: String? = nil,
        teamIdentifier: String,
        logLevel: GateAILogLevel = .off
    ) throws {
        guard let url = URL(string: baseURLString) else {
            throw GateAIError.configuration("Invalid base URL: '\(baseURLString)'")
        }

        let resolvedBundleID: String
        if let bundleIdentifier = bundleIdentifier {
            resolvedBundleID = bundleIdentifier
        } else if let mainBundleID = Bundle.main.bundleIdentifier {
            resolvedBundleID = mainBundleID
        } else {
            throw GateAIError.configuration("bundleIdentifier is required and could not be automatically detected from Bundle.main")
        }

        try self.init(
            baseURL: url,
            bundleIdentifier: resolvedBundleID,
            teamIdentifier: teamIdentifier,
            logLevel: logLevel
        )
    }

    /// Validates that a team identifier matches the expected Apple Team ID format
    ///
    /// Apple Team IDs are exactly 10 alphanumeric characters, typically uppercase.
    /// Examples: "ABCDE12345", "VY76D5S364"
    ///
    /// - Parameter teamIdentifier: The team identifier to validate
    /// - Throws: `GateAIError.configuration` if the format is invalid
    private static func validateTeamIdentifier(_ teamIdentifier: String) throws {
        guard teamIdentifier.count == 10 else {
            throw GateAIError.configuration(
                "teamIdentifier must be exactly 10 characters. Provided: '\(teamIdentifier)' (\(teamIdentifier.count) characters)"
            )
        }

        let alphanumericCharacterSet = CharacterSet.alphanumerics
        guard teamIdentifier.unicodeScalars.allSatisfy({ alphanumericCharacterSet.contains($0) }) else {
            throw GateAIError.configuration(
                "teamIdentifier must contain only alphanumeric characters (A-Z, 0-9). Provided: '\(teamIdentifier)'"
            )
        }
    }

    private static func resolveDevelopmentToken() -> String? {
        guard Platform.isSimulator else {
            return nil
        }
        let envToken = ProcessInfo.processInfo.environment["GATE_AI_DEV_TOKEN"]
        if let envToken, !envToken.isEmpty {
            return envToken
        }

        return nil
    }

    private static func resolveTeamIdentifier(_ provided: String?) throws -> String {
        fatalError("resolveTeamIdentifier should not be called when teamIdentifier is required")
    }
}
