import Foundation

enum BuildInfo {
    // Defaults for local/dev builds. Docker/CI can overwrite at build time.
    static let softwareVersion = "1.1.0"
    static let protocolVersion = "1.1"
    static let commit = "unknown"
    static let buildDate = "unknown"
}
