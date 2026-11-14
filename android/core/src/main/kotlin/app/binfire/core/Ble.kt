package app.binfire.core

import java.security.MessageDigest

/** Bluetooth LE handshake helpers (`spec/ble-gatt.md`). */
object Ble {
    /** Nonce length in bytes. */
    const val NONCE_BYTES = 16

    /** Largest control message, in bytes. */
    const val MAX_CONTROL_MESSAGE = 512

    /**
     * The 4-digit confirmation code both sides show:
     * `uint32_be(SHA-256("binfire-ble-v1" || sender || receiver)[0..4]) mod 10000`.
     */
    fun confirmationCode(senderNonce: ByteArray, receiverNonce: ByteArray): String {
        require(senderNonce.size == NONCE_BYTES && receiverNonce.size == NONCE_BYTES) { "nonces must be $NONCE_BYTES bytes" }
        val md = MessageDigest.getInstance("SHA-256")
        md.update("binfire-ble-v1".toByteArray(Charsets.US_ASCII))
        md.update(senderNonce)
        md.update(receiverNonce)
        val d = md.digest()
        val v = ((d[0].toLong() and 0xff) shl 24) or ((d[1].toLong() and 0xff) shl 16) or
            ((d[2].toLong() and 0xff) shl 8) or (d[3].toLong() and 0xff)
        return (v % 10000).toString().padStart(4, '0')
    }

    /** Data chunk size for an ATT [mtu] and payload [cid]: `MTU - 3 - 29 - len(cid)`. */
    fun chunkSize(mtu: Int, cid: String): Int = mtu - 3 - 29 - cid.length
}
