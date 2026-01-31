import Vapor

func routes(_ app: Application) throws {
    // Health check endpoint (liveness)
    app.get("health") { _ async in
        return "ok"
    }

    // Readiness endpoint (checks DB connectivity/migrations)
    app.get("ready") { req async in
        guard let config = AppConfig.get(from: req.application),
              config.apiTokenHash != nil else {
            return Response(status: .serviceUnavailable, body: .init(string: "not_ready"))
        }
        do {
            _ = try await UPS.query(on: req.db).count()
            return Response(status: .ok, body: .init(string: "ready"))
        } catch {
            req.logger.error("Readiness check failed", metadata: [
                "error": .string(error.localizedDescription)
            ])
            return Response(status: .serviceUnavailable, body: .init(string: "not_ready"))
        }
    }

    // Metrics endpoint (public, Prometheus-compatible)
    try app.register(collection: MetricsController())

    guard let config = AppConfig.get(from: app) else {
        throw Abort(.internalServerError, reason: "AppConfig not loaded")
    }

    // Versioned API routes (protected) - only if API_TOKEN is configured
    if let apiTokenHash = config.apiTokenHash {
        let v1 = app
            .grouped("v1")
            .grouped(RateLimitMiddleware())
            .grouped(AuthMiddleware(validTokenHash: apiTokenHash))

        try v1.register(collection: UPSController())
        try v1.register(collection: DeviceController())
        try v1.register(collection: RelayController())
        try v1.register(collection: SSEController())
        try v1.register(collection: StatusController())
    } else {
        app.logger.warning("API routes disabled: API_TOKEN not configured")
    }
}
