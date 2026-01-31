import Foundation

/// Errors that can occur during NUT protocol operations
enum NUTError: Error, CustomStringConvertible {
    /// Failed to establish TCP connection to NUT server
    case connectionFailed(String)

    /// Operation timed out
    case timeout

    /// Authentication failed
    case authFailed(String)

    /// Failed to parse NUT protocol response
    case parseError(String)

    /// Requested UPS not found on server
    case upsNotFound(String)

    /// Channel closed unexpectedly
    case channelClosed

    /// Invalid response from server
    case invalidResponse(String)

    var description: String {
        switch self {
        case .connectionFailed(let message):
            return "NUT connection failed: \(message)"
        case .timeout:
            return "NUT operation timed out"
        case .authFailed(let message):
            return "NUT authentication failed: \(message)"
        case .parseError(let message):
            return "NUT parse error: \(message)"
        case .upsNotFound(let upsName):
            return "UPS '\(upsName)' not found on NUT server"
        case .channelClosed:
            return "NUT channel closed unexpectedly"
        case .invalidResponse(let message):
            return "Invalid NUT response: \(message)"
        }
    }
}
