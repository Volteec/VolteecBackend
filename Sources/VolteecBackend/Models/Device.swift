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

    @OptionalField(key: "installation_id")
    var installationId: UUID?

    @OptionalField(key: "server_id")
    var serverId: String?

    @Field(key: "ups_hidden")
    var upsHidden: Bool

    @Enum(key: "environment")
    var environment: PushEnvironment

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
        installationId: UUID? = nil,
        serverId: String? = nil,
        upsHidden: Bool = false,
        environment: PushEnvironment
    ) {
        self.id = id
        self.upsId = upsId
        self.upsAlias = upsAlias
        self.deviceToken = deviceToken
        self.tokenHash = tokenHash
        self.installationId = installationId
        self.serverId = serverId
        self.upsHidden = upsHidden
        self.environment = environment
    }
}
