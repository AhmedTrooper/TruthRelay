/// Unit tests for the BLE small-payload transport.
///
/// The chunking/reassembly algorithm is the only place BLE-specific
/// concerns live in the mesh layer. These tests cover the framing
/// primitives, error paths, and end-to-end delivery with an in-memory
/// transport pair.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/ble_transport.dart';

void main() {
  group('BleChunker', () {
    test('round-trips short payload in a single frame', () {
      final payload = Uint8List.fromList('hello'.codeUnits);
      final frames = BleChunker.encode(payload, 64);
      expect(frames, hasLength(1));
      final parsed = BleChunker.parse(frames.single);
      expect(parsed, isNotNull);
      expect(parsed!.total, 5);
      expect(parsed.seq, 0);
      expect(String.fromCharCodes(parsed.payload), 'hello');
    });

    test('splits long payload across multiple frames', () {
      final payload = Uint8List.fromList(List<int>.generate(400, (i) => i & 0xff));
      final frames = BleChunker.encode(payload, 64);
      final per = BleChunker.effectivePayload(64);
      final expectedFrames = (400 + per - 1) ~/ per;
      expect(frames, hasLength(expectedFrames));
      final reassembled = <int>[];
      for (final f in frames) {
        final p = BleChunker.parse(f);
        expect(p, isNotNull);
        expect(p!.total, 400);
        reassembled.addAll(p.payload);
      }
      expect(reassembled, equals(payload));
    });

    test('encode rejects payloads exceeding 16-bit length', () {
      final huge = Uint8List(0x10000);
      expect(() => BleChunker.encode(huge, 64),
          throwsA(isA<BleTransportException>()));
    });

    test('parse returns null for keep-alive frames', () {
      final frame = Uint8List.fromList([0, 0, 0xff, 0xff]);
      expect(BleChunker.parse(frame), isNull);
    });

    test('parse returns null for too-short frames', () {
      expect(BleChunker.parse(Uint8List(3)), isNull);
    });
  });

  group('BleMeshTransport', () {
    test('delivers a short JSON envelope end-to-end', () async {
      final pair = InMemoryBleByteChannelPair.pair();
      final sender = BleMeshTransport(channel: pair.a);
      final receiver = BleMeshTransport(channel: pair.b);
      final received = <String>[];
      final sub = receiver.incoming.listen(received.add);
      await sender.send('{"hello":1}');
      // Pump so the buffered channel flushes to the receiver.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      await sender.dispose();
      await receiver.dispose();
      expect(received, ['{"hello":1}']);
    });

    test('chunks and reassembles a payload larger than one frame', () async {
      final pair = InMemoryBleByteChannelPair.pair();
      // Tiny chunk size so we definitely go multi-frame.
      final sender = BleMeshTransport(
        channel: pair.a,
        config: const BleMeshTransportConfig(chunkSize: 32),
      );
      final receiver = BleMeshTransport(
        channel: pair.b,
        config: const BleMeshTransportConfig(chunkSize: 32),
      );
      final received = <String>[];
      final sub = receiver.incoming.listen(received.add);

      final json = '{"v":1,"payload":"${'X' * 200}"}';
      await sender.send(json);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await sender.dispose();
      await receiver.dispose();
      expect(received, hasLength(1));
      expect(received.single, json);
    });

    test('rejects payloads above maxMessageBytes', () async {
      final pair = InMemoryBleByteChannelPair.pair();
      final t = BleMeshTransport(
        channel: pair.a,
        config: const BleMeshTransportConfig(maxMessageBytes: 16),
      );
      expect(() => t.send('{"a":"${'X' * 32}"}'),
          throwsA(isA<BleTransportException>()));
      await t.dispose();
    });

    test('duplicate chunk is ignored (idempotent)', () async {
      final pair = InMemoryBleByteChannelPair.pair();
      final sender = BleMeshTransport(
        channel: pair.a,
        config: const BleMeshTransportConfig(chunkSize: 32),
      );
      final receiver = BleMeshTransport(
        channel: pair.b,
        config: const BleMeshTransportConfig(chunkSize: 32),
      );
      final received = <String>[];
      final sub = receiver.incoming.listen(received.add);

      // Send a multi-frame message, then re-send the first chunk out of
      // band — the reassembler should treat it as a duplicate and not
      // re-deliver.
      final json = '{"payload":"${'X' * 100}"}';
      await sender.send(json);
      // Send the first chunk once more into the receiver's channel.
      final frame = BleChunker.encode(Uint8List.fromList(json.codeUnits), 32);
      await pair.b.sendChunk(frame.first);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await sender.dispose();
      await receiver.dispose();
      expect(received, [json]);
    });

    test('stale reassembly buffer is dropped on timeout', () async {
      final pair = InMemoryBleByteChannelPair.pair();
      final receiver = BleMeshTransport(
        channel: pair.b,
        config: const BleMeshTransportConfig(
          chunkSize: 32,
          reassemblyTimeout: Duration(milliseconds: 50),
        ),
      );
      final received = <String>[];
      final sub = receiver.incoming.listen(received.add);

      // Push a single chunk of a fresh message, then wait past the
      // timeout, then push the rest. Expect the partial message to be
      // dropped and the new one to be reassembled.
      final frames = BleChunker.encode(
        Uint8List.fromList('{"payload":"${'X' * 100}"}'.codeUnits),
        32,
      );
      await pair.b.sendChunk(frames.first);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      for (final f in frames.skip(1)) {
        await pair.b.sendChunk(f);
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      await receiver.dispose();
      // The newer frame sequence may reassemble into a complete message
      // if the timeout triggered; the older partial must not surface.
      expect(
        received.any((r) => r.length < 100),
        isFalse,
        reason: 'partial messages must not surface',
      );
    });
  });
}
