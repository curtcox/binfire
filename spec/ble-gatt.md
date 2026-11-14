# Bluetooth LE transfer

One GATT service is shared by all four ports, so any port can send to any
other. The UUIDs come from `config/binfire.config.json` `ble`.

| Item | UUID | Properties |
| --- | --- | --- |
| Service | `ble.serviceUuid` | primary, advertised |
| Control | `ble.controlCharacteristicUuid` | write (with response), notify |
| Data | `ble.dataCharacteristicUuid` | notify |

Roles: the **sender** is the peripheral. It advertises the service with a local
name of `binfire` plus the first 4 characters of its nonce. The **receiver** is
the central: it scans, lists senders, and connects.

## Messages

Control messages are UTF-8 JSON objects, each at most 512 bytes. A message
longer than the ATT payload is split by the sender of that message into
consecutive writes or notifications. Each piece is prefixed with one byte:
`0x01` for "more follows" or `0x00` for "last".

1. Receiver subscribes to Control and Data, requests the largest MTU (517),
   then writes `{"t":"hello","v":1,"nonce":"<16 random bytes, base64url>"}`.
2. Sender notifies
   `{"t":"offer","v":1,"nonce":"<16 bytes b64url>","kind":"url|cid|site","name":"…","total":n,"cid":"<payload CID>"}`.
3. Both sides show the **confirmation code**:
   `code = uint32_be(SHA-256(ascii("binfire-ble-v1") || senderNonce || receiverNonce)[0..4]) mod 10000`,
   shown as 4 digits with leading zeros. Nonces are the raw 16 bytes.
4. The receiver's user confirms that the codes match (and that the size is
   acceptable). The receiver writes `{"t":"accept"}`, or `{"t":"reject"}`.
5. The sender notifies Data with chunk frames (transfer.md). Chunk size is
   `MTU - 3 - 29 - len(cid)`.
6. The receiver writes `{"t":"missing","indexes":[…]}` (at most 100 indexes
   per message) for any gaps after the sender's `{"t":"sent"}` notification. The
   sender resends those frames and then sends `sent` again.
7. On success the receiver writes `{"t":"done","cid":"…"}`. On failure it
   writes `{"t":"error","error":"<code>"}`. Either side may disconnect after
   that.

Timeouts: 30 s waiting for confirmation, 10 s of no Data progress. Received
payloads open with `run=0` (PLAN §10).

## Fixture `ble.json`

`{ "codes": [{ "senderNonceHex", "receiverNonceHex", "code": "0042" }] }`
