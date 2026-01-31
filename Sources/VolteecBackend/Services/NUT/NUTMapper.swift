import Foundation

/// Mapped NUT data ready for database
struct NUTMappedData {
    let upsId: String
    let status: UPSStatus
    let upsStatusRaw: String?

    // Battery fields
    let batteryPercent: Int?
    let batteryChargeWarning: Int?
    let batteryChargeLow: Int?
    let batteryRuntimeSeconds: Int?
    let batteryRuntimeLowSeconds: Int?
    let batteryType: String?
    let batteryManufacturerDate: String?
    let batteryVoltage: Double?
    let batteryVoltageNominal: Double?

    // Load and power
    let loadPercent: Int?
    let upsRealPowerNominal: Int?

    // Input fields
    let inputVoltage: Double?
    let inputVoltageNominal: Double?
    let inputTransferLow: Double?
    let inputTransferHigh: Double?

    // Output fields
    let outputVoltage: Double?

    // Device fields
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceSerial: String?
    let deviceType: String?

    // UPS fields
    let upsManufacturer: String?
    let upsModel: String?
    let upsSerial: String?
    let upsVendorId: String?
    let upsProductId: String?
    let upsTestResult: String?
    let upsBeeperStatus: String?
    let upsDelayShutdown: Int?
    let upsDelayStart: Int?
    let upsTimerShutdown: Int?
    let upsTimerStart: Int?

    // Driver fields
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

    // Derived fields for backwards compatibility
    let battery: Int?
    let runtime: Int?
    let load: Int?
}

