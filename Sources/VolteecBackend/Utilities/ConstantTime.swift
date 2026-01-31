import Foundation
import Crypto

enum ConstantTime {
    static func equals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        if left.count != right.count {
            return false
        }
        var result: UInt8 = 0
        for (a, b) in zip(left, right) {
            result |= a ^ b
        }
        return result == 0
    }

    static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
