import Vapor
import VolteecShared

// Make ServerStatusResponse conform to Content locally
extension ServerStatusResponse: @retroactive RequestDecodable {}
extension ServerStatusResponse: @retroactive ResponseEncodable {}
extension ServerStatusResponse: @retroactive AsyncRequestDecodable {}
extension ServerStatusResponse: @retroactive AsyncResponseEncodable {}
extension ServerStatusResponse: @retroactive Content {}

struct StatusController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Public endpoint (or protected if needed, but App needs it for negotiation)
        // GET /status
        routes.get("status", use: getStatus)
        
        // POST /status/simulate-push (Debug only)
        if Environment.get("ENVIRONMENT") != "production" {
            routes.post("status", "simulate-push", use: simulatePush)
        }
    }
    
    /// Returns the server's protocol version and compatibility status.
    func getStatus(req: Request) async throws -> ServerStatusResponse {
        // 1. Get Version Info from Build
        let protocolVersion = BuildInfo.protocolVersion
        let softwareVersion = BuildInfo.softwareVersion
        
        // 2. Get Dynamic Compatibility State
        let compatibilityState = req.application.updateChecker.getCurrentState()
        
        return ServerStatusResponse(
            version: softwareVersion,
            protocolVersion: protocolVersion,
            compatibility: compatibilityState
        )
    }
    
    /// Debug endpoint to trigger 'Update Required' push manually
    func simulatePush(req: Request) async throws -> HTTPStatus {
        guard let relay = req.application.relayClient else {
            throw Abort(.serviceUnavailable, reason: "Relay client not configured")
        }
        
        // Force send notification regardless of actual state
        await relay.sendServerUpdateRequired(db: req.db)
        return .ok
    }
}
