import Vapor
import Crypto

/// Middleware for validating Bearer token authentication
struct AuthMiddleware: AsyncMiddleware {
    /// The expected SHA-256 hash of the API token
    private let validTokenHash: String

    /// Initialize with the valid API token
    /// - Parameter validTokenHash: The expected SHA-256 hash of the Bearer token
    init(validTokenHash: String) {
        self.validTokenHash = validTokenHash
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        // Extract Authorization header
        guard let authHeader = request.headers.bearerAuthorization else {
            logAuthFailure(request: request, reason: "missing_header")
            throw Abort(.unauthorized, reason: "Missing or invalid Authorization header")
        }

        // Validate token using hash + constant-time comparison
        let incomingHash = ConstantTime.sha256Hex(authHeader.token)
        guard ConstantTime.equals(incomingHash, validTokenHash) else {
            logAuthFailure(request: request, reason: "invalid_token")
            throw Abort(.unauthorized, reason: "Invalid authentication token")
        }

        // Token is valid, proceed to next responder
        return try await next.respond(to: request)
    }

    private func logAuthFailure(request: Request, reason: String) {
        let ipHash = hashIP(request.remoteAddress?.ipAddress ?? "unknown")
        request.logger.warning("Authentication failed", metadata: [
            "reason": .string(reason),
            "ipHash": .string(ipHash),
            "path": .string(request.url.path),
            "method": .string(request.method.rawValue)
        ])
    }

    private func hashIP(_ ip: String) -> String {
        let digest = SHA256.hash(data: Data(ip.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Application Extension

extension Application {
    /// Register authentication middleware globally
    /// This applies to all routes. Health check endpoints (if any) should be registered before this.
    /// - Parameter config: Application configuration containing the API token
    func registerAuthMiddleware(config: AppConfig) {
        guard let tokenHash = config.apiTokenHash else {
            return
        }
        let authMiddleware = AuthMiddleware(validTokenHash: tokenHash)
        self.middleware.use(authMiddleware)
    }
}
