import Fluent
import Vapor

final class Device: Model, Content, @unchecked Sendable {
    static let schema = "devices"

    // MARK: - Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "ups_id")
    var upsId: String

    @Field(key: "ups_alias")
    var upsAlias: String?

    @Field(key: "device_token")
    var deviceToken: String

    @Field(key: "token_hash")
    var tokenHash: String?

    @Enum(key: "environment")
    var environment: APNSEnvironment

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // MARK: - Initializers

    init() {}

    init(
        id: UUID? = nil,
        upsId: String,
        upsAlias: String? = nil,
        deviceToken: String,
        tokenHash: String? = nil,
        environment: APNSEnvironment
    ) {
        self.id = id
        self.upsId = upsId
        self.upsAlias = upsAlias
        self.deviceToken = deviceToken
        self.tokenHash = tokenHash
        self.environment = environment
    }
}
