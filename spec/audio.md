# Audio (data over sound)

Audio uses [ggwave](https://github.com/ggerganov/ggwave) (MIT), compiled into
each port. Bandwidth is tens of bytes per second, so audio carries only short
text.

- **Payload:** UTF-8 text of at most 140 bytes (ggwave's limit). It is either
  a bare CID, or a binfire link (`https://D/a/…`, `/c#…`, `/s#…`) that fits.
  Senders refuse anything else and offer QR or BLE instead.
- **Protocol:** `GGWAVE_PROTOCOL_AUDIBLE_FAST` by default, with
  `ULTRASOUND_FAST` as an option. Volume is 50, the sample rate is 48 kHz, and
  the format is mono float32.
- **Receive:** the decoded text goes through `route()` (links.md). Audio
  results open with `run=0`.

`audioPayloadOK(text)` → `true` when `text` is at most 140 UTF-8 bytes and
`route(text).action` is `load-cid`, `open-site`, or `open-app` via a
`https://D/a/` link.

## Fixture `audio.json`

`{ "payloads": [{ "text", "ok": true|false }], "waveforms": [{ "text", "protocol", "wavFile" }] }`

The `waveforms` entries point to reference WAV files in `shared/fixtures/audio/`.
Ports decode them in CI, so no microphone is needed. Waveforms are added in M7.
