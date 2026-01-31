import Vapor
import Fluent
import NIOCore

// MARK: - SSE Controller

struct SSEController: RouteCollection {

    func boot(routes: any RoutesBuilder) throws {
        routes.get("events", use: streamEvents)
    }

    // MARK: - Stream Events

    func streamEvents(req: Request) async throws -> Response {
        // Parse rate parameter (default 3s)
        let rateParam = req.query[String.self, at: "rate"]
        let updateRate = UpdateRate.parse(rateParam)

        req.logger.info("SSE connection started with rate: \(updateRate.rawValue)")

        // Get event bus from app storage
        guard let eventBus = req.application.storage[UPSEventBusKey.self] else {
            throw Abort(.internalServerError, reason: "Event bus not configured")
        }

        // Capture database and logger for use in streaming closure
        let db = req.db
        let logger = req.logger

        // Create response with SSE headers
        let response = Response(status: .ok)
        response.headers.contentType = .init(type: "text", subType: "event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: .connection, value: "keep-alive")

        // Create body stream using Vapor's async streaming API
        response.body = .init(asyncStream: { writer in
            await runSSEStream(
                writer: writer,
                db: db,
                logger: logger,
                updateRate: updateRate,
                eventBus: eventBus
            )
        })

        return response
    }
}

// MARK: - SSE Stream Runner (standalone function to avoid Sendable issues)

private func runSSEStream(
    writer: any AsyncBodyStreamWriter,
    db: any Database,
    logger: Logger,
    updateRate: UpdateRate,
    eventBus: UPSEventBus
) async {
    logger.info("SSE stream started")

    // Per-connection rate limiter for metrics_update
    let rateLimiter = MetricsRateLimiter(interval: updateRate.interval)

    // Global (process-wide) limiter to cap total metrics_update emissions
    let globalLimiter = GlobalMetricsLimiter.shared

    // Subscribe to event bus with limit enforcement
    // Store subscription ID in a holder to allow capture in handler
    let subscriptionIdHolder = SubscriptionIdHolder()

    do {
        let subscriptionId = try await eventBus.subscribe { event in
            await handleEvent(
                event,
                writer: writer,
                logger: logger,
                rateLimiter: rateLimiter,
                globalLimiter: globalLimiter,
                subscriptionIdHolder: subscriptionIdHolder,
                eventBus: eventBus
            )
        }
        subscriptionIdHolder.id = subscriptionId
    } catch UPSEventBus.EventBusError.subscriberLimitExceeded {
        logger.warning("SSE connection rejected: subscriber limit exceeded")
        try? await writer.write(.end)
        return
    } catch {
        logger.error("Failed to subscribe to event bus: \(error)")
        try? await writer.write(.end)
        return
    }

    // Extract subscription ID for cleanup
    guard let subscriptionId = subscriptionIdHolder.id else {
        logger.error("Subscription ID not set, cannot proceed")
        try? await writer.write(.end)
        return
    }

    defer {
        Task {
            await eventBus.unsubscribe(subscriptionId)
            logger.info("SSE stream unsubscribed from event bus")
        }
    }

    // Send initial snapshot: query DB once and send metrics_update for all UPS
    do {
        let upsList = try await UPS.query(on: db).all()
        var snapshotFailed = false

        for ups in upsList {
            let payload = UPSStatusPayload(from: ups)
            if let event = createEvent(type: .metricsUpdate, payload: payload) {
                let success = await sendEvent(event, to: writer)
                if !success {
                    logger.warning("Initial snapshot write failed, client disconnected")
                    snapshotFailed = true
                    break
                }
            }
        }

        if snapshotFailed {
            await cleanupDeadClient(subscriptionIdHolder: subscriptionIdHolder, eventBus: eventBus)
            return
        }

        logger.info("Sent initial snapshot with \(upsList.count) UPS")
    } catch {
        logger.error("Failed to send initial snapshot: \(error)")
    }

    // Start independent heartbeat task (every 10 seconds)
    let heartbeatTask = Task {
        await runHeartbeat(
            writer: writer,
            logger: logger,
            subscriptionIdHolder: subscriptionIdHolder,
            eventBus: eventBus
        )
    }

    await withTaskCancellationHandler {
        // Wait for cancellation (connection closed by client or server shutdown)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
        
        // Cleanup on normal exit
        heartbeatTask.cancel()
        logger.info("SSE stream ended")
    } onCancel: {
        heartbeatTask.cancel()
        logger.info("SSE stream cancelled")
    }
}

// MARK: - Event Handler

private func handleEvent(
    _ event: UPSEventBus.UPSEvent,
    writer: any AsyncBodyStreamWriter,
    logger: Logger,
    rateLimiter: MetricsRateLimiter,
    globalLimiter: GlobalMetricsLimiter,
    subscriptionIdHolder: SubscriptionIdHolder,
    eventBus: UPSEventBus
) async {
    let payload = UPSStatusPayload(from: event.ups)

    switch event.type {
    case .statusChange:
        // status_change: critical, always sent (detect dead clients)
        if let sseEvent = createEvent(type: .statusChange, payload: payload) {
            let success = await sendEvent(sseEvent, to: writer)
            if success {
                logger.info("Sent status_change for \(event.ups.upsId): \(event.ups.status.rawValue)")
            } else {
                logger.warning("SSE write failed, client disconnected. Will unsubscribe.", metadata: [
                    "subscriptionId": .string(subscriptionIdHolder.id?.uuidString ?? "unknown"),
                    "eventType": "status_change"
                ])
                await cleanupDeadClient(subscriptionIdHolder: subscriptionIdHolder, eventBus: eventBus)
            }
        }

    case .metricsUpdate:
        // metrics_update: rate-limited + fire-and-forget (detect dead clients)
        if await rateLimiter.shouldEmit(for: event.ups.upsId),
           await globalLimiter.shouldEmit() {
            if let sseEvent = createEvent(type: .metricsUpdate, payload: payload) {
                let success = await sendEvent(sseEvent, to: writer)
                if !success {
                    logger.warning("SSE write failed, client disconnected. Will unsubscribe.", metadata: [
                        "subscriptionId": .string(subscriptionIdHolder.id?.uuidString ?? "unknown"),
                        "eventType": "metrics_update"
                    ])
                    await cleanupDeadClient(subscriptionIdHolder: subscriptionIdHolder, eventBus: eventBus)
                }
            }
        }
    }
}

// MARK: - Heartbeat Task

private func runHeartbeat(
    writer: any AsyncBodyStreamWriter,
    logger: Logger,
    subscriptionIdHolder: SubscriptionIdHolder,
    eventBus: UPSEventBus
) async {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(10))

