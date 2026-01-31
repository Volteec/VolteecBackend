import Fluent

struct CreateUPS: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let dataSourceEnum = try await database.enum("data_source")
            .case("nut")
            .case("snmp")
            .create()

        let statusEnum = try await database.enum("ups_status")
            .case("online")
            .case("on_battery")
            .case("ups_offline")
            .create()

        try await database.schema("ups")
            .id()
            .field("ups_id", .string, .required)
            .field("data_source", dataSourceEnum, .required)
            .field("status", statusEnum, .required)
            .field("battery", .int)
            .field("runtime", .int)
            .field("load", .int)
            .field("input_voltage", .double)
            .field("output_voltage", .double)
            .field("updated_at", .datetime)
            .field("created_at", .datetime)
            .unique(on: "ups_id")
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("ups").delete()
        try await database.enum("ups_status").delete()
        try await database.enum("data_source").delete()
    }
}
