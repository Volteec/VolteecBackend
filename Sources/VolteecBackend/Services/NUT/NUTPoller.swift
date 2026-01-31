import Vapor
import Fluent

actor NUTPoller {
    private let config: NUTConfig
    private let db: any Database
    private let logger: Logger
    private let app: Application
    private let eventBus: UPSEventBus
    private var isRunning = false
    private var isPolling = false
    private var lastHeartbeatSent: Date?

    // Track previous status for each UPS to detect changes
    private var lastStatusMap: [String: UPSStatus] = [:]

    init(config: NUTConfig, db: any Database, logger: Logger, app: Application, eventBus: UPSEventBus) {
        self.config = config
        self.db = db
        self.logger = logger
        self.app = app
        self.eventBus = eventBus
    }

    func start() async {
        guard !isRunning else {
            logger.warning("NUTPoller already running")
            return
        }

        isRunning = true
        logger.info("NUTPoller started with interval: \(config.pollInterval)s")

        while isRunning {
            // Check for cancellation
            if Task.isCancelled {
                logger.info("NUTPoller task cancelled")
                isRunning = false
                break
            }

            // Sleep first to avoid immediate poll on startup
            try? await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))

            guard isRunning else { break }
            
            // Double check cancellation after sleep
            if Task.isCancelled {
                isRunning = false
                break
            }

            // Skip poll if previous poll still running (prevents overflow)
            guard !isPolling else {
                logger.warning("Skipping poll cycle: previous poll still in progress")
                continue
            }

            await pollAllUPS()
        }

        logger.info("NUTPoller stopped")
    }

    func stop() {
        isRunning = false
        logger.info("NUTPoller stop requested")
    }

    private func pollAllUPS() async {
        isPolling = true
        defer { isPolling = false }
        for upsName in config.upsList {
            await pollSingleUPS(upsName: upsName)
        }

        await sendHeartbeatIfNeeded()
    }

    /// Retry NUT fetch with exponential backoff
    /// - Returns: variables dict if successful, nil if all attempts failed
    private func retryNUTFetch(upsName: String, maxAttempts: Int = 3) async -> [String: String]? {
        for attempt in 1...maxAttempts {
            do {
                let client = NUTClient(
                    host: config.host,
                    port: config.port,
                    username: config.username,
                    password: config.password
                )

                try await client.connect()
                defer {
                    Task { await client.disconnect() }
                }

                let variables = try await client.fetchVariables(upsName: upsName)

                if attempt > 1 {
                    logger.info("NUT fetch succeeded on attempt \(attempt)/\(maxAttempts) for \(upsName)")
                }

                return variables

            } catch {
                logger.warning("NUT fetch failed (attempt \(attempt)/\(maxAttempts)) for \(upsName): \(error)")

                if attempt < maxAttempts {
                    let delaySeconds = attempt // 1s, then 2s
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
                }
            }
        }

        logger.error("All NUT fetch attempts failed for \(upsName)")
        return nil
    }

    private func pollSingleUPS(upsName: String) async {
        let upsId = upsName.lowercased()

        // Retry NUT fetch with backoff
        guard let variables = await retryNUTFetch(upsName: upsName) else {
            // All attempts failed
            await handlePollFailure(upsId: upsId)
            return
        }

        do {
            // Map NUT data
            let mappedData = NUTMapper.map(variables: variables, upsName: upsName)

            // Upsert to database and get saved UPS + previous DB status
            let (savedUPS, previousDBStatus) = try await upsertUPS(mappedData: mappedData)

            // Prefer in-memory status when available, fallback to DB for fresh starts
            let previousStatus = lastStatusMap[upsId] ?? previousDBStatus

            // Update status tracking
            lastStatusMap[upsId] = mappedData.status

            // Check for status change
            let statusChanged = previousStatus != mappedData.status
            let hasLowBattery = mappedData.upsStatusRaw?.uppercased().contains("LB") ?? false

            // Emit status change event if status actually changed
            if statusChanged {
                logger.info("Status change detected for \(upsId): \(previousStatus?.rawValue ?? "nil") -> \(mappedData.status.rawValue)")

                // Emit to event bus for SSE subscribers
                let event = UPSEventBus.UPSEvent(type: .statusChange, ups: savedUPS)
                await eventBus.publish(event)

                // Send relay push event (fire-and-forget)
                await sendStatusChangePush(
                    upsId: upsId,
                    newStatus: mappedData.status,
                    hasLowBattery: hasLowBattery
                )
            }

            // Always emit metrics update after successful poll (for SSE)
            let metricsEvent = UPSEventBus.UPSEvent(type: .metricsUpdate, ups: savedUPS)
            await eventBus.publish(metricsEvent)

            logger.info("Successfully polled UPS: \(upsName)")

        } catch {
            logger.error("Failed to map/save UPS data for \(upsName): \(error)")

            // Increment failure count and potentially mark offline
            await handlePollFailure(upsId: upsId)
        }
    }

    private func upsertUPS(mappedData: NUTMappedData) async throws -> (UPS, UPSStatus?) {
        if let existing = try await UPS.query(on: db)
            .filter(\.$upsId == mappedData.upsId)
            .first() {

            let previousStatus = existing.status

            // Update existing UPS - reset failure count on success
            existing.status = mappedData.status
            existing.upsStatusRaw = mappedData.upsStatusRaw
            existing.consecutiveFailures = 0

            // Battery fields
            existing.batteryPercent = mappedData.batteryPercent
            existing.batteryChargeWarning = mappedData.batteryChargeWarning
            existing.batteryChargeLow = mappedData.batteryChargeLow
            existing.batteryRuntimeSeconds = mappedData.batteryRuntimeSeconds
            existing.batteryRuntimeLowSeconds = mappedData.batteryRuntimeLowSeconds
            existing.batteryType = mappedData.batteryType
            existing.batteryManufacturerDate = mappedData.batteryManufacturerDate
            existing.batteryVoltage = mappedData.batteryVoltage
            existing.batteryVoltageNominal = mappedData.batteryVoltageNominal

            // Load and power
            existing.loadPercent = mappedData.loadPercent
            existing.upsRealPowerNominal = mappedData.upsRealPowerNominal

            // Input fields
            existing.inputVoltage = mappedData.inputVoltage
            existing.inputVoltageNominal = mappedData.inputVoltageNominal
            existing.inputTransferLow = mappedData.inputTransferLow
            existing.inputTransferHigh = mappedData.inputTransferHigh

            // Output fields
            existing.outputVoltage = mappedData.outputVoltage

            // Device fields
            existing.deviceManufacturer = mappedData.deviceManufacturer
            existing.deviceModel = mappedData.deviceModel
            existing.deviceSerial = mappedData.deviceSerial
            existing.deviceType = mappedData.deviceType

            // UPS fields
            existing.upsManufacturer = mappedData.upsManufacturer
            existing.upsModel = mappedData.upsModel
            existing.upsSerial = mappedData.upsSerial
            existing.upsVendorId = mappedData.upsVendorId
            existing.upsProductId = mappedData.upsProductId
            existing.upsTestResult = mappedData.upsTestResult
            existing.upsBeeperStatus = mappedData.upsBeeperStatus
            existing.upsDelayShutdown = mappedData.upsDelayShutdown
            existing.upsDelayStart = mappedData.upsDelayStart
            existing.upsTimerShutdown = mappedData.upsTimerShutdown
            existing.upsTimerStart = mappedData.upsTimerStart

            // Driver fields
            existing.driverName = mappedData.driverName
            existing.driverVersion = mappedData.driverVersion
            existing.driverVersionData = mappedData.driverVersionData
            existing.driverVersionInternal = mappedData.driverVersionInternal
            existing.driverVersionUsb = mappedData.driverVersionUsb
            existing.driverParameterPollfreq = mappedData.driverParameterPollfreq
            existing.driverParameterPollinterval = mappedData.driverParameterPollinterval
            existing.driverParameterPort = mappedData.driverParameterPort
            existing.driverParameterSynchronous = mappedData.driverParameterSynchronous
            existing.driverParameterVendorId = mappedData.driverParameterVendorId

            // Derived fields
            existing.battery = mappedData.battery
            existing.runtime = mappedData.runtime
            existing.load = mappedData.load

            try await existing.save(on: db)
            return (existing, previousStatus)

        } else {
            // Create new UPS
            let ups = UPS()
            ups.upsId = mappedData.upsId
            ups.dataSource = .nut
            ups.status = mappedData.status
            ups.upsStatusRaw = mappedData.upsStatusRaw
            ups.consecutiveFailures = 0

            // Battery fields
            ups.batteryPercent = mappedData.batteryPercent
            ups.batteryChargeWarning = mappedData.batteryChargeWarning
            ups.batteryChargeLow = mappedData.batteryChargeLow
            ups.batteryRuntimeSeconds = mappedData.batteryRuntimeSeconds
            ups.batteryRuntimeLowSeconds = mappedData.batteryRuntimeLowSeconds
            ups.batteryType = mappedData.batteryType
            ups.batteryManufacturerDate = mappedData.batteryManufacturerDate
            ups.batteryVoltage = mappedData.batteryVoltage
            ups.batteryVoltageNominal = mappedData.batteryVoltageNominal

            // Load and power
            ups.loadPercent = mappedData.loadPercent
            ups.upsRealPowerNominal = mappedData.upsRealPowerNominal

            // Input fields
            ups.inputVoltage = mappedData.inputVoltage
            ups.inputVoltageNominal = mappedData.inputVoltageNominal
            ups.inputTransferLow = mappedData.inputTransferLow
            ups.inputTransferHigh = mappedData.inputTransferHigh

            // Output fields
            ups.outputVoltage = mappedData.outputVoltage

            // Device fields
            ups.deviceManufacturer = mappedData.deviceManufacturer
            ups.deviceModel = mappedData.deviceModel
            ups.deviceSerial = mappedData.deviceSerial
            ups.deviceType = mappedData.deviceType

            // UPS fields
            ups.upsManufacturer = mappedData.upsManufacturer
            ups.upsModel = mappedData.upsModel
            ups.upsSerial = mappedData.upsSerial
            ups.upsVendorId = mappedData.upsVendorId
            ups.upsProductId = mappedData.upsProductId
            ups.upsTestResult = mappedData.upsTestResult
            ups.upsBeeperStatus = mappedData.upsBeeperStatus
            ups.upsDelayShutdown = mappedData.upsDelayShutdown
            ups.upsDelayStart = mappedData.upsDelayStart
            ups.upsTimerShutdown = mappedData.upsTimerShutdown
            ups.upsTimerStart = mappedData.upsTimerStart

            // Driver fields
            ups.driverName = mappedData.driverName
            ups.driverVersion = mappedData.driverVersion
            ups.driverVersionData = mappedData.driverVersionData
            ups.driverVersionInternal = mappedData.driverVersionInternal
            ups.driverVersionUsb = mappedData.driverVersionUsb
            ups.driverParameterPollfreq = mappedData.driverParameterPollfreq
            ups.driverParameterPollinterval = mappedData.driverParameterPollinterval
            ups.driverParameterPort = mappedData.driverParameterPort
            ups.driverParameterSynchronous = mappedData.driverParameterSynchronous
            ups.driverParameterVendorId = mappedData.driverParameterVendorId

            // Derived fields
            ups.battery = mappedData.battery
            ups.runtime = mappedData.runtime
            ups.load = mappedData.load

            try await ups.create(on: db)
            return (ups, nil)
        }
    }

    private func handlePollFailure(upsId: String) async {
        do {
            guard let existing = try await UPS.query(on: db)
                .filter(\.$upsId == upsId)
                .first() else {
                logger.warning("UPS \(upsId) not found in database, cannot increment failure count")
                return
            }

            // Check for status change BEFORE updating
            let previousStatus = existing.status

            // Increment failure count
            existing.consecutiveFailures += 1

            // If 3 or more consecutive failures, mark as offline and clear metrics
            if existing.consecutiveFailures >= 3 {
                logger.warning("UPS \(upsId) marked offline after \(existing.consecutiveFailures) consecutive failures (threshold: 3)")
                existing.status = .ups_offline

                // Update status tracking
                lastStatusMap[upsId] = .ups_offline

                // Clear all metric fields
                existing.upsStatusRaw = nil
                existing.batteryPercent = nil
                existing.batteryChargeWarning = nil
                existing.batteryChargeLow = nil
                existing.batteryRuntimeSeconds = nil
                existing.batteryRuntimeLowSeconds = nil
                existing.batteryType = nil
                existing.batteryManufacturerDate = nil
                existing.batteryVoltage = nil
                existing.batteryVoltageNominal = nil
                existing.loadPercent = nil
                existing.upsRealPowerNominal = nil
                existing.inputVoltage = nil
                existing.inputVoltageNominal = nil
                existing.inputTransferLow = nil
                existing.inputTransferHigh = nil
                existing.outputVoltage = nil
                existing.deviceManufacturer = nil
                existing.deviceModel = nil
                existing.deviceSerial = nil
                existing.deviceType = nil
                existing.upsManufacturer = nil
                existing.upsModel = nil
                existing.upsSerial = nil
                existing.upsVendorId = nil
                existing.upsProductId = nil
                existing.upsTestResult = nil
                existing.upsBeeperStatus = nil
                existing.upsDelayShutdown = nil
                existing.upsDelayStart = nil
                existing.upsTimerShutdown = nil
                existing.upsTimerStart = nil
                existing.driverName = nil
                existing.driverVersion = nil
                existing.driverVersionData = nil
                existing.driverVersionInternal = nil
                existing.driverVersionUsb = nil
                existing.driverParameterPollfreq = nil
                existing.driverParameterPollinterval = nil
                existing.driverParameterPort = nil
                existing.driverParameterSynchronous = nil
                existing.driverParameterVendorId = nil
                existing.battery = nil
                existing.runtime = nil
                existing.load = nil

                try await existing.save(on: db)

                // Emit status change if status changed to offline
                if previousStatus != .ups_offline {
                    // Emit to event bus for SSE subscribers
                    let event = UPSEventBus.UPSEvent(type: .statusChange, ups: existing)
                    await eventBus.publish(event)

                    // Send relay push event
                    await sendStatusChangePush(
                        upsId: upsId,
                        newStatus: .ups_offline,
                        hasLowBattery: false
                    )
                }
            } else {
                try await existing.save(on: db)
            }

        } catch {
            logger.error("Failed to handle poll failure for UPS \(upsId): \(error)")
        }
    }

    /// Send status change push notification via relay
    private func sendStatusChangePush(
        upsId: String,
        newStatus: UPSStatus,
        hasLowBattery: Bool
    ) async {
        guard let relayClient = RelayClient.get(from: app),
              RelayConfig.get(from: app) != nil else {
            logger.warning("Relay not configured, skipping push notification")
            return
        }

        let environment = RelayConfig.get(from: app)?.environment ?? "sandbox"
        let timestamp = Int64(Date().timeIntervalSince1970)

        let eventType = hasLowBattery ? "battery_low" : "ups_status_change"

        logger.debug("Sending \(eventType) via relay for UPS \(upsId)")

        await relayClient.sendEvent(
            eventType: eventType,
            status: newStatus.rawValue,
            upsId: upsId,
            environment: environment,
            timestamp: timestamp,
            batteryLevel: nil,
            installationId: nil
        )
    }

    private func sendHeartbeatIfNeeded() async {
        guard let relayClient = RelayClient.get(from: app),
              RelayConfig.get(from: app) != nil else {
            return
        }

        let now = Date()
        if let lastSent = lastHeartbeatSent, now.timeIntervalSince(lastSent) < 60 {
            return
        }

        lastHeartbeatSent = now

        let timestamp = Int64(now.timeIntervalSince1970)
        await relayClient.sendHeartbeat(timestamp: timestamp)
    }
}
