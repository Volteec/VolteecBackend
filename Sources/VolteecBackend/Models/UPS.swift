import Fluent
import Vapor

final class UPS: Model, Content, @unchecked Sendable {
    static let schema = "ups"

    // MARK: - Properties

    @ID(key: .id)
    var id: UUID?

    @Field(key: "ups_id")
    var upsId: String

    @Enum(key: "data_source")
    var dataSource: DataSource

    @Enum(key: "status")
    var status: UPSStatus

    @OptionalField(key: "battery")
    var battery: Int?

    @OptionalField(key: "runtime")
    var runtime: Int?

    @OptionalField(key: "load")
    var load: Int?

    @OptionalField(key: "input_voltage")
    var inputVoltage: Double?

    @OptionalField(key: "output_voltage")
    var outputVoltage: Double?

    // MARK: - Extended NUT Fields (V1.1)

    // Status
    @OptionalField(key: "ups_status_raw")
    var upsStatusRaw: String?

    // Battery
    @OptionalField(key: "battery_percent")
    var batteryPercent: Int?

    @OptionalField(key: "battery_charge_warning")
    var batteryChargeWarning: Int?

    @OptionalField(key: "battery_charge_low")
    var batteryChargeLow: Int?

    @OptionalField(key: "battery_runtime_seconds")
    var batteryRuntimeSeconds: Int?

    @OptionalField(key: "battery_runtime_low_seconds")
    var batteryRuntimeLowSeconds: Int?

    @OptionalField(key: "battery_type")
    var batteryType: String?

    @OptionalField(key: "battery_manufacturer_date")
    var batteryManufacturerDate: String?

    @OptionalField(key: "battery_voltage")
    var batteryVoltage: Double?

    @OptionalField(key: "battery_voltage_nominal")
    var batteryVoltageNominal: Double?

    // Load/Power
    @OptionalField(key: "load_percent")
    var loadPercent: Int?

    @OptionalField(key: "ups_real_power_nominal")
    var upsRealPowerNominal: Int?

    // Input/Output
    @OptionalField(key: "input_voltage_nominal")
    var inputVoltageNominal: Double?

    @OptionalField(key: "input_transfer_low")
    var inputTransferLow: Double?

    @OptionalField(key: "input_transfer_high")
    var inputTransferHigh: Double?

    // Device/UPS Identity
    @OptionalField(key: "device_manufacturer")
    var deviceManufacturer: String?

    @OptionalField(key: "device_model")
    var deviceModel: String?

    @OptionalField(key: "device_serial")
    var deviceSerial: String?

    @OptionalField(key: "device_type")
    var deviceType: String?

    @OptionalField(key: "ups_manufacturer")
    var upsManufacturer: String?

    @OptionalField(key: "ups_model")
    var upsModel: String?

    @OptionalField(key: "ups_serial")
    var upsSerial: String?

    @OptionalField(key: "ups_vendor_id")
    var upsVendorId: String?

    @OptionalField(key: "ups_product_id")
    var upsProductId: String?

    // Diagnostics/Timers
    @OptionalField(key: "ups_test_result")
    var upsTestResult: String?

    @OptionalField(key: "ups_beeper_status")
    var upsBeeperStatus: String?

    @OptionalField(key: "ups_delay_shutdown")
    var upsDelayShutdown: Int?

    @OptionalField(key: "ups_delay_start")
    var upsDelayStart: Int?

    @OptionalField(key: "ups_timer_shutdown")
    var upsTimerShutdown: Int?

    @OptionalField(key: "ups_timer_start")
    var upsTimerStart: Int?

    @OptionalField(key: "driver_name")
    var driverName: String?

    @OptionalField(key: "driver_version")
    var driverVersion: String?

    @OptionalField(key: "driver_version_data")
    var driverVersionData: String?

    @OptionalField(key: "driver_version_internal")
    var driverVersionInternal: String?

    @OptionalField(key: "driver_version_usb")
    var driverVersionUsb: String?

    @OptionalField(key: "driver_parameter_pollfreq")
    var driverParameterPollfreq: Int?

    @OptionalField(key: "driver_parameter_pollinterval")
    var driverParameterPollinterval: Int?

    @OptionalField(key: "driver_parameter_port")
    var driverParameterPort: String?

    @OptionalField(key: "driver_parameter_synchronous")
    var driverParameterSynchronous: String?

    @OptionalField(key: "driver_parameter_vendor_id")
    var driverParameterVendorId: String?

    // Polling state
    @Field(key: "consecutive_failures")
    var consecutiveFailures: Int

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // MARK: - Initializers

    init() {
        self.consecutiveFailures = 0
    }

    init(
        id: UUID? = nil,
        upsId: String,
        dataSource: DataSource,
        status: UPSStatus,
        battery: Int? = nil,
        runtime: Int? = nil,
        load: Int? = nil,
        inputVoltage: Double? = nil,
        outputVoltage: Double? = nil,
        consecutiveFailures: Int = 0
    ) {
        self.id = id
        self.upsId = upsId
        self.dataSource = dataSource
        self.status = status
        self.battery = battery
        self.runtime = runtime
        self.load = load
        self.inputVoltage = inputVoltage
        self.outputVoltage = outputVoltage
        self.consecutiveFailures = consecutiveFailures
    }
}
