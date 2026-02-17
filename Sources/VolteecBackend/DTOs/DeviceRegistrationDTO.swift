import Vapor

struct DeviceRegistrationDTO: Content {
    let apiVersion: String?
    let upsId: String
    let upsAlias: String?
    let deviceToken: String
    let environment: PushEnvironment?
    let installationId: UUID?
    let upsHidden: Bool?

    var resolvedEnvironment: PushEnvironment {
        environment ?? .sandbox
    }
}
