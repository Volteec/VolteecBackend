import Vapor
import Foundation

/// Relay configuration loaded from environment variables
/// Returns nil if RELAY_URL is not set, enabling graceful degradation
struct RelayConfig {
    let url: String
    let tenantId: String
    let tenantSecret: String
    let serverId: String
    let environment: String

    /// Configuration error types
    enum ConfigError: Error, CustomStringConvertible {
        case missingURL
        case missingTenantId
        case missingTenantSecret
        case missingServerId
        case invalidURL(String)
        case invalidServerId(String)

        var description: String {
            switch self {
            case .missingURL:
                return "RELAY_URL environment variable is required"
            case .missingTenantId:
                return "RELAY_TENANT_ID environment variable is required"
            case .missingTenantSecret:
                return "RELAY_TENANT_SECRET environment variable is required"
            case .missingServerId:
                return "RELAY_SERVER_ID environment variable is required"
            case .invalidURL(let url):
                return "Invalid RELAY_URL: \(url)"
            case .invalidServerId(let value):
                return "Invalid RELAY_SERVER_ID: \(value)"
            }
        }
    }

    /// Load configuration from environment variables
    /// Returns nil if relay is not configured (graceful degradation)
    /// - Returns: Configured RelayConfig instance or nil if not configured
    static func load() -> RelayConfig? {
        // Check if RELAY_URL is set (primary indicator)
        guard let url = Environment.get("RELAY_URL"), !url.isEmpty else {
            return nil
        }

        // If URL is set, all other variables are required
        let tenantId = Environment.get("RELAY_TENANT_ID") ?? Environment.get("RELAY_CLIENT_ID")
        guard let tenantId, !tenantId.isEmpty else {
            return nil
        }

        let tenantSecret = Environment.get("RELAY_TENANT_SECRET") ?? Environment.get("RELAY_CLIENT_SECRET")
        guard let tenantSecret, !tenantSecret.isEmpty else {
            return nil
        }

        guard let serverId = Environment.get("RELAY_SERVER_ID"), !serverId.isEmpty else {
            return nil
        }

        guard UUID(uuidString: serverId) != nil else {
            return nil
        }

        let environment = (Environment.get("RELAY_ENVIRONMENT") ?? "sandbox").lowercased()

        return RelayConfig(
            url: url,
            tenantId: tenantId,
            tenantSecret: tenantSecret,
            serverId: serverId,
            environment: environment
        )
    }

    /// Validate that the URL is well-formed
    /// - Throws: ConfigError if validation fails
    func validate() throws {
        // Ensure URL is valid
        guard URL(string: url) != nil else {
            throw ConfigError.invalidURL(url)
        }

        guard UUID(uuidString: serverId) != nil else {
            throw ConfigError.invalidServerId(serverId)
        }
    }

    /// Check if relay is configured
    /// - Returns: true if relay configuration is available
    static func isConfigured() -> Bool {
        return load() != nil
    }
}

// MARK: - Storage Key

extension RelayConfig {
    /// Storage key for accessing config from Application
    private struct Key: StorageKey {
        typealias Value = RelayConfig
    }

    /// Store config in application storage
    static func store(in app: Application, config: RelayConfig) {
        app.storage[Key.self] = config
    }

    /// Retrieve config from application storage
    static func get(from app: Application) -> RelayConfig? {
        return app.storage[Key.self]
    }
}
