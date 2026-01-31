import Vapor
import Crypto
import Foundation
import Fluent

/// HTTP client for sending push events to VolteecPushRelay
actor RelayClient {
    private let app: Application
    private let config: RelayConfig
    private let logger: Logger

    init(app: Application, config: RelayConfig) {
        self.app = app
        self.config = config
        self.logger = app.logger
    }

    /// Send event request to relay with 1 retry on failure.
    /// - Parameters:
    ///   - eventType: Type of event (e.g., "ups_status_change")
    ///   - status: UPS status (e.g., "online", "on_battery", "ups_offline")
    ///   - upsId: UPS identifier
    ///   - environment: push environment ("sandbox", "production")
    ///   - timestamp: Unix timestamp (seconds)
    ///   - batteryLevel: Optional battery percentage (0-100)
    ///   - installationId: Optional installation target
    func sendEvent(
        eventType: String,
        status: String,
        upsId: String,
        environment: String,
        timestamp: Int64,
        batteryLevel: Int?,
        installationId: String?
    ) async {
        let eventId = UUID().uuidString
        // Attempt with 1 retry (total 2 attempts)
        let maxAttempts = 2
        let retryDelaySeconds: UInt64 = 2

        for attempt in 1...maxAttempts {
            do {
                try await sendEventInternal(
                    eventType: eventType,
                    status: status,
                    upsId: upsId,
                    environment: environment,
                    timestamp: timestamp,
                    batteryLevel: batteryLevel,
                    installationId: installationId,
                    eventId: eventId
                )
                // Success - exit retry loop
                return
            } catch {
                let isLastAttempt = attempt == maxAttempts
                if isLastAttempt {
                    logger.error("Failed to send event to relay for UPS \(upsId) after \(maxAttempts) attempts: \(error)")
                } else {
                    logger.warning("Event send attempt \(attempt) failed for UPS \(upsId), retrying in \(retryDelaySeconds)s: \(error)")
                    try? await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
                }
            }
        }
    }

    /// Internal event send implementation (no retry logic).
    private func sendEventInternal(
        eventType: String,
        status: String,
        upsId: String,
        environment: String,
        timestamp: Int64,
        batteryLevel: Int?,
        installationId: String?,
        eventId: String
    ) async throws {
        let request = RelayEventRequest(
            tenantId: config.tenantId,
            eventId: eventId,
            eventType: eventType,
            timestamp: timestamp,
            environment: environment,
            upsId: upsId,
            status: status,
            serverId: config.serverId,
            batteryLevel: batteryLevel,
            installationId: installationId
        )

        // Encode request body
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData = try encoder.encode(request)
        let rawBody = String(data: bodyData, encoding: .utf8) ?? ""

        // Build HMAC signature
        let nonce = generateNonce()
        let signature = try buildHMACSignature(
            timestamp: String(timestamp),
            nonce: nonce,
            rawBody: rawBody,
            secret: config.tenantSecret
        )

        // Build URL
        guard let url = URL(string: "\(config.url)/event") else {
            logger.error("Invalid relay URL: \(config.url)")
            throw RelayError.invalidURL
        }

        // Create HTTP request
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Volteec-Signature", value: signature)
        headers.add(name: "X-Volteec-Nonce", value: nonce)
        headers.add(name: "X-Request-ID", value: eventId)

        let httpRequest = ClientRequest(
            method: .POST,
            url: URI(string: url.absoluteString),
            headers: headers,
            body: .init(data: bodyData)
        )
        var requestWithTimeout = httpRequest
        requestWithTimeout.timeout = .seconds(15)

        // Send request
        let response = try await app.client.send(requestWithTimeout)

        // Check response
        if response.status.code >= 200 && response.status.code < 300 {
            logger.debug("Successfully sent event to relay for UPS \(upsId)")
        } else {
            logger.error("Relay returned error status \(response.status.code) for UPS \(upsId)")
            throw RelayError.relayErrorStatus(response.status.code)
        }
    }

    /// Create a pairing code in relay
    /// - Parameters:
    ///   - pairCode: Pairing code (8-10 chars)
    ///   - timestamp: Unix timestamp (seconds)
    func createPairCode(pairCode: String, timestamp: Int64) async throws {
        let request = RelayPairRequest(
            tenantId: config.tenantId,
            pairCode: pairCode,
            timestamp: timestamp
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(request)
        let rawBody = String(data: bodyData, encoding: .utf8) ?? ""

        let nonce = generateNonce()
        let signature = try buildHMACSignature(
            timestamp: String(timestamp),
            nonce: nonce,
            rawBody: rawBody,
            secret: config.tenantSecret
        )

        guard let url = URL(string: "\(config.url)/pair") else {
            logger.error("Invalid relay URL: \(config.url)")
            throw RelayError.invalidURL
        }

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "X-Volteec-Signature", value: signature)
        headers.add(name: "X-Volteec-Nonce", value: nonce)
        headers.add(name: "X-Request-ID", value: UUID().uuidString)

        let httpRequest = ClientRequest(
            method: .POST,
            url: URI(string: url.absoluteString),
            headers: headers,
            body: .init(data: bodyData)
        )

        let response = try await app.client.send(httpRequest)
        guard (200..<300).contains(response.status.code) else {
            throw RelayError.relayErrorStatus(response.status.code)
        }
    }

    /// Send heartbeat to relay
    /// - Parameters:
    ///   - timestamp: Unix timestamp (seconds)
    func sendHeartbeat(timestamp: Int64) async {
        do {
            let request = RelayHeartbeatRequest(
                tenantId: config.tenantId,
                timestamp: timestamp,
                serverId: config.serverId
            )

            let encoder = JSONEncoder()
            let bodyData = try encoder.encode(request)
            let rawBody = String(data: bodyData, encoding: .utf8) ?? ""

            let nonce = generateNonce()
            let signature = try buildHMACSignature(
                timestamp: String(timestamp),
                nonce: nonce,
                rawBody: rawBody,
                secret: config.tenantSecret
            )

            guard let url = URL(string: "\(config.url)/heartbeat") else {
                logger.error("Invalid relay URL: \(config.url)")
                return
            }

            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "X-Volteec-Signature", value: signature)
            headers.add(name: "X-Volteec-Nonce", value: nonce)
            headers.add(name: "X-Request-ID", value: UUID().uuidString)

            let httpRequest = ClientRequest(
                method: .POST,
                url: URI(string: url.absoluteString),
                headers: headers,
                body: .init(data: bodyData)
            )

            let response = try await app.client.send(httpRequest)

            if response.status.code >= 200 && response.status.code < 300 {
                logger.debug("Successfully sent heartbeat to relay")
            } else {
                logger.error("Relay returned error status \(response.status.code) for heartbeat")
            }
        } catch {
            logger.error("Failed to send heartbeat to relay: \(error)")
        }
    }

    /// Send push notifications for server update required event (via relay)
    /// - Parameters:
    ///   - db: Database connection
    func sendServerUpdateRequired(db: any Database) async {
        await broadcastEvent(eventType: "server_update_required", status: "update_required", db: db)
    }

    /// Send push notifications for server update available event (via relay)
    /// - Parameters:
    ///   - db: Database connection
    func sendServerUpdateAvailable(db: any Database) async {
        await broadcastEvent(eventType: "server_update_available", status: "update_available", db: db)
    }

    /// Helper to broadcast a server-level event to all registered devices in all environments
    private func broadcastEvent(eventType: String, status: String, db: any Database) async {
        do {
            // Verify if we have any registered devices locally to avoid spamming Relay for empty servers
            let deviceCount = try await Device.query(on: db).count()
            
            guard deviceCount > 0 else {
                logger.debug("No local devices registered, skipping broadcast push (\(eventType))")
                return
            }
            
            logger.debug("Sending \(eventType) broadcast to Relay (Tenant fan-out)")
            
            let timestamp = Int64(Date().timeIntervalSince1970)
            
            // Broadcast to BOTH environments (sandbox & production) to reach all devices
            let environments = ["production", "sandbox"]
            
            for env in environments {
                await sendEvent(
                    eventType: eventType,
                    status: status,
                    upsId: "", // Global event
                    environment: env,
                    timestamp: timestamp,
                    batteryLevel: nil,
                    installationId: nil // Nil triggers Tenant-level broadcast in Relay
                )
            }
        } catch {
            logger.error("Failed to count devices for relay broadcast push: \(error)")
        }
    }

    /// Build HMAC-SHA256 signature
    /// - Parameters:
    ///   - timestamp: Unix timestamp as string
    ///   - rawBody: Raw JSON body as string
    ///   - secret: Client secret
    /// - Returns: Hex-encoded HMAC signature
    private func buildHMACSignature(
        timestamp: String,
        nonce: String,
        rawBody: String,
        secret: String
    ) throws -> String {
        // Canonical string: timestamp + "\n" + nonce + "\n" + rawBody
        let canonicalString = timestamp + "\n" + nonce + "\n" + rawBody

        // Convert to Data
        guard let messageData = canonicalString.data(using: .utf8),
              let keyData = secret.data(using: .utf8) else {
            throw RelayError.invalidSignatureData
        }

        // Create HMAC key
        let key = SymmetricKey(data: keyData)

        // Compute HMAC-SHA256
        let signature = HMAC<SHA256>.authenticationCode(for: messageData, using: key)

        // Convert to hex string
        return Data(signature).map { String(format: "%02x", $0) }.joined()
    }

    private func generateNonce() -> String {
        UUID().uuidString
    }
}

