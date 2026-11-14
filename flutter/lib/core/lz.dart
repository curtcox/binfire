/// lz-string 1.5.0 `compressToEncodedURIComponent` and FK's bounded strict
/// decoder (spec/state.md, ported from `tools/lib/lz.mjs`).
///
/// Texts are JavaScript strings: sequences of UTF-16 code units. Dart strings
/// are the same, and lone surrogates survive both directions.
library;

import 'config.dart';
import 'errors.dart';
import 'text.dart';

const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-\$';

final List<int> _reverse = () {
  final table = List<int>.filled(128, -1);
  for (var i = 0; i < _alphabet.length; i++) {
    table[_alphabet.codeUnitAt(i)] = i;
  }
  return table;
}();

int _indexOf(int codeUnit) => codeUnit < 128 ? _reverse[codeUnit] : -1;

/// lz-string 1.5.0 `compressToEncodedURIComponent(text)`.
String lzCompress(String text) {
  final dictionary = <String, int>{};
  final toCreate = <String>{};
  var w = '';
  var enlargeIn = 2;
  var dictSize = 3;
  var numBits = 2;
  final out = StringBuffer();
  var value = 0;
  var position = 0;

  void writeBits(int bits, int count) {
    for (var i = 0; i < count; i++) {
      value = (value << 1) | (bits & 1);
      bits >>= 1;
      if (position == 5) {
        position = 0;
        out.write(_alphabet[value]);
        value = 0;
      } else {
        position++;
      }
    }
  }

  void countDown() {
    enlargeIn--;
    if (enlargeIn == 0) {
      enlargeIn = 1 << numBits;
      numBits++;
    }
  }

  void emit(String w) {
    if (toCreate.contains(w)) {
      final code = w.codeUnitAt(0);
      if (code < 256) {
        writeBits(0, numBits);
        writeBits(code, 8);
      } else {
        writeBits(1, numBits);
        writeBits(code, 16);
      }
      countDown();
      toCreate.remove(w);
    } else {
      writeBits(dictionary[w]!, numBits);
    }
    countDown();
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (!dictionary.containsKey(c)) {
      dictionary[c] = dictSize++;
      toCreate.add(c);
    }
    final wc = w + c;
    if (dictionary.containsKey(wc)) {
      w = wc;
    } else {
      emit(w);
      dictionary[wc] = dictSize++;
      w = c;
    }
  }
  if (w.isNotEmpty) emit(w);
  writeBits(2, numBits);
  while (true) {
    value <<= 1;
    if (position == 5) {
      out.write(_alphabet[value]);
      break;
    }
    position++;
  }
  return out.toString();
}

/// Decompresses [input] with FK's bounds and strict canonicality.
///
/// [limitBytes] bounds both the UTF-16 length during decoding and the UTF-8
/// size of the result. Throws [BinfireException] with `too-large` or
/// `invalid`.
String lzDecompress(String input, [int? limitBytes]) {
  final limit = limitBytes ?? BinfireLimits.defaults.maxStateBytes;
  if (input.length > limit * 4 + 64) {
    throw const BinfireException(ErrorCodes.tooLarge);
  }
  final normalized = input.replaceAll(' ', '+');
  final result = _decodeSource(normalized, limit);
  if (result == null || lzCompress(result) != normalized) {
    throw const BinfireException(ErrorCodes.invalid);
  }
  if (result.length > limit || utf8Length(result) > limit) {
    throw const BinfireException(ErrorCodes.tooLarge);
  }
  return result;
}

/// FK `decodeSource`, with spaces already replaced by `+`.
String? _decodeSource(String input, int limit) {
  if (input.isEmpty) return null;
  for (var i = 0; i < input.length; i++) {
    if (_indexOf(input.codeUnitAt(i)) < 0) return null;
  }
  var position = 32;
  var index = 1;
  var value = _indexOf(input.codeUnitAt(0));

  int bits(int count) {
    var result = 0;
    for (var p = 0; p < count; p++) {
      if (value & position != 0) result += 1 << p;
      position >>= 1;
      if (position == 0) {
        position = 32;
        value = index < input.length ? _indexOf(input.codeUnitAt(index)) : 0;
        index++;
      }
    }
    return result;
  }

  // Entries 0..2 are placeholders, as in the JS original.
  final dictionary = <String?>[null, null, null];
  var next = bits(2);
  String c;
  if (next == 0) {
    c = String.fromCharCode(bits(8));
  } else if (next == 1) {
    c = String.fromCharCode(bits(16));
  } else {
    return next == 2 ? '' : null;
  }
  dictionary.add(c);
  var w = c;
  var dictSize = 4;
  var enlarge = 4;
  var numBits = 3;
  var length = 1;
  if (length > limit) throw const BinfireException(ErrorCodes.tooLarge);
  final output = StringBuffer(c);
  while (true) {
    if (index > input.length) return null;
    next = bits(numBits);
    if (next == 0 || next == 1) {
      dictionary.add(String.fromCharCode(bits(next == 0 ? 8 : 16)));
      dictSize++;
      next = dictSize - 1;
      enlarge--;
    } else if (next == 2) {
      return output.toString();
    }
    if (enlarge == 0) {
      enlarge = 1 << numBits;
      numBits++;
    }
    var entry = next < dictionary.length ? dictionary[next] : null;
    if (entry == null) {
      if (next != dictSize) return null;
      entry = w + w[0];
    }
    length += entry.length;
    if (length > limit) throw const BinfireException(ErrorCodes.tooLarge);
    output.write(entry);
    dictionary.add(w + entry[0]);
    dictSize++;
    enlarge--;
    w = entry;
    if (enlarge == 0) {
      enlarge = 1 << numBits;
      numBits++;
    }
  }
}
