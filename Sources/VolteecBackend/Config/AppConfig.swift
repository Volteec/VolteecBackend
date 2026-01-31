import Vapor

/// Application configuration loaded from environment variables
struct AppConfig {
    /// SHA-256 hash of API token for authentication (nil if missing)
    let apiTokenHash: String?

    /// APNs environment configuration
    let apnsEnvironment: APNsEnvironment

    enum APNsEnvironment: String {
        case sandbox
        case production
    }

    /// Configuration error types
    enum ConfigError: Error, CustomStringConvertible {
        case missingAPIToken
        case invalidAPNsEnvironment(String)

        var description: String {
            switch self {
            case .missingAPIToken:
                return "API_TOKEN environment variable is required but not set"
            case .invalidAPNsEnvironment(let value):
                return "Invalid APNS_ENVIRONMENT value: '\(value)'. Must be 'sandbox' or 'production'"
            }
        }
    }

    /// Load configuration from environment variables
    /// - Parameter environment: Vapor environment to read from
    /// - Throws: ConfigError if required variables are missing or invalid
    /// - Returns: Configured AppConfig instance
    static func load(from environment: Environment) throws -> AppConfig {
        // Load API_TOKEN (optional; missing puts server in degraded mode)
        let apiToken = Environment.get("API_TOKEN")
        let apiTokenHash = apiToken.map { ConstantTime.sha256Hex($0) }

        // Load APNs environment (defaults to sandbox)
        let apnsEnvironmentString = Environment.get("APNS_ENVIRONMENT") ?? "sandbox"
        guard let apnsEnvironment = APNsEnvironment(rawValue: apnsEnvironmentString.lowercased()) else {
            throw ConfigError.invalidAPNsEnvironment(apnsEnvironmentString)
        }

        return AppConfig(
            apiTokenHash: apiTokenHash,
            apnsEnvironment: apnsEnvironment
        )
    }
}

// MARK: - Storage Key

extension AppConfig {
    /// Storage key for accessing config from Application
    private struct Key: StorageKey {
        typealias Value = AppConfig
    }

    /// Store config in application storage
    static func store(in app: Application, config: AppConfig) {
        app.storage[Key.self] = config
    }

    /// Retrieve config from application storage
    static func get(from app: Application) -> AppConfig? {
        return app.storage[Key.self]
    }
}