        guard !Task.isCancelled else { break }

        let payload = HeartbeatPayload()
        if let event = createEvent(type: .heartbeat, payload: payload) {
            let success = await sendEvent(event, to: writer)
            if success {
                logger.debug("Sent heartbeat")
            } else {
                logger.warning("Heartbeat write failed, client disconnected. Will unsubscribe.", metadata: [
                    "subscriptionId": .string(subscriptionIdHolder.id?.uuidString ?? "unknown")
                ])
                await cleanupDeadClient(subscriptionIdHolder: subscriptionIdHolder, eventBus: eventBus)
                break // Exit heartbeat loop on dead client
            }
        }
    }
}

// MARK: - Helper Functions

private func createEvent<T: Encodable>(type: SSEEventType, payload: T) -> SSEEvent? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(payload),
          let jsonString = String(data: data, encoding: .utf8) else {
        return nil
    }
    return SSEEvent(event: type, data: jsonString)
}

private func sendEvent(_ event: SSEEvent, to writer: any AsyncBodyStreamWriter) async -> Bool {
    let eventString = event.format()
    let buffer = ByteBuffer(string: eventString)

    do {
        try await writer.write(.buffer(buffer))
        return true
    } catch {
        return false
    }
}

// MARK: - Dead Client Cleanup

private func cleanupDeadClient(
    subscriptionIdHolder: SubscriptionIdHolder,
    eventBus: UPSEventBus
) async {
    guard let subscriptionId = subscriptionIdHolder.id else { return }

    // Unsubscribe dead client from event bus
    await eventBus.unsubscribe(subscriptionId)

    // Mark as cleaned up to prevent duplicate cleanup
    subscriptionIdHolder.id = nil
}

// MARK: - Subscription ID Holder

/// Thread-safe holder for subscription ID to allow capture in closures
final class SubscriptionIdHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var _id: UUID?

    var id: UUID? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _id
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _id = newValue
        }
    }
}

// MARK: - Metrics Rate Limiter Actor

/// Actor to handle per-connection, per-UPS rate limiting for metrics_update events
actor MetricsRateLimiter {
    private let interval: TimeInterval
    private var lastEmitTime: [String: Date] = [:]

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func shouldEmit(for upsId: String) -> Bool {
        let now = Date()
        if let last = lastEmitTime[upsId] {
            if now.timeIntervalSince(last) >= interval {
                lastEmitTime[upsId] = now
                return true
            }
            return false
        } else {
            lastEmitTime[upsId] = now
            return true
        }
    }
}

// MARK: - Global Metrics Limiter

/// Process-wide limiter for metrics_update events (caps total emit rate).
actor GlobalMetricsLimiter {
    static let shared = GlobalMetricsLimiter(maxPerSecond: 50)

    private let maxPerSecond: Int
    private var windowStart: Date
    private var count: Int

    init(maxPerSecond: Int) {
        self.maxPerSecond = maxPerSecond
        self.windowStart = Date()
        self.count = 0
    }

    func shouldEmit() -> Bool {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1.0 {
            windowStart = now
            count = 0
        }
        if count < maxPerSecond {
            count += 1
            return true
        }
        return false
    }
}
