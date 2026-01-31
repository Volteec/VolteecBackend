import Vapor
import Fluent

struct DeviceController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.post("register-device", use: registerDevice)
        routes.post("unregister-device", use: unregisterDevice)
    }

    // POST /register-device
    func registerDevice(req: Request) async throws -> HTTPStatus {
        let dto = try req.content.decode(DeviceRegistrationDTO.self)
        guard dto.apiVersion == "1.0" else {
            throw Abort(.badRequest, reason: "Unsupported apiVersion")
        }
        let crypto = try DeviceTokenCrypto()

        let normalizedUpsId = dto.upsId.lowercased()
        let environment = dto.resolvedEnvironment
        let normalizedAlias = dto.upsAlias?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        let encryptedToken = try crypto.encrypt(plaintext: dto.deviceToken)
        let tokenHash = DeviceTokenCrypto.hash(dto.deviceToken)

        // Check if device already registered
        let existingDevice = try await Device.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .filter(\.$upsId == normalizedUpsId)
            .filter(\.$environment == environment)
            .first()

        if let existingDevice = existingDevice {
            existingDevice.deviceToken = encryptedToken
            existingDevice.upsAlias = normalizedAlias
            try await existingDevice.update(on: req.db)
            return .ok
        }

        // Create new device registration
        let device = Device(
            upsId: normalizedUpsId,
            upsAlias: normalizedAlias,
            deviceToken: encryptedToken,
            tokenHash: tokenHash,
            environment: environment
        )

        try await device.create(on: req.db)
        return .created
    }

    // POST /unregister-device
    func unregisterDevice(req: Request) async throws -> HTTPStatus {
        let dto = try req.content.decode(DeviceRegistrationDTO.self)
        guard dto.apiVersion == "1.0" else {
            throw Abort(.badRequest, reason: "Unsupported apiVersion")
        }
        let normalizedUpsId = dto.upsId.lowercased()
        let environment = dto.resolvedEnvironment

        let tokenHash = DeviceTokenCrypto.hash(dto.deviceToken)

        // Find device registration
        if let device = try await Device.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .filter(\.$upsId == normalizedUpsId)
            .filter(\.$environment == environment)
            .first()
        {
            try await device.delete(on: req.db)
        }

        // Succeed even if not found (idempotent)
        return .ok
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
