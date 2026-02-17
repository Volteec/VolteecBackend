import Fluent
import SQLKit

struct AddServerAndHiddenToDevice: AsyncMigration {
    enum MigrationError: Error {
        case unsupportedDatabase
    }

    func prepare(on database: any Database) async throws {
        try await database.schema("devices")
            .field("server_id", .string)
            .field("ups_hidden", .bool, .required, .sql(.default(false)))
            .update()

        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_devices_targeting
            ON devices (ups_id, environment, server_id, ups_hidden);
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        try await sql.raw("DROP INDEX IF EXISTS idx_devices_targeting;").run()

        try await database.schema("devices")
            .deleteField("server_id")
            .deleteField("ups_hidden")
            .update()
    }
}
