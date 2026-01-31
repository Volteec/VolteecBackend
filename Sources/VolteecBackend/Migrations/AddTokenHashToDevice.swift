import Fluent

struct AddTokenHashToDevice: AsyncMigration {
    func prepare(on database: any Database) async throws {
        // Add token_hash column (nullable)
        try await database.schema("devices")
            .field("token_hash", .string)
            .update()

        // Add index on token_hash for efficient lookups
        try await database.schema("devices")
            .unique(on: "token_hash", name: "idx_devices_token_hash")
            .update()
    }

    func revert(on database: any Database) async throws {
        // Drop index
        try await database.schema("devices")
            .deleteUnique(on: "token_hash")
            .update()

        // Drop column
        try await database.schema("devices")
            .deleteField("token_hash")
            .update()
    }
}
