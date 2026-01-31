import Vapor

struct UPSStatusDTO: Content {
    // MARK: - Versioning
    let apiVersion: String

    // MARK: - Core Fields
    let upsId: String
    let status: UPSStatus
    let dataSource: DataSource
    let battery: Int?
    let runtime: Int?
    let load: Int?
    let inputVoltage: Double?
    let outputVoltage: Double?
    let updatedAt: String

    // MARK: - Extended NUT Fields

    // Status
    let upsStatusRaw: String?

    // Battery
    let batteryPercent: Int?
    let batteryChargeWarning: Int?
    let batteryChargeLow: Int?
    let batteryRuntimeSeconds: Int?
    let batteryRuntimeLowSeconds: Int?
    let batteryType: String?
    let batteryManufacturerDate: String?
    let batteryVoltage: Double?
    let batteryVoltageNominal: Double?

    // Load/Power
    let loadPercent: Int?
    let upsRealPowerNominal: Int?

    // Input/Output
    let inputVoltageNominal: Double?
    let inputTransferLow: Double?
    let inputTransferHigh: Double?

    // Device/UPS Identity
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceSerial: String?
    let deviceType: String?
    let upsManufacturer: String?
    let upsModel: String?
    let upsSerial: String?
    let upsVendorId: String?
    let upsProductId: String?

    // Diagnostics/Timers
    let upsTestResult: String?
    let upsBeeperStatus: String?
    let upsDelayShutdown: Int?
    let upsDelayStart: Int?
    let upsTimerShutdown: Int?
    let upsTimerStart: Int?

    // Driver Information
    let driverName: String?
    let driverVersion: String?
    let driverVersionData: String?
    let driverVersionInternal: String?
    let driverVersionUsb: String?
    let driverParameterPollfreq: Int?
    let driverParameterPollinterval: Int?
    let driverParameterPort: String?
    let driverParameterSynchronous: String?
    let driverParameterVendorId: String?

    init(from ups: UPS) {
        self.apiVersion = "1.0"

        // Core fields
        self.upsId = ups.upsId.lowercased()
        self.status = ups.status
        self.dataSource = ups.dataSource
        self.battery = ups.battery
        self.runtime = ups.runtime
        self.load = ups.load
        self.inputVoltage = ups.inputVoltage
        self.outputVoltage = ups.outputVoltage
        self.updatedAt = ISO8601DateFormatter().string(from: Date())

        // Extended NUT fields
        self.upsStatusRaw = ups.upsStatusRaw
        self.batteryPercent = ups.batteryPercent
        self.batteryChargeWarning = ups.batteryChargeWarning
        self.batteryChargeLow = ups.batteryChargeLow
        self.batteryRuntimeSeconds = ups.batteryRuntimeSeconds
        self.batteryRuntimeLowSeconds = ups.batteryRuntimeLowSeconds
        self.batteryType = ups.batteryType
        self.batteryManufacturerDate = ups.batteryManufacturerDate
        self.batteryVoltage = ups.batteryVoltage
        self.batteryVoltageNominal = ups.batteryVoltageNominal
        self.loadPercent = ups.loadPercent
        self.upsRealPowerNominal = ups.upsRealPowerNominal
        self.inputVoltageNominal = ups.inputVoltageNominal
        self.inputTransferLow = ups.inputTransferLow
        self.inputTransferHigh = ups.inputTransferHigh
        self.deviceManufacturer = ups.deviceManufacturer
        self.deviceModel = ups.deviceModel
        self.deviceSerial = ups.deviceSerial
        self.deviceType = ups.deviceType
        self.upsManufacturer = ups.upsManufacturer
        self.upsModel = ups.upsModel
        self.upsSerial = ups.upsSerial
        self.upsVendorId = ups.upsVendorId
        self.upsProductId = ups.upsProductId
        self.upsTestResult = ups.upsTestResult
        self.upsBeeperStatus = ups.upsBeeperStatus
        self.upsDelayShutdown = ups.upsDelayShutdown
        self.upsDelayStart = ups.upsDelayStart
        self.upsTimerShutdown = ups.upsTimerShutdown
        self.upsTimerStart = ups.upsTimerStart
        self.driverName = ups.driverName
        self.driverVersion = ups.driverVersion
        self.driverVersionData = ups.driverVersionData
        self.driverVersionInternal = ups.driverVersionInternal
        self.driverVersionUsb = ups.driverVersionUsb
        self.driverParameterPollfreq = ups.driverParameterPollfreq
        self.driverParameterPollinterval = ups.driverParameterPollinterval
        self.driverParameterPort = ups.driverParameterPort
        self.driverParameterSynchronous = ups.driverParameterSynchronous
        self.driverParameterVendorId = ups.driverParameterVendorId
    }
}
