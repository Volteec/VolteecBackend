import Vapor

/// Relay endpoints for app pairing flow
struct RelayController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let relay = routes.grouped("relay")
        relay.post("pair", use: createPairing)
    }

    /// POST /relay/pair - Generate pairCode and register it with relay
    /// - Returns: relayUrl + pairCode
    func createPairing(req: Request) async throws -> RelayPairResponseDTO {
        guard let relayConfig = RelayConfig.get(from: req.application),
              let relayClient = RelayClient.get(from: req.application) else {
            throw Abort(.serviceUnavailable, reason: "Relay not configured")
        }

        let pairCode = PairCodeGenerator.generate()
        let timestamp = Int64(Date().timeIntervalSince1970)

        do {
            try await relayClient.createPairCode(pairCode: pairCode, timestamp: timestamp)
        } catch {
            req.logger.error("Failed to create pair code with relay: \(error)")
            throw Abort(.badGateway, reason: "Failed to register pair code")
        }

        return RelayPairResponseDTO(
            apiVersion: "1.0",
            relayUrl: relayConfig.url,
            pairCode: pairCode,
            serverId: relayConfig.serverId
        )
    }
}

private enum PairCodeGenerator {
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate(length: Int = 8) -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }
}
