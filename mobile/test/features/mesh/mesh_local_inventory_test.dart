/// Unit tests for [MeshLocalInventory] and the in-memory source used by
/// the mesh session.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/mesh_local_inventory.dart';
import 'package:mobile/features/sync/data/bloom_filter.dart';

Uint8List _payload(String id) =>
    Uint8List.fromList(utf8.encode('{"id":"$id"}'));

MeshItem _item(String id, {String kind = 'request', DateTime? at}) => MeshItem(
      kind: kind,
      id: id,
      payload: _payload(id),
      receivedAt: at ?? DateTime.now().toUtc(),
    );

void main() {
  group('MeshItem', () {
    test('value equality uses kind + id + payload + receivedAt', () {
      final at = DateTime.utc(2025, 1, 1);
      final a = MeshItem(kind: 'request', id: 'a', payload: _payload('a'), receivedAt: at);
      final b = MeshItem(kind: 'request', id: 'a', payload: _payload('a'), receivedAt: at);
      final c = MeshItem(kind: 'bulletin', id: 'a', payload: _payload('a'), receivedAt: at);
      final d = MeshItem(kind: 'request', id: 'b', payload: _payload('b'), receivedAt: at);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different payload bytes compare unequal', () {
      final at = DateTime.utc(2025, 1, 1);
      final a = MeshItem(kind: 'request', id: 'x', payload: _payload('x'), receivedAt: at);
      final b = MeshItem(
        kind: 'request',
        id: 'x',
        payload: Uint8List.fromList(utf8.encode('{"id":"y"}')),
        receivedAt: at,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('MeshLocalInventory.missingIds', () {
    test('returns only ids the bloom says we probably do not have', () async {
      final src = InMemoryInventorySource();
      final t0 = DateTime.utc(2025, 1, 1);
      src.seed([
        _item('bulletin-a', kind: 'bulletin', at: t0),
        _item('request-b', kind: 'request', at: t0),
      ]);
      final snap = await src.snapshot();
      expect(snap.itemCount, 2);

      final missing = snap.missingIds(<String>['bulletin-a', 'request-b', 'request-c']);
      expect(missing, contains('request-c'));
      // 'bulletin-a' and 'request-b' should not be missing (bloom says yes).
      expect(missing, isNot(contains('bulletin-a')));
      expect(missing, isNot(contains('request-b')));
    });

    test('empty inventory reports every id as missing', () async {
      final src = InMemoryInventorySource();
      final snap = await src.snapshot();
      expect(snap.itemCount, 0);
      expect(snap.missingIds(<String>['x', 'y']), ['x', 'y']);
    });
  });

  group('InMemoryInventorySource', () {
    test('applyInbound is idempotent on duplicate id', () async {
      final src = InMemoryInventorySource();
      final first = _item('a');
      expect(await src.applyInbound(first), isTrue);
      expect(await src.applyInbound(first), isFalse);
      expect(src.size, 1);
    });

    test('payloadFor returns null for unknown ids', () async {
      final src = InMemoryInventorySource();
      expect(await src.payloadFor('nope'), isNull);
    });

    test('snapshot bloom survives serialization round-trip', () async {
      final src = InMemoryInventorySource();
      src.seed([_item('x'), _item('y'), _item('z')]);
      final snap = await src.snapshot();
      final raw = snap.bloom.toBytes();
      final restored = BloomFilter.fromBytes(raw);
      expect(restored.mightContainString('x'), isTrue);
      expect(restored.mightContainString('y'), isTrue);
      expect(restored.mightContainString('z'), isTrue);
    });
  });
}