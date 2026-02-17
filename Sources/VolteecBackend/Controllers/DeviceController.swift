import Vapor
import Fluent

struct DeviceController: RouteCollection {
    private static let supportedLifecycleVersions: Set<String> = ["1.0", "1.1"]

    func boot(routes: any RoutesBuilder) throws {
        routes.post("register-device", use: registerDevice)
        routes.post("unregister-device", use: unregisterDevice)
    }

    // POST /register-device
    func registerDevice(req: Request) async throws -> HTTPStatus {
        let dto = try req.content.decode(DeviceRegistrationDTO.self)
        try validateLifecycleVersion(dto.apiVersion)
        let crypto = try DeviceTokenCrypto()

        let normalizedUpsId = dto.upsId.lowercased()
        let environment = dto.resolvedEnvironment
        let normalizedAlias = dto.upsAlias?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let localServerId = RelayConfig.get(from: req.application)?.serverId

        let encryptedToken = try crypto.encrypt(plaintext: dto.deviceToken)
        let tokenHash = DeviceTokenCrypto.hash(dto.deviceToken)
        let installationId = dto.installationId
        let upsHidden = dto.upsHidden ?? false

        // Check if device already registered.
        // Prefer an exact match including installationId when available.
        var existingQuery = Device.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .filter(\.$upsId == normalizedUpsId)
            .filter(\.$environment == environment)
        if let localServerId {
            existingQuery = existingQuery.filter(\.$serverId == localServerId)
        }
        let existingCandidates = try await existingQuery.all()

        let existingDevice = existingCandidates.first { candidate in
            candidate.installationId == installationId
        } ?? {
            // Backward compatibility for older registrations without installationId.
            guard installationId == nil else { return nil }
            return existingCandidates.first { $0.installationId == nil }
        }()

        if let existingDevice = existingDevice {
            existingDevice.deviceToken = encryptedToken
            existingDevice.upsAlias = normalizedAlias
            existingDevice.installationId = installationId
            existingDevice.serverId = localServerId
            existingDevice.upsHidden = dto.upsHidden ?? existingDevice.upsHidden
            try await existingDevice.update(on: req.db)
            return .ok
        }

        // Create new device registration
        let device = Device(
            upsId: normalizedUpsId,
            upsAlias: normalizedAlias,
            deviceToken: encryptedToken,
            tokenHash: tokenHash,
            installationId: installationId,
            serverId: localServerId,
            upsHidden: upsHidden,
            environment: environment
        )

        try await device.create(on: req.db)
        return .created
    }

    // POST /unregister-device
    func unregisterDevice(req: Request) async throws -> HTTPStatus {
        let dto = try req.content.decode(DeviceRegistrationDTO.self)
        try validateLifecycleVersion(dto.apiVersion)
        let normalizedUpsId = dto.upsId.lowercased()
        let environment = dto.resolvedEnvironment
        let installationId = dto.installationId
        let localServerId = RelayConfig.get(from: req.application)?.serverId

        let tokenHash = DeviceTokenCrypto.hash(dto.deviceToken)

        // Find device registration.
        // Prefer exact installation match when available.
        var matchingQuery = Device.query(on: req.db)
            .filter(\.$tokenHash == tokenHash)
            .filter(\.$upsId == normalizedUpsId)
            .filter(\.$environment == environment)
        if let localServerId {
            matchingQuery = matchingQuery.filter(\.$serverId == localServerId)
        }
        let matchingDevices = try await matchingQuery.all()

        let deviceToDelete = matchingDevices.first { device in
            device.installationId == installationId
        } ?? {
            guard installationId == nil else { return nil }
            return matchingDevices.first { $0.installationId == nil }
        }()

        if let device = deviceToDelete {
            try await device.delete(on: req.db)
        }

        // Succeed even if not found (idempotent)
        return .ok
    }

    private func validateLifecycleVersion(_ apiVersion: String?) throws {
        guard let apiVersion else {
            return
        }

        let normalizedVersion = apiVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedVersion.isEmpty {
            return
        }

        guard Self.supportedLifecycleVersions.contains(normalizedVersion) else {
            throw Abort(
                .badRequest,
                reason: "Unsupported apiVersion '\(normalizedVersion)'. Supported versions: 1.0, 1.1. Omit apiVersion for backward compatibility."
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
