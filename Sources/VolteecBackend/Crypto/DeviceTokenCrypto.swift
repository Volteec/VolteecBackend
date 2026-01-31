import Foundation
import Crypto

/// AES-GCM encryption/decryption for device tokens.
/// Uses a 256-bit key loaded from the DEVICE_TOKEN_KEY environment variable.
/// Format: base64(nonce[12] + ciphertext + tag[16])
struct DeviceTokenCrypto {
    private let key: SymmetricKey

    enum CryptoError: Error {
        case missingKey
        case invalidKeyFormat
        case encryptionFailed
    }

    init() throws {
        guard let keyBase64 = ProcessInfo.processInfo.environment["DEVICE_TOKEN_KEY"] else {
            throw CryptoError.missingKey
        }
        guard let keyData = Data(base64Encoded: keyBase64), keyData.count == 32 else {
            throw CryptoError.invalidKeyFormat
        }
        self.key = SymmetricKey(data: keyData)
    }

    func encrypt(plaintext: String) throws -> String {
        guard let data = plaintext.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)

        var combined = Data()
        combined.append(contentsOf: nonce)
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)

        return combined.base64EncodedString()
    }

    func decrypt(ciphertext: String) -> String? {
        guard let combined = Data(base64Encoded: ciphertext) else {
            return nil
        }
        guard combined.count >= 28 else {
            return nil
        }

        do {
            let nonce = try AES.GCM.Nonce(data: combined.prefix(12))
            let tag = combined.suffix(16)
            let cipherTextData = combined.dropFirst(12).dropLast(16)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipherTextData, tag: tag)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return String(data: decryptedData, encoding: .utf8)
        } catch {
            return nil
        }
    }

    static func hash(_ token: String) -> String {
        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
