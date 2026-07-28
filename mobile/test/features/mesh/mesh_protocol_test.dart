/// Unit tests for the versioned mesh wire format.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/models/mesh_packet.dart';

MeshHeader _hdr() => MeshHeader(
      version: meshProtocolVersion,
      packetId: Uint8List.fromList(List<int>.generate(32, (i) => i + 1)),
      peerId: 'peer-test',
    );

void main() {
  group('MeshHello', () {
    test('round-trips through encode/decode', () {
      final hello = MeshHello(
        header: _hdr(),
        bloom: Uint8List(512),
        itemCount: 42,
        newestReceivedAt: DateTime.utc(2026, 7, 28, 10, 0, 0),
      );
      final raw = hello.encode();
      final decoded = decodeMeshPacket(raw);
      expect(decoded, isA<MeshHello>());
      final h = decoded as MeshHello;
      expect(h.header.peerId, 'peer-test');
      expect(h.itemCount, 42);
      expect(h.newestReceivedAt.toUtc(), hello.newestReceivedAt.toUtc());
      expect(h.bloom.length, 512);
    });
  });

  group('MeshRequest', () {
    test('round-trips with multiple ids', () {
      final req = MeshRequest(
        header: _hdr(),
        wantIds: [
          Uint8List.fromList(List<int>.generate(32, (i) => i)),
          Uint8List.fromList(List<int>.generate(32, (i) => i * 3)),
        ],
      );
      final decoded = decodeMeshPacket(req.encode()) as MeshRequest;
      expect(decoded.wantIds.length, 2);
      expect(decoded.wantIds[0].length, 32);
      expect(decoded.wantIds[1].length, 32);
    });

    test('rejects > 1024 ids', () {
      expect(
        () => MeshRequest(
          header: _hdr(),
          wantIds: List.generate(1025, (_) => Uint8List(32)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('MeshData', () {
    test('round-trips with payload', () {
      final data = MeshData(
        header: _hdr(),
        itemKind: 'bulletin',
        jsonPayload: '{"id":"abc","kind":"Blood","body":"need O+"}',
      );
      final decoded = decodeMeshPacket(data.encode()) as MeshData;
      expect(decoded.itemKind, 'bulletin');
      expect(jsonDecode(decoded.jsonPayload), isA<Map<String, dynamic>>());
    });

    test('rejects oversized payload', () {
      expect(
        () => MeshData(
          header: _hdr(),
          itemKind: 'bulletin',
          jsonPayload: 'x' * (meshMaxPayloadBytes + 1),
        ),
        // Construction itself doesn't throw; decode throws on the wire.
        // We construct then call encode + decode.
        returnsNormally,
      );
      final huge = MeshData(
        header: _hdr(),
        itemKind: 'bulletin',
        jsonPayload: 'x' * (meshMaxPayloadBytes + 1),
      );
      expect(() => decodeMeshPacket(huge.encode()), throwsFormatException);
    });
  });

  group('MeshAck', () {
    test('round-trips an ack id', () {
      final ack = MeshAck(
        header: _hdr(),
        ackPacketId: Uint8List.fromList(List<int>.generate(32, (i) => 255 - i)),
      );
      final decoded = decodeMeshPacket(ack.encode()) as MeshAck;
      expect(decoded.ackPacketId, ack.ackPacketId);
    });
  });

  group('decodeMeshPacket', () {
    test('rejects malformed JSON', () {
      expect(() => decodeMeshPacket('not json'), throwsFormatException);
    });

    test('rejects non-object root', () {
      expect(() => decodeMeshPacket('[1,2,3]'), throwsFormatException);
    });

    test('rejects missing header', () {
      expect(
        () => decodeMeshPacket(jsonEncode({'b': {'kind': 'ack'}})),
        throwsFormatException,
      );
    });

    test('rejects unknown envelope kind', () {
      final raw = jsonEncode({
        'h': {'v': meshProtocolVersion, 'p': base64Encode(Uint8List(32)), 'peer': 'p'},
        'b': {'kind': 'wat'},
      });
      expect(() => decodeMeshPacket(raw), throwsFormatException);
    });

    test('rejects version mismatch', () {
      final raw = jsonEncode({
        'h': {'v': 999, 'p': base64Encode(Uint8List(32)), 'peer': 'p'},
        'b': {'kind': 'ack', 'ack': base64Encode(Uint8List(32))},
      });
      expect(() => decodeMeshPacket(raw), throwsFormatException);
    });

    test('rejects wrong-length packet id', () {
      final raw = jsonEncode({
        'h': {'v': meshProtocolVersion, 'p': base64Encode(Uint8List(16)), 'peer': 'p'},
        'b': {'kind': 'ack', 'ack': base64Encode(Uint8List(32))},
      });
      expect(() => decodeMeshPacket(raw), throwsFormatException);
    });
  });
}
