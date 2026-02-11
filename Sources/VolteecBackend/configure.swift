import NIOSSL
import Fluent
import FluentPostgresDriver
import Vapor

// configures your application
public func configure(_ app: Application) async throws {
    // HTTP client timeouts (RelayClient)
    app.http.client.configuration.timeout = .init(
        connect: .seconds(10),
        read: .seconds(15)
    )
    // Load application configuration from environment
    // This MUST succeed or the application will not start
    let config: AppConfig
    do {
        config = try AppConfig.load(from: app.environment)
        AppConfig.store(in: app, config: config)
        app.logger.info("Configuration loaded successfully")
    } catch let error as AppConfig.ConfigError {
        app.logger.critical("Configuration error: \(error.description)")
        throw error
    } catch {
        app.logger.critical("Unexpected configuration error: \(error)")
        throw error
    }

    if config.apiTokenHash == nil {
        app.logger.critical("API_TOKEN is missing. Server running in degraded mode (health OK, ready FAIL, /v1 disabled).")
    }

    // Explicit CORS configuration (default: disallow all origins)
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .none,
        allowedMethods: [.GET, .POST, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig))

    // Register middleware (order matters: RequestID → Metrics → Auth)
    app.middleware.use(RequestIDMiddleware())
    app.middleware.use(MetricsMiddleware())

    // Initialize metrics service
    let metricsService = MetricsService()
    app.storage[MetricsServiceKey.self] = metricsService
    app.logger.info("Metrics service initialized")

    // uncomment to serve files from /Public folder
    // app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    // Parse DATABASE_TLS_MODE (require | prefer | disable, default: require)
    let tlsMode = try parseDatabaseTLSMode(app: app)

    app.databases.use(DatabaseConfigurationFactory.postgres(configuration: .init(
        hostname: Environment.get("DATABASE_HOST") ?? "localhost",
        port: Environment.get("DATABASE_PORT").flatMap(Int.init(_:)) ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("DATABASE_USERNAME") ?? "vapor_username",
        password: Environment.get("DATABASE_PASSWORD") ?? "vapor_password",
        database: Environment.get("DATABASE_NAME") ?? "vapor_database",
        tls: tlsMode)
    ), as: .psql)

    // register migrations
    app.migrations.add(CreateUPS())
    app.migrations.add(CreateDevice())
    app.migrations.add(AddUpsAliasToDevice())
    app.migrations.add(EnforceLowercaseUPSId())
    app.migrations.add(AddNUTFieldsToUPS())
    app.migrations.add(AddTokenHashToDevice())

    // Create shared UPS event bus for SSE subscriptions
    let eventBus = UPSEventBus()
    app.storage[UPSEventBusKey.self] = eventBus
    app.logger.info("UPS event bus initialized")

    // Configure push notification strategy: Relay only (V1.2)
    // Relay mode: Send push events to external relay service
    var pushMode = "disabled"

    // Try to configure relay first (preferred)
    do {
        if let relayConfig = try RelayConfig.load() {
            // Validate relay URL
            try relayConfig.validate()

            app.logger.info("Relay configuration loaded: url=\(relayConfig.url), tenantId=\(relayConfig.tenantId), serverId=\(relayConfig.serverId)")

            // Create and store relay client
            let relayClient = RelayClient(app: app, config: relayConfig)
            RelayClient.store(in: app, service: relayClient)
            RelayConfig.store(in: app, config: relayConfig)

            app.logger.info("Relay client initialized successfully")
            pushMode = "relay"
        }
    } catch let error as RelayConfig.ConfigError {
        app.logger.error("Relay configuration error: \(error.description)")
        app.logger.warning("Continuing without relay support")
    } catch {
        app.logger.error("Relay initialization error: \(error)")
        app.logger.warning("Continuing without relay support")
    }

    // Log active push mode
    app.logger.info("Push notification mode: \(pushMode)")

    // Validate device token encryption key
    do {
        _ = try DeviceTokenCrypto()
        app.logger.info("Device token encryption: enabled")
    } catch DeviceTokenCrypto.CryptoError.missingKey {
        app.logger.critical("DEVICE_TOKEN_KEY environment variable is required for device token encryption")
        throw Abort(.internalServerError, reason: "Missing DEVICE_TOKEN_KEY")
    } catch {
        app.logger.critical("Invalid DEVICE_TOKEN_KEY: \(error)")
        throw Abort(.internalServerError, reason: "Invalid encryption key")
    }

    // register routes
    try routes(app)

    // Start NUT poller if configured
    do {
        if let nutConfig = try NUTConfig.load() {
            app.logger.info("NUT configuration loaded: host=\(nutConfig.host), port=\(nutConfig.port), UPS list=\(nutConfig.upsList.joined(separator: ","))")

            let poller = NUTPoller(
                config: nutConfig,
                db: app.db,
                logger: app.logger,
                app: app,
                eventBus: eventBus
            )

            // Store poller in app storage for lifecycle management
            app.storage[NUTPollerKey.self] = poller

            // Start polling in background task
            Task {
                await poller.start()
            }

            app.logger.info("NUT poller started")
        } else {
            app.logger.info("NUT not configured (NUT_HOST not set), skipping NUT poller")
        }
    } catch let error as NUTConfig.ConfigError {
        app.logger.error("NUT configuration error: \(error.description)")
        // Don't fail startup, just skip NUT polling
    }

    // Start Compatibility Update Checker (Task-023)
    let updateChecker = app.updateChecker
    Task {
        await updateChecker.start()
    }
}

// MARK: - Storage Keys

private struct NUTPollerKey: StorageKey {
    typealias Value = NUTPoller
}

// MARK: - Database TLS Mode Parser

/// Parse DATABASE_TLS_MODE environment variable
/// Valid values: require (default), prefer, disable
private func parseDatabaseTLSMode(app: Application) throws -> PostgresConnection.Configuration.TLS {
    let mode = Environment.get("DATABASE_TLS_MODE") ?? "disable"

    switch mode.lowercased() {
    case "require":
        app.logger.info("Database TLS mode: require (enforced)")
        return .require(try .init(configuration: .clientDefault))
    case "prefer":
        app.logger.info("Database TLS mode: prefer (fallback to plaintext if unavailable)")
        return .prefer(try .init(configuration: .clientDefault))
    case "disable":
        app.logger.warning("Database TLS mode: disable (plaintext connection - NOT RECOMMENDED for production)")
        return .disable
    default:
        app.logger.critical("Invalid DATABASE_TLS_MODE: '\(mode)'")
        throw Abort(.internalServerError, reason: "Invalid DATABASE_TLS_MODE: '\(mode)'. Valid values: require, prefer, disable")
    }
}