struct NUTMapper {
    /// Map NUT variables dictionary to structured data
    static func map(variables: [String: String], upsName: String) -> NUTMappedData {
        let upsId = upsName.lowercased()
        let upsStatusRaw = variables["ups.status"]
        let status = parseStatus(raw: upsStatusRaw)

        func parseDouble(_ key: String) -> Double? {
            guard let value = variables[key] else { return nil }
            return Double(value)
        }

        func parseRoundedInt(_ key: String) -> Int? {
            parseDouble(key).map { Int($0.rounded()) }
        }

        func parseTruncatedInt(_ key: String) -> Int? {
            parseDouble(key).map { Int($0) }
        }

        // Battery fields
        let batteryPercent = parseRoundedInt("battery.charge")
        let batteryChargeWarning = parseRoundedInt("battery.charge.warning")
        let batteryChargeLow = parseRoundedInt("battery.charge.low")
        let batteryRuntimeSeconds = parseTruncatedInt("battery.runtime")
        let batteryRuntimeLowSeconds = parseTruncatedInt("battery.runtime.low")
        let batteryType = variables["battery.type"]
        let batteryManufacturerDate = variables["battery.mfr.date"]
        let batteryVoltage = parseDouble("battery.voltage")
        let batteryVoltageNominal = parseDouble("battery.voltage.nominal")

        // Load and power
        let loadPercent = parseRoundedInt("ups.load")
        let upsRealPowerNominal = parseTruncatedInt("ups.realpower.nominal")

        // Input fields
        let inputVoltage = parseDouble("input.voltage")
        let inputVoltageNominal = parseDouble("input.voltage.nominal")
        let inputTransferLow = parseDouble("input.transfer.low")
        let inputTransferHigh = parseDouble("input.transfer.high")

        // Output fields
        let outputVoltage = parseDouble("output.voltage")

        // Device fields
        let deviceManufacturer = variables["device.mfr"]
        let deviceModel = variables["device.model"]
        let deviceSerial = variables["device.serial"]
        let deviceType = variables["device.type"]

        // UPS fields
        let upsManufacturer = variables["ups.mfr"]
        let upsModel = variables["ups.model"]
        let upsSerial = variables["ups.serial"]
        let upsVendorId = variables["ups.vendorid"]
        let upsProductId = variables["ups.productid"]
        let upsTestResult = variables["ups.test.result"]
        let upsBeeperStatus = variables["ups.beeper.status"]
        let upsDelayShutdown = parseTruncatedInt("ups.delay.shutdown")
        let upsDelayStart = parseTruncatedInt("ups.delay.start")
        let upsTimerShutdown = parseTruncatedInt("ups.timer.shutdown")
        let upsTimerStart = parseTruncatedInt("ups.timer.start")

        // Driver fields
        let driverName = variables["driver.name"]
        let driverVersion = variables["driver.version"]
        let driverVersionData = variables["driver.version.data"]
        let driverVersionInternal = variables["driver.version.internal"]
        let driverVersionUsb = variables["driver.version.usb"]
        let driverParameterPollfreq = parseTruncatedInt("driver.parameter.pollfreq")
        let driverParameterPollinterval = parseTruncatedInt("driver.parameter.pollinterval")
        let driverParameterPort = variables["driver.parameter.port"]
        let driverParameterSynchronous = variables["driver.parameter.synchronous"]
        let driverParameterVendorId = variables["driver.parameter.vendorid"]

        // Derived fields for backwards compatibility
        let battery = batteryPercent
        let runtime = batteryRuntimeSeconds.map { Int(floor(Double($0) / 60.0)) }
        let load = loadPercent

        return NUTMappedData(
            upsId: upsId,
            status: status,
            upsStatusRaw: upsStatusRaw,
            batteryPercent: batteryPercent,
            batteryChargeWarning: batteryChargeWarning,
            batteryChargeLow: batteryChargeLow,
            batteryRuntimeSeconds: batteryRuntimeSeconds,
            batteryRuntimeLowSeconds: batteryRuntimeLowSeconds,
            batteryType: batteryType,
            batteryManufacturerDate: batteryManufacturerDate,
            batteryVoltage: batteryVoltage,
            batteryVoltageNominal: batteryVoltageNominal,
            loadPercent: loadPercent,
            upsRealPowerNominal: upsRealPowerNominal,
            inputVoltage: inputVoltage,
            inputVoltageNominal: inputVoltageNominal,
            inputTransferLow: inputTransferLow,
            inputTransferHigh: inputTransferHigh,
            outputVoltage: outputVoltage,
            deviceManufacturer: deviceManufacturer,
            deviceModel: deviceModel,
            deviceSerial: deviceSerial,
            deviceType: deviceType,
            upsManufacturer: upsManufacturer,
            upsModel: upsModel,
            upsSerial: upsSerial,
            upsVendorId: upsVendorId,
            upsProductId: upsProductId,
            upsTestResult: upsTestResult,
            upsBeeperStatus: upsBeeperStatus,
            upsDelayShutdown: upsDelayShutdown,
            upsDelayStart: upsDelayStart,
            upsTimerShutdown: upsTimerShutdown,
            upsTimerStart: upsTimerStart,
            driverName: driverName,
            driverVersion: driverVersion,
            driverVersionData: driverVersionData,
            driverVersionInternal: driverVersionInternal,
            driverVersionUsb: driverVersionUsb,
            driverParameterPollfreq: driverParameterPollfreq,
            driverParameterPollinterval: driverParameterPollinterval,
            driverParameterPort: driverParameterPort,
            driverParameterSynchronous: driverParameterSynchronous,
            driverParameterVendorId: driverParameterVendorId,
            battery: battery,
            runtime: runtime,
            load: load
        )
    }

    /// Parse status flags from ups.status raw string
    /// "OL" -> online, "OB" or "LB" -> on_battery, else ups_offline
    static func parseStatus(raw: String?) -> UPSStatus {
        guard let raw = raw else {
            return .ups_offline
        }

        let uppercased = raw.uppercased()

        // Check for online status
        if uppercased.contains("OL") {
            return .online
        }

        // Check for battery status
        if uppercased.contains("OB") || uppercased.contains("LB") {
            return .on_battery
        }

        // Default to offline
        return .ups_offline
    }
}
