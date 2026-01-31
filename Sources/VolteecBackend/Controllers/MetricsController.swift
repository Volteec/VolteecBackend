import Vapor

/// Controller for exposing backend metrics (Prometheus text format).
struct MetricsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.get("metrics", use: metrics)
    }

    func metrics(req: Request) async throws -> Response {
        let body = req.metricsService.renderPrometheus()
        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/plain; version=0.0.4; charset=utf-8")
        return Response(status: .ok, headers: headers, body: .init(string: body))
    }
}
