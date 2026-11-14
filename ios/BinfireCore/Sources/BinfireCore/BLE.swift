import CryptoKit
import Foundation

/// Bluetooth LE transfer helpers (`spec/ble-gatt.md`).
public enum BLE {
    /// Nonce length in bytes.
    public static let nonceLength = 16
    /// Largest control message, in bytes.
    public static let maxControlMessageBytes = 512
    /// Largest number of indexes in one `missing` message.
    public static let maxMissingIndexes = 100

    /// The 4-digit confirmation code both sides show:
    /// `uint32_be(SHA-256("binfire-ble-v1" || senderNonce || receiverNonce)[0..4]) mod 10000`.
    public static func confirmationCode(senderNonce: Data, receiverNonce: Data) -> String {
        var input = Data("binfire-ble-v1".utf8)
        input.append(senderNonce)
        input.append(receiverNonce)
        let digest = Array(SHA256.hash(data: input))
        let n = UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3])
        let code = String(n % 10000)
        return String(repeating: "0", count: 4 - code.count) + code
    }

    /// Data chunk size for a negotiated MTU: `MTU - 3 - 29 - len(cid)`.
    public static func chunkSize(mtu: Int, cid: String) -> Int {
        mtu - 3 - 29 - cid.utf8.count
    }
}
