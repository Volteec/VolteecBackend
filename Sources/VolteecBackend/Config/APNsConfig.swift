import Vapor
import Foundation

/// APNs configuration loaded from environment variables
/// Returns nil if APNS_KEY_P8_PATH is not set, enabling graceful degradation
struct APNsConfig {
    let teamId: String
    let keyId: String
    let topic: String
    let keyPath: String
    let environment: APNSEnvironment

    /// Configuration error types
    enum ConfigError: Error, CustomStringConvertible {
        case missingTeamId
        case missingKeyId
        case missingTopic
        case missingKeyPath
        case keyFileNotFound(String)
        case keyFileNotReadable(String)

        var description: String {
            switch self {
            case .missingTeamId:
                return "APNS_TEAM_ID environment variable is required"
            case .missingKeyId:
                return "APNS_KEY_ID environment variable is required"
            case .missingTopic:
                return "APNS_TOPIC environment variable is required"
            case .missingKeyPath:
                return "APNS_KEY_P8_PATH environment variable is required"
            case .keyFileNotFound(let path):
                return "APNs key file not found at path: \(path)"
            case .keyFileNotReadable(let path):
                return "APNs key file not readable at path: \(path)"
            }
        }
    }

    /// Load configuration from environment variables
    /// Returns nil if APNs is not configured (graceful degradation)
    /// - Returns: Configured APNsConfig instance or nil if not configured
    static func load() -> APNsConfig? {
        // Check if APNS_KEY_P8_PATH is set (primary indicator)
        guard let keyPath = Environment.get("APNS_KEY_P8_PATH"), !keyPath.isEmpty else {
            return nil
        }

        // If key path is set, all other variables are required
        guard let teamId = Environment.get("APNS_TEAM_ID"), !teamId.isEmpty else {
            return nil
        }

        guard let keyId = Environment.get("APNS_KEY_ID"), !keyId.isEmpty else {
            return nil
        }

        guard let topic = Environment.get("APNS_TOPIC"), !topic.isEmpty else {
            return nil
        }

        // Load environment (defaults to sandbox)
        let environmentString = Environment.get("APNS_ENVIRONMENT") ?? "sandbox"
        let environment = APNSEnvironment(rawValue: environmentString.lowercased()) ?? .sandbox

        return APNsConfig(
            teamId: teamId,
            keyId: keyId,
            topic: topic,
            keyPath: keyPath,
            environment: environment
        )
    }

    /// Validate that the key file exists and is readable
    /// - Throws: ConfigError if validation fails
    func validate() throws {
        let fileManager = FileManager.default

        // Check file exists
        guard fileManager.fileExists(atPath: keyPath) else {
            throw ConfigError.keyFileNotFound(keyPath)
        }

        // Check file is readable
        guard fileManager.isReadableFile(atPath: keyPath) else {
            throw ConfigError.keyFileNotReadable(keyPath)
        }
    }
}

// MARK: - Storage Key

extension APNsConfig {
    /// Storage key for accessing config from Application
    private struct Key: StorageKey {
        typealias Value = APNsConfig
    }

    /// Store config in application storage
    static func store(in app: Application, config: APNsConfig) {
        app.storage[Key.self] = config
    }

    /// Retrieve config from application storage
    static func get(from app: Application) -> APNsConfig? {
        return app.storage[Key.self]
    }
}
