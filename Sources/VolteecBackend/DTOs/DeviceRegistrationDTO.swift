import Vapor

struct DeviceRegistrationDTO: Content {
    let apiVersion: String
    let upsId: String
    let upsAlias: String?
    let deviceToken: String
    let environment: APNSEnvironment?

    var resolvedEnvironment: APNSEnvironment {
        environment ?? .sandbox
    }
}
