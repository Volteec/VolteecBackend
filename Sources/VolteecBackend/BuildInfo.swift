import Foundation

enum BuildInfo {
    // Local/dev fallback values only. Public release identity comes from Git tags
    // injected as Docker build arguments during CI/release builds.
    static let softwareVersion = "1.1.0"
    static let protocolVersion = "1.1"
    static let commit = "unknown"
    static let buildDate = "unknown"
}
