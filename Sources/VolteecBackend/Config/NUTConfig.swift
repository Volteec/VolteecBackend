import Foundation

/// Configuration for NUT (Network UPS Tools) TCP client
struct NUTConfig: Sendable {
    /// NUT server hostname or IP address
    let host: String

    /// NUT server port (default: 3493)
    let port: Int

    /// List of UPS names to poll
    let upsList: [String]

    /// Optional username for NUT authentication
    let username: String?

    /// Optional password for NUT authentication
    let password: String?

    /// Polling interval in seconds (default: 1.0)
    let pollInterval: TimeInterval

    /// Configuration error types
    enum ConfigError: Error, CustomStringConvertible {
        case missingHost
        case missingUPSList
        case invalidPort(String)
        case invalidPollInterval(String)
        case emptyUPSList

        var description: String {
            switch self {
            case .missingHost:
                return "NUT_HOST environment variable is required"
            case .missingUPSList:
                return "NUT_UPS environment variable is required (comma-separated list)"
            case .invalidPort(let value):
                return "Invalid NUT_PORT value: '\(value)'. Must be a valid port number (1-65535)"
            case .invalidPollInterval(let value):
                return "Invalid NUT_POLL_INTERVAL value: '\(value)'. Must be a positive number"
            case .emptyUPSList:
                return "NUT_UPS list is empty or contains only whitespace"
            }
        }
    }

    /// Load NUT configuration from environment variables
    /// - Returns: Configured NUTConfig instance, or nil if NUT_HOST is not set (NUT disabled)
    /// - Throws: ConfigError if required variables are missing or invalid
    static func load() throws -> NUTConfig? {
        // Check if NUT is enabled (NUT_HOST must be set)
        guard let host = ProcessInfo.processInfo.environment["NUT_HOST"], !host.isEmpty else {
            return nil
        }

        // Parse port (default: 3493)
        let port: Int
        if let portString = ProcessInfo.processInfo.environment["NUT_PORT"] {
            guard let parsedPort = Int(portString), parsedPort > 0, parsedPort <= 65535 else {
                throw ConfigError.invalidPort(portString)
            }
            port = parsedPort
        } else {
            port = 3493
        }

        // Parse UPS list (required, comma-separated)
        guard let upsString = ProcessInfo.processInfo.environment["NUT_UPS"], !upsString.isEmpty else {
            throw ConfigError.missingUPSList
        }

        let upsList = upsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !upsList.isEmpty else {
            throw ConfigError.emptyUPSList
        }

        // Parse optional authentication
        let username = ProcessInfo.processInfo.environment["NUT_USERNAME"]
        let password = ProcessInfo.processInfo.environment["NUT_PASSWORD"]

        // Parse poll interval (default: 1.0 second)
        let pollInterval: TimeInterval
        if let intervalString = ProcessInfo.processInfo.environment["NUT_POLL_INTERVAL"] {
            guard let parsedInterval = TimeInterval(intervalString), parsedInterval > 0 else {
                throw ConfigError.invalidPollInterval(intervalString)
            }
            pollInterval = parsedInterval
        } else {
            pollInterval = 1.0
        }

        return NUTConfig(
            host: host,
            port: port,
            upsList: upsList,
            username: username,
            password: password,
            pollInterval: pollInterval
        )
    }
}
