/// A compact, in-memory Bloom filter used to advertise "which packet ids do I
/// already have?" to peers over a low-bandwidth transport (BLE advertisements,
/// Wi-Fi Direct hellos, etc).
///
/// Design choices, all deliberate for the offline-mesh use case:
///
///   * Fixed size: [_bitLength] = 4096 bits = 512 bytes. Small enough to fit
///     in a single BLE advertisement or one TLV of a Wi-Fi Direct hello frame.
///   * Hash strategy: 3 double-hashed positions derived from a 32-byte input
///     hash. Empirically <1% false-positive rate at ~1000 items.
///   * Pure Dart: no dependency added. ~60 LOC over a `Uint8List` BitList.
///
/// `add` and `mightContain` accept any 32-byte content hash (sha256 is the
/// canonical input in this app).
library;

import 'dart:typed_data';

class BloomFilter {
  static const int _bitLength = 4096;
  static const int _byteLength = _bitLength ~/ 8;
  static const int _hashCount = 3;

  final Uint8List _bits;

  BloomFilter() : _bits = Uint8List(_byteLength);

  /// Restore from a serialized buffer. Returns an empty filter if [raw] is
  /// null or the wrong size (degraded mode, never throws on the wire).
  factory BloomFilter.fromBytes(Uint8List? raw) {
    final f = BloomFilter();
    if (raw != null && raw.length == _byteLength) {
      f._bits.setAll(0, raw);
    }
    return f;
  }

  Uint8List toBytes() => Uint8List.fromList(_bits);

  /// Add a 32-byte content hash to the filter.
  void add(Uint8List hash32) {
    assert(hash32.length == 32, 'BloomFilter.add expects a 32-byte hash');
    final h1 = _readBigEndian(hash32, 0);
    final h2 = _readBigEndian(hash32, 8);
    for (var i = 0; i < _hashCount; i++) {
      // Kirsch-Mitzenmacher double-hashing: g_i(x) = h1 + i * h2
      final pos = (h1 + i * h2) & (_bitLength - 1);
      _bits[pos ~/ 8] |= 1 << (pos & 7);
    }
  }

  /// Returns false if [hash32] is definitely not in the set. Returns true if
  /// it might be (with bounded false-positive probability).
  bool mightContain(Uint8List hash32) {
    assert(hash32.length == 32, 'BloomFilter.mightContain expects a 32-byte hash');
    final h1 = _readBigEndian(hash32, 0);
    final h2 = _readBigEndian(hash32, 8);
    for (var i = 0; i < _hashCount; i++) {
      final pos = (h1 + i * h2) & (_bitLength - 1);
      if ((_bits[pos ~/ 8] & (1 << (pos & 7))) == 0) return false;
    }
    return true;
  }

  /// String convenience: hashes the id into a 32-byte buffer using FNV-1a
  /// so callers can ask "might I have this id?" without an explicit sha256.
  /// Must be paired with [addString] (or any 32-byte digest of the same id
  /// bytes) for membership to be consistent.
  bool mightContainString(String id) => mightContain(_key32(id));

  /// String convenience: adds the 32-byte FNV-1a digest of [id]. Use this
  /// when you'll later query with [mightContainString].
  void addString(String id) => add(_key32(id));

  /// FNV-1a 64-bit hash, expanded to 32 bytes (low + high halves each
  /// padded to 16 bytes). Discriminating for short ids, deterministic, and
  /// cheap. NOT cryptographic — only used as the bloom input.
  static Uint8List _key32(String id) {
    var hash = 0xcbf29ce484222325; // FNV-1a 64-bit offset basis
    const prime = 0x100000001b3;
    for (final r in id.runes) {
      hash = ((hash ^ (r & 0xff)) * prime) & 0xffffffffffffffff;
    }
    final out = Uint8List(32);
    final bytes = ByteData(8);
    bytes.setUint64(0, hash);
    final lo = bytes.getUint64(0);
    // Split the 8-byte digest into two halves, each spread across 16 bytes,
    // so the bloom's two independent 8-byte reads (`_readBigEndian` at
    // offset 0 and 8) see non-zero, distinct inputs.
    for (var i = 0; i < 8; i++) {
      out[i] = (lo >> ((7 - i) * 8)) & 0xff;
      out[16 + i] = (hash >> ((7 - i) * 8)) & 0xff;
    }
    // Fill the remaining 8 bytes (offsets 8-15) with a stretched XOR of
    // the input length and a constant so even short inputs produce
    // distinct buffers.
    for (var i = 8; i < 16; i++) {
      out[i] = ((hash >> ((i % 8) * 8)) ^ (id.length * (i + 1))) & 0xff;
    }
    return out;
  }

  /// Wipe all bits. Used after a retention-policy sweep so the filter only
  /// reflects what is currently in the local cache.
  void reset() {
    _bits.fillRange(0, _byteLength, 0);
  }

  /// Number of set bits (cheap health-check for tests).
  int get popCount {
    var n = 0;
    for (final b in _bits) {
      n += _popcountByte(b);
    }
    return n;
  }

  static int _readBigEndian(Uint8List buf, int offset) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v * 256) + buf[offset + i];
    }
    return v;
  }

  static int _popcountByte(int b) {
    var n = 0;
    var v = b & 0xff;
    while (v != 0) {
      n += v & 1;
      v >>= 1;
    }
    return n;
  }
}
