import Vapor

/// Response DTO for relay pairing initiation
struct RelayPairResponseDTO: Content {
    let apiVersion: String
    let relayUrl: String
    let pairCode: String
    let serverId: String
}
