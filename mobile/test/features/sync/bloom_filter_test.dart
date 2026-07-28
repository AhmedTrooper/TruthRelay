/// Unit tests for the in-tree Bloom filter used by mesh peer advertisements.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/sync/data/bloom_filter.dart';

final _sha = Sha256();

Future<Uint8List> _hash(int seed) async {
  final h = await _sha.hash(utf8.encode('seed-$seed'));
  return Uint8List.fromList(h.bytes);
}

void main() {
  test('empty filter rejects everything', () async {
    final f = BloomFilter();
    expect(f.mightContain(await _hash(1)), isFalse);
    expect(f.popCount, 0);
  });

  test('inserted hash is detected (no false negative)', () async {
    final f = BloomFilter();
    final h = await _hash(42);
    f.add(h);
    expect(f.mightContain(h), isTrue);
    expect(f.popCount, greaterThan(0));
  });

  test('unrelated hash is rejected (with rare false positives)', () async {
    final f = BloomFilter();
    f.add(await _hash(1));
    f.add(await _hash(2));
    f.add(await _hash(3));
    expect(f.mightContain(await _hash(99999)), isFalse);
  });

  test('reset clears all bits', () async {
    final f = BloomFilter();
    f.add(await _hash(1));
    f.add(await _hash(2));
    expect(f.popCount, greaterThan(0));
    f.reset();
    expect(f.popCount, 0);
    expect(f.mightContain(await _hash(1)), isFalse);
  });

  test('serialization round-trip preserves membership', () async {
    final a = BloomFilter();
    a.add(await _hash(10));
    a.add(await _hash(20));
    a.add(await _hash(30));
    final raw = a.toBytes();
    final b = BloomFilter.fromBytes(raw);
    expect(b.mightContain(await _hash(10)), isTrue);
    expect(b.mightContain(await _hash(20)), isTrue);
    expect(b.mightContain(await _hash(30)), isTrue);
    expect(b.mightContain(await _hash(11)), isFalse);
  });

  test('fromBytes on null yields an empty filter (no throw on the wire)', () async {
    final f = BloomFilter.fromBytes(null);
    expect(f.mightContain(await _hash(1)), isFalse);
    expect(f.popCount, 0);
  });

  test('fromBytes on wrong-sized buffer yields an empty filter (defensive)', () async {
    final f = BloomFilter.fromBytes(Uint8List(8));
    expect(f.mightContain(await _hash(1)), isFalse);
  });

  test('realistic mesh load (~100 items) keeps FP rate under 2%', () async {
    final f = BloomFilter();
    // Realistic load: a phone in a crisis-zone mesh carries ~100 bulletins.
    for (var i = 0; i < 100; i++) {
      f.add(await _hash(i));
    }
    var falsePositives = 0;
    const probes = 10000;
    for (var i = 100000; i < 100000 + probes; i++) {
      if (f.mightContain(await _hash(i))) falsePositives++;
    }
    // Theoretical FP at m=4096, k=3, n=100 is ~0.05%. We allow up to 2%.
    expect(falsePositives, lessThan((probes * 0.02).round()));
  });
}
