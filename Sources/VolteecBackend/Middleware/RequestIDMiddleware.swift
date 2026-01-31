import Vapor

/// Adds or propagates X-Request-ID and attaches it to the request logger.
struct RequestIDMiddleware: AsyncMiddleware {
    private let headerName = "X-Request-ID"

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let requestId = request.headers.first(name: headerName) ?? UUID().uuidString
        request.storage[RequestIDKey.self] = requestId
        request.logger[metadataKey: "requestId"] = .string(requestId)

        let response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: headerName, value: requestId)
        return response
    }
}

struct RequestIDKey: StorageKey {
    typealias Value = String
}

extension Request {
    var requestId: String? {
        storage[RequestIDKey.self]
    }
}
