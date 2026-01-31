import Fluent
import SQLKit

struct EnforceLowercaseUPSId: AsyncMigration {
    enum MigrationError: Error {
        case unsupportedDatabase
    }

    func prepare(on database: any Database) async throws {
        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        try await sql.raw("UPDATE ups SET ups_id = lower(ups_id);").run()
        try await sql.raw("""
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_constraint WHERE conname = 'ups_id_lowercase'
                ) THEN
                    ALTER TABLE ups
                    ADD CONSTRAINT ups_id_lowercase
                    CHECK (ups_id = lower(ups_id));
                END IF;
            END $$;
            """).run()
    }

    func revert(on database: any Database) async throws {
        guard let sql = database as? (any SQLDatabase) else {
            throw MigrationError.unsupportedDatabase
        }

        try await sql.raw("ALTER TABLE ups DROP CONSTRAINT IF EXISTS ups_id_lowercase;").run()
    }
}
