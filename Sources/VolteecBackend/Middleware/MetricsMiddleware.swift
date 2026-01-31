import Vapor

/// Captures basic request metrics (count + total duration).
struct MetricsMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        let start = DispatchTime.now()
        do {
            let response = try await next.respond(to: request)
            recordMetrics(for: request, status: response.status, start: start)
            return response
        } catch {
            let status = (error as? any AbortError)?.status ?? .internalServerError
            recordMetrics(for: request, status: status, start: start)
            throw error
        }
    }

    private func recordMetrics(
        for request: Request,
        status: HTTPResponseStatus,
        start: DispatchTime
    ) {
        let end = DispatchTime.now()
        let durationNs = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
        let durationMs = durationNs / 1_000_000
        request.metricsService.record(
            method: request.method,
            path: request.url.path,
            status: status,
            durationMs: durationMs
        )
    }
}
