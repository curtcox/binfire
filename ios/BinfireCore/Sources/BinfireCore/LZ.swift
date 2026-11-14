import Foundation

/// lz-string 1.5.0 `compressToEncodedURIComponent` and Fragment Kit's bounded,
/// strict decoder (`spec/state.md` "lz-string").
///
/// Text is a JavaScript string: a sequence of UTF-16 code units. Lone
/// surrogates survive both directions. `String` conveniences are provided
/// for well-formed text.
public enum LZ {
    private static let alphabet: [UInt16] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$".utf16)
    private static let lookup: [Int] = {
        var t = [Int](repeating: -1, count: 128)
        for (i, c) in alphabet.enumerated() { t[Int(c)] = i }
        return t
    }()

    // MARK: compress

    /// lz-string `compressToEncodedURIComponent(text)`.
    public static func compress(_ text: [UInt16]) -> [UInt16] {
        var out: [UInt16] = []
        var bitValue = 0
        var bitPosition = 0
        @inline(__always) func writeBit(_ bit: Int) {
            bitValue = (bitValue << 1) | bit
            if bitPosition == 5 {
                bitPosition = 0
                out.append(alphabet[bitValue])
                bitValue = 0
            } else {
                bitPosition += 1
            }
        }
        @inline(__always) func writeBits(_ value: Int, _ count: Int) {
            var v = value
            for _ in 0..<count { writeBit(v & 1); v >>= 1 }
        }

        var singles: [UInt16: Int] = [:]      // single-character dictionary entries
        var toCreate = Set<UInt16>()          // single characters not yet emitted raw
        var pairs: [Int: Int] = [:]           // (code(w) << 16 | c) -> code(w + c)
        var dictSize = 3
        var numBits = 2
        var enlargeIn = 2
        var hasW = false
        var wCode = 0
        var wIsSingle = false
        var wChar: UInt16 = 0
        // lz-string keeps its dictionary in a plain JS object, so the phrase
        // "__proto__" is never stored (assigning it sets the prototype) yet
        // still consumes a code. Track whether w is exactly "__proto_".
        let protoPrefix: [UInt16] = Array("__proto_".utf16)
        var wTail: [UInt16] = []   // the first 9 units of w (enough to compare)
        var wLength = 0

        func decrementEnlarge() {
            enlargeIn -= 1
            if enlargeIn == 0 {
                enlargeIn = 1 << numBits
                numBits += 1
            }
        }
        func emitW() {
            if wIsSingle && toCreate.contains(wChar) {
                if wChar < 256 {
                    writeBits(0, numBits)
                    writeBits(Int(wChar), 8)
                } else {
                    writeBits(1, numBits)
                    writeBits(Int(wChar), 16)
                }
                decrementEnlarge()
                toCreate.remove(wChar)
            } else {
                writeBits(wCode, numBits)
            }
            decrementEnlarge()
        }

        for c in text {
            if singles[c] == nil {
                singles[c] = dictSize
                dictSize += 1
                toCreate.insert(c)
            }
            if !hasW {
                hasW = true
                wCode = singles[c]!
                wIsSingle = true
                wChar = c
                wTail = [c]
                wLength = 1
                continue
            }
            let isProto = c == 0x5F && wLength == 8 && wTail == protoPrefix
            let key = wCode << 16 | Int(c)
            if !isProto, let code = pairs[key] {
                wCode = code
                wIsSingle = false
                wLength += 1
                if wTail.count < 9 { wTail.append(c) }
                continue
            }
            emitW()
            if !isProto { pairs[key] = dictSize }
            dictSize += 1
            wCode = singles[c]!
            wIsSingle = true
            wChar = c
            wTail = [c]
            wLength = 1
        }
        if hasW { emitW() }
        writeBits(2, numBits)
        while true {
            bitValue <<= 1
            if bitPosition == 5 {
                out.append(alphabet[bitValue])
                break
            }
            bitPosition += 1
        }
        return out
    }

    /// `compress` for a well-formed Swift string.
    public static func compress(_ text: String) -> String {
        String(decoding: compress(Array(text.utf16)), as: UTF16.self)
    }

    // MARK: decompress

