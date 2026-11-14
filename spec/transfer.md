# Transfer

There are three payload kinds:

- `url`: a state URL.
- `cid`: a document by CID, carried together with its bytes.
- `site`: a site manifest plus all of its files.

Every kind travels in a **bundle**. A bundle is the payload of a `.binfire`
file and of the chunked channels (multi-frame QR, BLE). Audio and single QR
codes carry plain text instead (audio.md, links.md).

## Bundle container

```
offset  size      field
0       4         magic  "BFB1" (0x42 0x46 0x42 0x31)
4       4         hlen   header length, uint32 big-endian, 2 <= hlen <= 1048576
8       hlen      header UTF-8 JSON object
8+hlen  …         entry bytes, concatenated in header.entries order
```

Header fields:

| Field | Type | Kinds | Notes |
| --- | --- | --- | --- |
| `kind` | string | all | `url`, `cid` or `site` |
| `url` | string | `url` | an absolute URL (routed with `route`) |
| `cid` | string | `cid`, `site` | the document CID, or the manifest CID |
| `app` | string | `cid` (optional) | a slug hint |
| `name` | string | any (optional) | a display name, at most 200 characters |
| `entries` | array of `{ "cid": string }` | all | `[]` for `url` |

Each entry's size is `cidLength(entry.cid)`. Decoding checks, in order:

1. Magic → `bad-magic`. `hlen` in range, and the container is at least
   `8 + hlen` bytes long → `bad-bundle`.
2. The header is UTF-8 JSON with a known `kind` and the fields that kind needs
   → `bad-bundle`. Unknown header fields are ignored.
3. Every entry CID, and the header `cid` when present, is valid →
   `invalid-cid`. The sum of entry sizes is at most
   `limits.maxTransferBytes` → `too-large`. The container length is exactly
   `8 + hlen + sum` → `bad-bundle`.
4. Each entry's bytes verify against its CID → `mismatch`.
5. Per kind:
   - `url`: `entries` is empty.
   - `cid`: `entries` is exactly `[{cid}]`.
   - `site`: `entries[0].cid == cid`, and that entry is a valid site manifest
     (site-manifest.md). Every file CID in the manifest appears in `entries`,
     and no entry is outside the manifest. Each distinct CID appears once.
     → `bad-bundle` (or the manifest's own error code).

Header JSON is not canonical, and ports may serialize it differently. The
outer payload CID covers whatever bytes the sender produced.

### `.binfire` files

A `.binfire` file is exactly one bundle container.

- MIME type: `application/vnd.binfire.bundle`
- UTI: `app.binfire.bundle`, conforming to `public.data`
- Android intent filters: that MIME type, plus `*/*` with path pattern
  `.*\.binfire`

Received bundles open with `run=0` until the user chooses **Run** (PLAN §10).
For a `url` bundle, that means the route is shown first and is not opened
automatically.

## Chunk frames

Chunked channels split the bundle bytes (the *payload*) into frames:

```
offset  size     field
0       2        magic   "BF"
2       1        version 1
3       1        flags   0 (reserved; receivers reject anything else)
4       8        id      transfer id, random per transfer
12      4        index   uint32 BE
16      4        count   uint32 BE, >= 1
20      4        offset  uint32 BE, byte offset of this chunk in the payload
24      4        total   uint32 BE, payload length
28      1        cidLen  8..94
29      cidLen   cid     ASCII payload CID
29+cidLen …      data    chunk bytes
```

`encodeFrames(payload, id, chunkSize)` is deterministic:

- `count = max(1, ceil(total / chunkSize))`.
- Frame `i` carries `payload[i*chunkSize : min((i+1)*chunkSize, total)]` at
  `offset = i*chunkSize`.
- An empty payload is one frame with no data.

`decodeFrame(bytes)` returns the fields or fails with `bad-magic` (also
for inputs shorter than 2 bytes),
`bad-version` (version != 1 or flags != 0) or `bad-frame` (one of: truncated,
`index >= count`, `count > max(1, total)`, `offset + len(data) > total`,
an invalid CID, or `total != cidLength(cid)`). The `count` bound stops a
hostile frame from making a receiver track billions of indexes.

Reassembly (`Reassembler`) accepts frames in any order:

- The first frame fixes `id`, `count`, `total` and `cid`. A later frame that
  differs → `inconsistent`.
- `total > limits.maxTransferBytes` → `too-large`. This is checked on the
  first frame, before anything is allocated.
- A duplicate index with different data or offset → `inconsistent`. Identical
  duplicates are ignored.
- The transfer is complete when all `count` indexes have arrived. Chunks
  sorted by offset must tile `[0, total)` exactly → `bad-frame`. The payload
  must verify against `cid` → `mismatch`.
- `missing()` lists the indexes that haven't arrived. BLE uses it to
  re-request.

### QR text frames

Multi-frame QR shows each frame as the text `BF1:` + base64url(frame). The
sender cycles frames at about 5 per second, with a data chunk size of 512
bytes. A single small state is shown as its plain `https://D/…` link instead.
`route` never sees `BF1:` texts. The scanner feeds them to a `Reassembler`.

## Fixture `transfer.json`

```json
{ "bundles":       [{ "name", "b64", "expect": { "kind", "url"?, "cid"?, "app"?, "name"?, "entries": ["cid", …] } }],
  "bundleErrors":  [{ "name", "b64", "error" }],
  "frames":        [{ "name", "payloadB64", "cid", "idHex", "chunkSize", "frames": ["b64", …] }],
  "frameErrors":   [{ "name", "b64", "error" }],
  "reassemblyErrors": [{ "name", "frames": ["b64", …], "error" }] }
```

For `frames`, ports check that `encodeFrames` produces the listed frames
exactly, and that reassembling them in reverse order gives the payload.
