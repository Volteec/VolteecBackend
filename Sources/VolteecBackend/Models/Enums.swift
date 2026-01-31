import Vapor

// MARK: - DataSource

enum DataSource: String, Codable {
    case nut
    case snmp
}

// MARK: - UPSStatus

enum UPSStatus: String, Codable {
    case online
    case on_battery
    case ups_offline
}

// MARK: - APNSEnvironment

enum APNSEnvironment: String, Codable {
    case sandbox
    case production
}
