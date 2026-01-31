import Vapor
import Foundation
import NIOConcurrencyHelpers

/// In-memory metrics collector (Prometheus text format).
final class MetricsService: @unchecked Sendable {
    private struct MetricKey: Hashable {
        let method: String
        let path: String
        let status: String
    }

    private struct MetricValue {
        var count: Int64
        var durationMsSum: Double
    }

    private let storage = NIOLockedValueBox<[MetricKey: MetricValue]>([:])

    func record(
        method: HTTPMethod,
        path: String,
        status: HTTPResponseStatus,
        durationMs: Double
    ) {
        let key = MetricKey(
            method: method.rawValue,
            path: path,
            status: String(status.code)
        )
        storage.withLockedValue { metrics in
            var entry = metrics[key] ?? MetricValue(count: 0, durationMsSum: 0)
            entry.count += 1
            entry.durationMsSum += durationMs
            metrics[key] = entry
        }
    }

    func renderPrometheus() -> String {
        var lines: [String] = []
        lines.append("# TYPE volteec_requests_total counter")
        lines.append("# TYPE volteec_request_duration_ms_sum counter")

        let snapshot = storage.withLockedValue { $0 }
        for (key, value) in snapshot {
            let labels = "method=\"\(key.method)\",path=\"\(key.path)\",status=\"\(key.status)\""
            lines.append("volteec_requests_total{\(labels)} \(value.count)")
            let duration = String(format: "%.2f", value.durationMsSum)
            lines.append("volteec_request_duration_ms_sum{\(labels)} \(duration)")
        }

        return lines.joined(separator: "\n") + "\n"
    }
}

struct MetricsServiceKey: StorageKey {
    typealias Value = MetricsService
}

extension Request {
    var metricsService: MetricsService {
        if let service = application.storage[MetricsServiceKey.self] {
            return service
        }
        let service = MetricsService()
        application.storage[MetricsServiceKey.self] = service
        return service
    }
}
