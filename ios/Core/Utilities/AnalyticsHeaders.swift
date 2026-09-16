import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Helper to generate analytics headers for Gate/AI requests.
///
/// These headers provide contextual information about the app and device for analytics purposes.
struct AnalyticsHeaders {
    /// The user status set by the application (e.g., "free", "premium", "trial").
    let userStatus: String?

    /// The user plan tier set by the application (e.g., "free", "pro"). Matched case-sensitively
    /// against Portal-configured per-tier usage limits.
    var userTier: String? = nil

    /// The opaque user identifier set by the application (e.g., an account ID). Never PII.
    let userIdentifier: String?

    /// The app feature tag set by the application (e.g., "chat", "summarize").
    let appFeature: String?

    /// The quota anchor day-of-month (1–31) set by the application. Values outside 1–31 are dropped.
    var quotaAnchorDay: Int? = nil

    /// Generates a dictionary of analytics headers.
    ///
    /// - Returns: A dictionary with X-prefixed analytics headers.
    func headers() async -> [String: String] {
        var headers: [String: String] = [:]

        // X-Client-Locale: Language and country code (e.g., "es-MX", "en-US")
        if let locale = Self.clientLocale() {
            headers["X-Client-Locale"] = locale
        }

        // X-App-Version: App version from bundle (e.g., "1.0.2")
        if let appVersion = Self.appVersion() {
            headers["X-App-Version"] = appVersion
        }

        // X-OS-Version: iOS version (e.g., "17.2")
        if let osVersion = await Self.osVersion() {
            headers["X-OS-Version"] = osVersion
        }

        // X-User-Status: Custom status provided by developer
        if let userStatus = userStatus {
            headers["X-User-Status"] = userStatus
        }

        // X-User-Tier: Plan tier provided by developer; enforcement key for per-tier usage limits
        if let userTier = userTier {
            headers["X-User-Tier"] = userTier
        }

        // X-Device-Identifier: Vendor identifier (UUID string)
        if let deviceId = await Self.deviceIdentifier() {
            headers["X-Device-Identifier"] = deviceId
        }

        // X-Device-Type: Device model (e.g., "iPhone", "iPad")
        if let deviceType = await Self.deviceType() {
            headers["X-Device-Type"] = deviceType
        }

        // X-User-Identifier: Opaque user/account ID provided by developer
        if let userIdentifier = userIdentifier {
            headers["X-User-Identifier"] = userIdentifier
        }

        // X-App-Feature: Feature tag provided by developer (e.g., "chat", "summarize")
        if let appFeature = appFeature {
            headers["X-App-Feature"] = appFeature
        }

        // X-Quota-Anchor-Day: Billing-cycle anchor day provided by developer (1–31).
        // Out-of-range values are dropped; the Proxy also ignores invalid values.
        if let quotaAnchorDay = quotaAnchorDay, (1...31).contains(quotaAnchorDay) {
            headers["X-Quota-Anchor-Day"] = String(quotaAnchorDay)
        }

        // X-Environment: Build environment ("development", "testflight", "production")
        headers["X-Environment"] = Self.environment()

        // X-Device-Model: Hardware model identifier (e.g., "iPhone16,1")
        if let deviceModel = Self.deviceModel() {
            headers["X-Device-Model"] = deviceModel
        }

        // X-SDK-Version: Gate/AI SDK version (e.g., "1.1.0")
        headers["X-SDK-Version"] = GateAIVersion.current

        return headers
    }

    // MARK: - Private Helpers

    private static func clientLocale() -> String? {
        // Convert "en_US" to "en-US" format
        let identifier = Locale.current.identifier
        return identifier.replacingOccurrences(of: "_", with: "-")
    }

    private static func appVersion() -> String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static func osVersion() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run { UIDevice.current.systemVersion }
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    private static func deviceIdentifier() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        #else
        return nil
        #endif
    }

    private static func deviceType() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run { UIDevice.current.model }
        #else
        return "macOS"
        #endif
    }

    private static func environment() -> String {
        #if DEBUG
        return "development"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "testflight"
        }
        return "production"
        #endif
    }

    private static func deviceModel() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer -> String in
            let data = Data(buffer)
            return String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
        }

        // On the simulator, utsname reports the host architecture; prefer the simulated model.
        if machine == "x86_64" || machine == "arm64",
           let simulatorModel = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulatorModel
        }

        return machine.isEmpty ? nil : machine
    }
}
