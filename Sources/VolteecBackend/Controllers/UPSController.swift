import Vapor
import Fluent

struct UPSController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let ups = routes.grouped("ups")

        ups.get(use: listAll)
        ups.get(":upsId", "status", use: getStatus)
    }

    // GET /ups
    func listAll(req: Request) async throws -> [UPSStatusDTO] {
        let upsList = try await UPS.query(on: req.db).all()
        return upsList.map { UPSStatusDTO(from: $0) }
    }

    // GET /ups/:upsId/status
    func getStatus(req: Request) async throws -> UPSStatusDTO {
        guard let upsId = req.parameters.get("upsId") else {
            throw Abort(.badRequest, reason: "Missing upsId parameter")
        }
        let normalizedUpsId = upsId.lowercased()

        guard let ups = try await UPS.query(on: req.db)
            .filter(\.$upsId == normalizedUpsId)
            .first()
        else {
            throw Abort(.notFound, reason: "UPS not found")
        }

        return UPSStatusDTO(from: ups)
    }
}
