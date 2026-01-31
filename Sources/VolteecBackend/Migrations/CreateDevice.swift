import Fluent

struct CreateDevice: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let environmentEnum = try await database.enum("apns_environment")
            .case("sandbox")
            .case("production")
            .create()

        try await database.schema("devices")
            .id()
            .field("ups_id", .string, .required)
            .field("device_token", .string, .required)
            .field("environment", environmentEnum, .required)
            .field("created_at", .datetime)
            .unique(on: "ups_id", "device_token", "environment")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("devices").delete()
        try await database.enum("apns_environment").delete()
    }
}
