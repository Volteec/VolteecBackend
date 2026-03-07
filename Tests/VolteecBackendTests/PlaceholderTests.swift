import Foundation
import Testing
import Vapor
@testable import VolteecBackend

@Suite("StatusController")
struct PlaceholderTests {
    @Test("GET /v1/status omite snapshot fields cand nu exista cache Relay valid")
    func statusWithoutCachedRelaySnapshotOmitsOptionalFields() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        app.storage[UpdateCheckerService.CompatibilityCacheKey.self] = .supported

        let request = Request(application: app, on: app.eventLoopGroup.next())
        let response = try await StatusController().getStatus(req: request)
        let encoded = try JSONEncoder().encode(response)
        let payload = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]

        #expect(response.version == BuildInfo.softwareVersion)
        #expect(response.protocolVersion == BuildInfo.protocolVersion)
        #expect(response.compatibility == .supported)
        #expect(response.relayCurrentProtocolVersion == nil)
        #expect(response.relayMinProtocolVersion == nil)
        #expect(payload?["relayCurrentProtocolVersion"] == nil)
        #expect(payload?["relayMinProtocolVersion"] == nil)
    }

    @Test("GET /v1/status include snapshot fields din ultimul check Relay reusit")
    func statusWithCachedRelaySnapshotIncludesOptionalFields() async throws {
        let app = Application(.testing)
        defer { app.shutdown() }

        app.storage[UpdateCheckerService.CompatibilityCacheKey.self] = .supported
        app.storage[UpdateCheckerService.RelayProtocolSnapshotKey.self] = .init(
            current: "1.1",
            min: "1.0"
        )

        let request = Request(application: app, on: app.eventLoopGroup.next())
        let response = try await StatusController().getStatus(req: request)

        #expect(response.version == BuildInfo.softwareVersion)
        #expect(response.protocolVersion == BuildInfo.protocolVersion)
        #expect(response.compatibility == .supported)
        #expect(response.relayCurrentProtocolVersion == "1.1")
        #expect(response.relayMinProtocolVersion == "1.0")
    }
}
