import Fluent

struct AddInstallationIdToDevice: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("devices")
            .field("installation_id", .uuid)
            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("devices")
            .deleteField("installation_id")
            .update()
    }
}
