import Vapor
import VolteecShared

/// Service responsible for checking protocol compatibility with the Relay.
struct UpdateCheckerService {
    let app: Application
    
    /// Storage key for caching the compatibility state
    struct CompatibilityCacheKey: StorageKey {
        typealias Value = CompatibilityState
    }
    
    /// Storage key for caching the last 'update available' push notification date
    struct LastAvailablePushKey: StorageKey {
        typealias Value = Date
    }

    /// Storage key for caching the last 'update required' push notification date
    struct LastRequiredPushKey: StorageKey {
        typealias Value = Date
    }
    
    /// Starts the background task for periodic compatibility checks.
    func start() async {
        app.logger.info("UpdateCheckerService started")
        
        while !Task.isCancelled {
            await updateCompatibilityState()
            
            // Wait for 24 hours before next check
            // 24h * 60m * 60s * 1_000_000_000 nanoseconds
            try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
        }
    }
    
    /// Checks the Relay metadata and updates local compatibility state.
    /// Should be called periodically (e.g., daily) and on startup.
    func updateCompatibilityState() async {
        // 1. Get Relay URL from the configured RelayConfig (internal-only base URL).
        guard let relayConfig = RelayConfig.get(from: app),
              let relayUrl = URL(string: relayConfig.url)?.appendingPathComponent("meta") else {
            app.logger.info("Relay not configured. Server operating in standalone mode (supported).")
            app.storage[CompatibilityCacheKey.self] = .supported
            return
        }

        // 2. Fetch Metadata from Relay
        do {
            let meta = try await fetchRelayMeta(url: relayUrl)

            // 3. Calculate State using Shared Logic
            let serverProtocol = BuildInfo.protocolVersion

            let state = VersionLogic.calculateState(
                serverProtocol: serverProtocol,
                relayMeta: meta
            )

            // 4. Cache Result
            app.storage[CompatibilityCacheKey.self] = state

            app.logger.info("Compatibility check completed", metadata: [
                "relay": .string(relayUrl.absoluteString),
                "state": .string(state.rawValue),
                "serverProtocol": .string(serverProtocol)
            ])

            // 5. Trigger Notifications (Exclusive per state)

            // CASE A: Deprecated -> Send 'Update Available' ONLY
            if state == .deprecated {
                let lastPush = app.storage[LastAvailablePushKey.self]
                let shouldPush = lastPush == nil || Date().timeIntervalSince(lastPush!) > 86400

                if shouldPush {
                    app.logger.info("Sending 'Update Available' push via Relay.")
                    if let relay = app.relayClient {
                        await relay.sendServerUpdateAvailable(db: app.db)
                        app.storage[LastAvailablePushKey.self] = Date()
                    }
                }
            }
            // CASE B: Unsupported -> Send 'Update Required' ONLY
            else if state == .unsupported {
                let lastPush = app.storage[LastRequiredPushKey.self]
                let shouldPush = lastPush == nil || Date().timeIntervalSince(lastPush!) > 86400

                if shouldPush {
                    app.logger.info("Sending 'Update Required' push via Relay.")
                    if let relay = app.relayClient {
                        await relay.sendServerUpdateRequired(db: app.db)
                        app.storage[LastRequiredPushKey.self] = Date()
                    }
                }

                app.logger.critical("Server is UNSUPPORTED. Entering Safe Mode.")
            }

        } catch let error as DecodingError {
            // Parse/decode errors -> invalid data
            app.logger.error("Failed to decode Relay metadata: \(error)")
            if app.storage[CompatibilityCacheKey.self] == nil {
                app.storage[CompatibilityCacheKey.self] = .invalid
            }
        } catch {
            // Network/HTTP errors -> unreachable
            app.logger.error("Failed to fetch Relay metadata: \(error)")
            if app.storage[CompatibilityCacheKey.self] == nil {
                app.storage[CompatibilityCacheKey.self] = .unreachable
            }
        }
    }
    
    /// Returns the current cached compatibility state (or .unreachable if check never ran)
    func getCurrentState() -> CompatibilityState {
        return app.storage[CompatibilityCacheKey.self] ?? .unreachable
    }
    
    // MARK: - Private Helpers
    
    private func fetchRelayMeta(url: URL) async throws -> RelayMeta {
        let response = try await app.client.get(URI(string: url.absoluteString))
        
        guard response.status == .ok else {
            throw Abort(response.status, reason: "Relay returned non-200 status")
        }
        
        return try response.content.decode(RelayMeta.self)
    }
}

// Extension to easily access the service
extension Application {
    var updateChecker: UpdateCheckerService {
        .init(app: self)
    }
}
