import Fluent

struct AddNUTFieldsToUPS: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("ups")
            // Status
            .field("ups_status_raw", .string)

            // Battery
            .field("battery_percent", .int)
            .field("battery_charge_warning", .int)
            .field("battery_charge_low", .int)
            .field("battery_runtime_seconds", .int)
            .field("battery_runtime_low_seconds", .int)
            .field("battery_type", .string)
            .field("battery_manufacturer_date", .string)
            .field("battery_voltage", .double)
            .field("battery_voltage_nominal", .double)

            // Load/Power
            .field("load_percent", .int)
            .field("ups_real_power_nominal", .int)

            // Input/Output
            .field("input_voltage_nominal", .double)
            .field("input_transfer_low", .double)
            .field("input_transfer_high", .double)

            // Device/UPS Identity
            .field("device_manufacturer", .string)
            .field("device_model", .string)
            .field("device_serial", .string)
            .field("device_type", .string)
            .field("ups_manufacturer", .string)
            .field("ups_model", .string)
            .field("ups_serial", .string)
            .field("ups_vendor_id", .string)
            .field("ups_product_id", .string)

            // Diagnostics/Timers
            .field("ups_test_result", .string)
            .field("ups_beeper_status", .string)
            .field("ups_delay_shutdown", .int)
            .field("ups_delay_start", .int)
            .field("ups_timer_shutdown", .int)
            .field("ups_timer_start", .int)
            .field("driver_name", .string)
            .field("driver_version", .string)
            .field("driver_version_data", .string)
            .field("driver_version_internal", .string)
            .field("driver_version_usb", .string)
            .field("driver_parameter_pollfreq", .int)
            .field("driver_parameter_pollinterval", .int)
            .field("driver_parameter_port", .string)
            .field("driver_parameter_synchronous", .string)
            .field("driver_parameter_vendor_id", .string)

            // Polling state
            .field("consecutive_failures", .int, .required, .sql(.default(0)))

            .update()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("ups")
            // Status
            .deleteField("ups_status_raw")

            // Battery
            .deleteField("battery_percent")
            .deleteField("battery_charge_warning")
            .deleteField("battery_charge_low")
            .deleteField("battery_runtime_seconds")
            .deleteField("battery_runtime_low_seconds")
            .deleteField("battery_type")
            .deleteField("battery_manufacturer_date")
            .deleteField("battery_voltage")
            .deleteField("battery_voltage_nominal")

            // Load/Power
            .deleteField("load_percent")
            .deleteField("ups_real_power_nominal")

            // Input/Output
            .deleteField("input_voltage_nominal")
            .deleteField("input_transfer_low")
            .deleteField("input_transfer_high")

            // Device/UPS Identity
            .deleteField("device_manufacturer")
            .deleteField("device_model")
            .deleteField("device_serial")
            .deleteField("device_type")
            .deleteField("ups_manufacturer")
            .deleteField("ups_model")
            .deleteField("ups_serial")
            .deleteField("ups_vendor_id")
            .deleteField("ups_product_id")

            // Diagnostics/Timers
            .deleteField("ups_test_result")
            .deleteField("ups_beeper_status")
            .deleteField("ups_delay_shutdown")
            .deleteField("ups_delay_start")
            .deleteField("ups_timer_shutdown")
            .deleteField("ups_timer_start")
            .deleteField("driver_name")
            .deleteField("driver_version")
            .deleteField("driver_version_data")
            .deleteField("driver_version_internal")
            .deleteField("driver_version_usb")
            .deleteField("driver_parameter_pollfreq")
            .deleteField("driver_parameter_pollinterval")
            .deleteField("driver_parameter_port")
            .deleteField("driver_parameter_synchronous")
            .deleteField("driver_parameter_vendor_id")

            // Polling state
            .deleteField("consecutive_failures")

            .update()
    }
}
