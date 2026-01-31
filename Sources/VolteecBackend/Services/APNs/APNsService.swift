import Vapor
import Fluent
import APNS
import VaporAPNS
import APNSCore

/// Actor responsible for sending APNs push notifications on status change events
actor APNsService {
    private let app: Application
    private let config: APNsConfig
    private let logger: Logger

    init(app: Application, config: APNsConfig) {
        self.app = app
        self.config = config
        self.logger = app.logger
    }

    /// Send push notifications for a status change event
    /// - Parameters:
    ///   - upsId: UPS identifier
    ///   - newStatus: New UPS status
    ///   - hasLowBattery: Whether the UPS has low battery flag (LB)
    ///   - db: Database connection
    func sendStatusChange(
        upsId: String,
        newStatus: UPSStatus,
        hasLowBattery: Bool,
        db: any Database
    ) async {
        do {
            let crypto = try DeviceTokenCrypto()

            // Query all devices registered for this UPS and matching environment
            let devices = try await Device.query(on: db)
                .filter(\.$upsId == upsId)
                .filter(\.$environment == config.environment)
                .all()

            guard !devices.isEmpty else {
                logger.debug("No devices registered for UPS \(upsId) in \(config.environment.rawValue) environment")
                return
            }

            logger.debug("Sending status_change push for UPS \(upsId) to \(devices.count) device(s)")

            // Send to each device (fire-and-forget)
            for device in devices {
                guard let plainToken = crypto.decrypt(ciphertext: device.deviceToken) else {
                    logger.error("Failed to decrypt device token for device \(device.id?.uuidString ?? "unknown")")
                    continue
                }

                Task {
                    await sendPushNotification(
                        deviceToken: plainToken,
                        upsId: upsId,
                        upsAlias: device.upsAlias,
                        status: newStatus
                    )
                }
            }

        } catch {
            logger.error("Failed to query devices for status_change push: \(error)")
        }
    }

    /// Send push notification to a single device token
    /// - Parameters:
    ///   - deviceToken: APNs device token
    ///   - upsId: UPS identifier
    ///   - upsAlias: Optional UPS alias for user-friendly identification
    ///   - status: UPS status
    private func sendPushNotification(
        deviceToken: String,
        upsId: String,
        upsAlias: String?,
        status: UPSStatus
    ) async {
        // Payload structure for NSE processing
        struct EventPayload: Encodable, Sendable {
            struct Event: Encodable, Sendable {
                let eventType: String
                let upsId: String
                let upsAlias: String?
                let status: String
                let environment: String
            }
            let event: Event
        }

        let payload = EventPayload(
            event: .init(
                eventType: "ups_status_changed",
                upsId: upsId,
                upsAlias: upsAlias,
                status: status.rawValue,
                environment: config.environment.rawValue
            )
        )

        // Use alert notification with mutable-content to trigger NSE
        let notification = APNSAlertNotification(
            alert: .init(
                title: .raw("Update"),
                subtitle: nil,
                body: .raw("")
            ),
            expiration: .immediately,
            priority: .immediately,
            topic: config.topic,
            payload: payload,
            sound: .default,
            mutableContent: 1
        )

        // Retry logic: 2 attempts (1 original + 1 retry), 2s delay
        let maxAttempts = 2
        for attempt in 1...maxAttempts {
            do {
                try await withTimeout(seconds: 15) { [self] in
                    try await app.apns.client.sendAlertNotification(
                        notification,
                        deviceToken: deviceToken
                    )
                }

                logger.debug("Successfully sent push (attempt \(attempt)/\(maxAttempts))")
                return // Success, exit

            } catch {
                logger.warning("APNs push failed (attempt \(attempt)/\(maxAttempts)): \(error)")

                // Check if permanent error (no retry)
                let errorString = String(describing: error).lowercased()
                if errorString.contains("baddevicetoken") ||
                   errorString.contains("unregistered") ||
                   errorString.contains("devicetokennotfortopic") {
                    logger.error("Permanent APNs error (device token redacted), will not retry")
                    return
                }

                // If last attempt, give up
                if attempt == maxAttempts {
                    logger.error("All APNs push attempts failed (device token redacted)")
                    return
                }

                // Wait before retry
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
    }
}

// MARK: - Timeout helper

private struct APNSTimeoutError: Error { }

private func withTimeout(
    seconds: UInt64,
    operation: @Sendable @escaping () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            throw APNSTimeoutError()
        }

        guard let _ = try await group.next() else {
            throw APNSTimeoutError()
        }
        group.cancelAll()
        return
    }
}

// MARK: - Storage Key

extension APNsService {
    /// Storage key for accessing service from Application
    struct Key: StorageKey {
        typealias Value = APNsService
    }

    /// Store service in application storage
    static func store(in app: Application, service: APNsService) {
        app.storage[Key.self] = service
    }

    /// Retrieve service from application storage
    static func get(from app: Application) -> APNsService? {
        return app.storage[Key.self]
    }
}