    /// Bounded strict decompression. Throws `BinfireError.tooLarge` or
    /// `BinfireError.invalid` exactly as `spec/state.md` steps 1-5 describe.
    public static func decompress(_ input: [UInt16], limitBytes: Int) throws -> [UInt16] {
        let (scaled, overflow) = limitBytes.multipliedReportingOverflow(by: 4)
        if !overflow, scaled <= Int.max - 64, input.count > scaled + 64 { throw BinfireError.tooLarge }
        let normalized = input.map { $0 == 0x20 ? 0x2B : $0 }
        guard let result = try decodeSource(normalized, limit: limitBytes),
              compress(result) == normalized else { throw BinfireError.invalid }
        if result.count > limitBytes || utf8Length(result) > limitBytes { throw BinfireError.tooLarge }
        return result
    }

    /// `decompress` for a Swift string. The result must be well-formed UTF-16
    /// to be returned as a `String`; otherwise use the code-unit overload.
    public static func decompress(_ input: String, limitBytes: Int) throws -> String {
        let units = try decompress(Array(input.utf16), limitBytes: limitBytes)
        return String(decoding: units, as: UTF16.self)
    }

    /// UTF-8 length of UTF-16 code units, counting a lone surrogate as 3 bytes
    /// (U+FFFD), like `Buffer.byteLength`.
    public static func utf8Length(_ units: [UInt16]) -> Int {
        var n = 0
        var i = 0
        while i < units.count {
            let u = units[i]
            if u < 0x80 { n += 1 }
            else if u < 0x800 { n += 2 }
            else if (0xD800...0xDBFF).contains(u), i + 1 < units.count, (0xDC00...0xDFFF).contains(units[i + 1]) {
                n += 4
                i += 1
            } else { n += 3 }
            i += 1
        }
        return n
    }

    /// Port of FK's bounded decoder (`tools/lib/lz.mjs` decodeSource). `input`
    /// already has spaces replaced by `+`. Returns nil for `invalid`.
    private static func decodeSource(_ input: [UInt16], limit: Int) throws -> [UInt16]? {
        if input.isEmpty { return nil }
        for u in input where u >= 128 || lookup[Int(u)] < 0 { return nil }
        var position = 32
        var index = 1
        var value = lookup[Int(input[0])]
        func bits(_ count: Int) -> Int {
            var result = 0
            for p in 0..<count {
                if value & position != 0 { result += 1 << p }
                position >>= 1
                if position == 0 {
                    position = 32
                    value = index < input.count ? lookup[Int(input[index])] : 0
                    index += 1
                }
            }
            return result
        }
        // Each dictionary entry is a range of `output`: entries are always
        // either the chunk just appended, or the previous chunk plus the first
        // unit of the next one, which are contiguous in the output.
        var dictStart: [Int] = [0, 0, 0]
        var dictLength: [Int] = [0, 0, 0]
        var next = bits(2)
        let c: UInt16
        if next == 0 { c = UInt16(bits(8)) }
        else if next == 1 { c = UInt16(bits(16)) }
        else { return next == 2 ? [] : nil }
        var output: [UInt16] = [c]
        dictStart.append(0); dictLength.append(1)
        var wStart = 0, wLength = 1
        var enlarge = 4, numBits = 3
        if 1 > limit { throw BinfireError.tooLarge }
        while true {
            if index > input.count { return nil }
            next = bits(numBits)
            var literal: UInt16? = nil
            if next == 0 || next == 1 {
                literal = UInt16(bits(next == 0 ? 8 : 16))
                dictStart.append(output.count); dictLength.append(1)
                next = dictStart.count - 1
                enlarge -= 1
            } else if next == 2 {
                return output
            }
            if enlarge == 0 {
                enlarge = 1 << numBits
                numBits += 1
            }
            let entryStart = output.count
            var entryLength: Int
            if let literal {
                entryLength = 1
                if output.count + entryLength > limit { throw BinfireError.tooLarge }
                output.append(literal)
            } else if next < dictStart.count {
                entryLength = dictLength[next]
                if output.count + entryLength > limit { throw BinfireError.tooLarge }
                let s = dictStart[next]
                output.append(contentsOf: output[s..<(s + entryLength)])
            } else {
                if next != dictStart.count { return nil }
                // entry = w + w[0]
                entryLength = wLength + 1
                if output.count + entryLength > limit { throw BinfireError.tooLarge }
                output.append(contentsOf: output[wStart..<(wStart + wLength)])
                output.append(output[wStart])
            }
            // dictionary[dictSize++] = w + entry[0]: w is immediately followed by entry.
            dictStart.append(wStart); dictLength.append(wLength + 1)
            enlarge -= 1
            wStart = entryStart
            wLength = entryLength
            if enlarge == 0 {
                enlarge = 1 << numBits
                numBits += 1
            }
        }
    }
}
