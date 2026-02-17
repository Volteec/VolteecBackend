import Fluent
import SQLKit

struct FixDeviceTokenHashIndex: AsyncMigration {
    enum MigrationError: Error {
        case unsupportedDatabase
    }

    func prepare(on database: any Database) async throws {
        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        // `AddTokenHashToDevice` created a UNIQUE constraint named `idx_devices_token_hash`.
        // In Postgres, this is not droppable via `DROP INDEX` while the constraint exists.
        try await sql.raw("ALTER TABLE devices DROP CONSTRAINT IF EXISTS idx_devices_token_hash;").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_devices_token_hash;").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_devices_token_hash_lookup;").run()

        // Recreate as a non-unique index for fast lookup without enforcing global uniqueness.
        try await sql.raw("""
            CREATE INDEX IF NOT EXISTS idx_devices_token_hash
            ON devices (token_hash);
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        try await sql.raw("DROP INDEX IF EXISTS idx_devices_token_hash;").run()
        try await sql.raw("DROP INDEX IF EXISTS idx_devices_token_hash_lookup;").run()

        // Restore the original UNIQUE constraint name for compatibility with older migration expectations.
        try await sql.raw("""
            ALTER TABLE devices
            ADD CONSTRAINT idx_devices_token_hash UNIQUE (token_hash);
            """).run()
    }
}
