import Vapor
import Foundation

// MARK: - UPS Event Bus

/// Actor-based event bus for distributing UPS state changes to SSE subscribers
/// Guarantees thread-safe pub/sub with no data races
actor UPSEventBus {

    // MARK: - Error Types

    enum EventBusError: Error {
        case subscriberLimitExceeded
    }

    // MARK: - UPSEvent

    struct UPSEvent: Sendable {
        enum EventType: Sendable {
            case statusChange
            case metricsUpdate
        }

        let type: EventType
        let ups: UPS
        let hasLowBattery: Bool

        init(type: EventType, ups: UPS) {
            self.type = type
            self.ups = ups
            // Check if upsStatusRaw contains "LB" (low battery flag from NUT)
            self.hasLowBattery = ups.upsStatusRaw?.uppercased().contains("LB") ?? false
        }
    }

    // MARK: - Subscription Management

    typealias Subscriber = @Sendable (UPSEvent) async -> Void

    private var subscribers: [UUID: Subscriber] = [:]

    /// Subscribe to UPS events. Returns a subscription ID that must be used to unsubscribe.
    /// - Throws: EventBusError.subscriberLimitExceeded if limit reached
    func subscribe(_ handler: @escaping Subscriber) throws -> UUID {
        let limit = 100
        guard subscribers.count < limit else {
            throw EventBusError.subscriberLimitExceeded
        }

        let id = UUID()
        subscribers[id] = handler
        return id
    }

    /// Unsubscribe from UPS events using the subscription ID
    func unsubscribe(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    /// Publish a UPS event to all subscribers
    func publish(_ event: UPSEvent) async {
        await withTaskGroup(of: Void.self) { group in
            for (_, subscriber) in subscribers {
                group.addTask {
                    await subscriber(event)
                }
            }
        }
    }

    /// Get the current number of active subscribers (useful for debugging)
    func subscriberCount() -> Int {
        return subscribers.count
    }
}

// MARK: - Storage Key

struct UPSEventBusKey: StorageKey {
    typealias Value = UPSEventBus
}
