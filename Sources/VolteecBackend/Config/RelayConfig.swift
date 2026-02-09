import Vapor
import Foundation

/// Relay configuration loaded from environment variables
/// Returns nil if Relay is not configured, enabling graceful degradation.
struct RelayConfig {
    // Internal-only: Relay base URL and environment are intentionally NOT configurable
    // via .env to prevent accidental misconfiguration.
    //
    // For internal production deployments, operators can set:
    //   VOLTEEC_DEPLOYMENT=production
    // This switches the Relay target to production without changing user-facing setup.
    private enum RelayTarget: String {
        case sandbox
        case production
    }

    private static func resolvedTarget() -> RelayTarget {
        let deployment = (Environment.get("VOLTEEC_DEPLOYMENT") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if deployment == RelayTarget.production.rawValue {
            return .production
        }
        return .sandbox
    }

    private static var fixedBaseURL: String {
        switch resolvedTarget() {
        case .sandbox:
            return "https://dev-api.volteec.com/v1"
        case .production:
            return "https://api.volteec.com/v1"
        }
    }

    private static var fixedEnvironment: String {
        switch resolvedTarget() {
        case .sandbox:
            return "sandbox"
        case .production:
            return "production"
        }
    }

    let url: String
    let tenantId: String
    let tenantSecret: String
    let serverId: String
    let environment: String

    /// Configuration error types
    enum ConfigError: Error, CustomStringConvertible {
        case missingTenantId
        case missingTenantSecret
        case missingServerId
        case invalidTenantId(String)
        case invalidServerId(String)
        case invalidURL(String)

        var description: String {
            switch self {
            case .missingTenantId:
                return "RELAY_TENANT_ID environment variable is required"
            case .missingTenantSecret:
                return "RELAY_TENANT_SECRET environment variable is required"
            case .missingServerId:
                return "RELAY_SERVER_ID environment variable is required"
            case .invalidTenantId(let value):
                return "Invalid RELAY_TENANT_ID (expected UUID): \(value)"
            case .invalidURL(let url):
                return "Invalid Relay base URL: \(url)"
            case .invalidServerId(let value):
                return "Invalid RELAY_SERVER_ID: \(value)"
            }
        }
    }

    /// Load configuration from environment variables
    /// Returns nil if relay is not configured (graceful degradation).
    /// Throws if relay appears configured (any RELAY_* is set) but is invalid/incomplete.
    static func load() throws -> RelayConfig? {
        let tenantIdRaw = Environment.get("RELAY_TENANT_ID") ?? Environment.get("RELAY_CLIENT_ID")
        let tenantSecretRaw = Environment.get("RELAY_TENANT_SECRET") ?? Environment.get("RELAY_CLIENT_SECRET")
        let serverIdRaw = Environment.get("RELAY_SERVER_ID")

        let anyRelayEnvSet =
            (tenantIdRaw?.isEmpty == false) ||
            (tenantSecretRaw?.isEmpty == false) ||
            (serverIdRaw?.isEmpty == false)

        guard anyRelayEnvSet else {
            return nil
        }

        guard let tenantId = tenantIdRaw, !tenantId.isEmpty else {
            throw ConfigError.missingTenantId
        }
        guard let tenantSecret = tenantSecretRaw, !tenantSecret.isEmpty else {
            throw ConfigError.missingTenantSecret
        }
        guard let serverId = serverIdRaw, !serverId.isEmpty else {
            throw ConfigError.missingServerId
        }

        let config = RelayConfig(
            url: Self.fixedBaseURL,
            tenantId: tenantId,
            tenantSecret: tenantSecret,
            serverId: serverId,
            environment: Self.fixedEnvironment
        )

        try config.validate()
        return config
    }

    /// Validate that the URL is well-formed
    /// - Throws: ConfigError if validation fails
    func validate() throws {
        guard URL(string: url) != nil else {
            throw ConfigError.invalidURL(url)
        }

        guard UUID(uuidString: tenantId) != nil else {
            throw ConfigError.invalidTenantId(tenantId)
        }

        guard UUID(uuidString: serverId) != nil else {
            throw ConfigError.invalidServerId(serverId)
        }
    }

    /// Check if relay is configured
    /// - Returns: true if relay configuration is available
    static func isConfigured() -> Bool {
        (try? load()) != nil
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
