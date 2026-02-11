import Fluent

struct AddUpsAliasToDevice: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("devices")
            .field("ups_alias", .string)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("devices")
            .deleteField("ups_alias")
            .update()
    }
}
