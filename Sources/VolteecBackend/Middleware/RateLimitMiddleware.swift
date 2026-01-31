import Vapor

/// Simple fixed-window rate limiting middleware (per IP, in-memory).
/// V1 is single-instance; external rate limiting can be added at the edge if needed.
final class RateLimitMiddleware: AsyncMiddleware {
    private let limiter: RateLimiter

    init(maxRequests: Int = 60, windowSeconds: Int = 60) {
        self.limiter = RateLimiter(maxRequests: maxRequests, windowSeconds: windowSeconds)
    }

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let ip = request.remoteAddress?.ipAddress ?? "unknown"
        let allowed = await limiter.allow(key: ip)
        guard allowed else {
            throw Abort(.tooManyRequests, reason: "Rate limit exceeded")
        }
        return try await next.respond(to: request)
    }
}

// MARK: - In-memory fixed-window limiter

actor RateLimiter {
    struct Entry {
        var count: Int
        var windowStart: Date
    }

    private let maxRequests: Int
    private let windowSeconds: Int
    private var store: [String: Entry] = [:]

    init(maxRequests: Int, windowSeconds: Int) {
        self.maxRequests = maxRequests
        self.windowSeconds = windowSeconds
    }

    func allow(key: String) -> Bool {
        let now = Date()
        if var entry = store[key] {
            if now.timeIntervalSince(entry.windowStart) >= Double(windowSeconds) {
                entry.count = 1
                entry.windowStart = now
                store[key] = entry
                return true
            }
            if entry.count < maxRequests {
                entry.count += 1
                store[key] = entry
                return true
            }
            return false
        } else {
            store[key] = Entry(count: 1, windowStart: now)
            return true
        }
    }
}
