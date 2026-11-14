# binfire specifications

These documents are the contract that all four ports implement. Where a spec
and a port disagree, the spec wins. Fix the port, or change the spec and the
fixtures in the same commit.

| Spec | Covers | Fixtures |
| --- | --- | --- |
| [registry.md](registry.md) | App registry format and URL matching | `registry.json` |
| [cid.md](cid.md) | 256t content identifiers: compute, validate, verify | `cid.json` |
| [state.md](state.md) | Classifying an app URL's state (FK precedence), lz-string, envelopes | `state.json`, `lz.json`, `envelope.json` |
| [links.md](links.md) | binfire link forms and the routing of any input text | `links.json` |
| [transfer.md](transfer.md) | Bundle container, chunk frames, `.binfire` files, QR text frames | `transfer.json` |
| [site-manifest.md](site-manifest.md) | Packaged static sites and site IDs | `site-manifest.json` |
| [ble-gatt.md](ble-gatt.md) | Bluetooth LE service, handshake and confirmation code | `ble.json` |
| [audio.md](audio.md) | Data-over-sound payload rules (ggwave) | `audio.json` |
| [hashbin.md](hashbin.md) | Native Save (OAuth + PKCE), Publish popup compatibility | `hashbin.json` |
| [qr.md](qr.md) | QR sizing plan, multi-frame QR, scanning rules | `qr.json` |
| [bridge.md](bridge.md) | `window.binfire` host bridge for registered origins | (M8) |
| [ui.md](ui.md) | Screens, actions and accessibility IDs shared by all ports | `maestro/` flows |

Conventions used everywhere:

- **base64url** means RFC 4648 section 5 without padding. Decoders reject
  padding, characters outside the alphabet, lengths with `len % 4 == 1`, and
  non-canonical trailing bits.
- **Bytes** in fixtures are given as UTF-8 text (`"text"`) or as base64url
  (`"b64"`). Exactly one of the two is used per value.
- **Bounds** come from `config/binfire.config.json` `limits`. Untrusted input is
  always checked against its bound *before* it is decoded or allocated.
- **Text limits** such as "at most 200 characters" count Unicode code points.
- **UTF-8 JSON** (envelopes, manifests, bundle headers): decoding is strict
  (invalid UTF-8 fails), and one leading byte-order mark (EF BB BF) is
  stripped before parsing, as `TextDecoder` does.
- Error codes are short kebab-case strings, listed in each spec. Fixtures name
  the expected code. Ports must not invent new codes for listed cases.