// MARK: - Request/Response Models

/// Payload structure for relay push request
struct RelayEventRequest: Content, Sendable {
    let tenantId: String
    let eventId: String
    let eventType: String
    let timestamp: Int64
    let environment: String
    let upsId: String?
    let status: String?
    let serverId: String?
    let batteryLevel: Int?
    let installationId: String?
}

struct RelayHeartbeatRequest: Content, Sendable {
    let tenantId: String
    let timestamp: Int64
    let serverId: String?
}

struct RelayPairRequest: Content, Sendable {
    let tenantId: String
    let pairCode: String
    let timestamp: Int64
}

// MARK: - Errors

enum RelayError: Error, CustomStringConvertible {
    case invalidSignatureData
    case invalidURL
    case relayErrorStatus(UInt)

    var description: String {
        switch self {
        case .invalidSignatureData:
            return "Failed to convert signature data to UTF-8"
        case .invalidURL:
            return "Invalid relay URL"
        case .relayErrorStatus(let status):
            return "Relay returned error status \(status)"
        }
    }
}

// MARK: - Storage Key

extension RelayClient {
    /// Storage key for accessing service from Application
    struct Key: StorageKey {
        typealias Value = RelayClient
    }

    /// Store service in application storage
    static func store(in app: Application, service: RelayClient) {
        app.storage[Key.self] = service
    }

    /// Retrieve service from application storage
    static func get(from app: Application) -> RelayClient? {
        return app.storage[Key.self]
    }
}

extension Application {
    var relayClient: RelayClient? {
        RelayClient.get(from: self)
    }
}
