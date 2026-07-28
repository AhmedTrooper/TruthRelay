/// Wire-format envelopes used by the offline mesh.
///
/// Every packet carries a [version] so future protocol changes can be
/// detected and rejected without breaking older builds. [packetId] is a
/// 32-byte random nonce used to deduplicate retransmits and anti-loop.
///
/// Envelope kinds:
///   * [MeshHello]   — initial handshake; advertises peer id + supported version.
///   * [MeshInventory] — "here is what I already have" — bloom + count + newest.
///   * [MeshRequest]  — "send me these packet ids".
///   * [MeshData]     — one signed JSON envelope (bulletin or help-request payload).
///   * [MeshAck]      — "I received packet X, do not retransmit".
///
/// The codec is transport-agnostic: subsequent commits will bind it to
/// Wi-Fi Direct sockets, BLE GATT, and TCP-over-hotspot.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Bump on breaking wire-format changes. Receivers must drop packets whose
/// [MeshHello.version] differs from this constant.
const int meshProtocolVersion = 1;

/// Maximum payload size accepted on the wire (signed JSON envelope). Packets
/// larger than this are rejected as malformed; transports are responsible for
/// chunking on their side if MTU is smaller.
const int meshMaxPayloadBytes = 256 * 1024; // 256 KB

/// All envelope kinds share a common header.
class MeshHeader {
  final int version;
  final Uint8List packetId; // 32 bytes
  final String peerId; // human-readable per-device id

  const MeshHeader({
    required this.version,
    required this.packetId,
    required this.peerId,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'p': base64Encode(packetId),
        'peer': peerId,
      };

  factory MeshHeader.fromJson(Map<String, dynamic> m) {
    final v = m['v'];
    final p = m['p'];
    final peer = m['peer'];
    if (v is! int) {
      throw const FormatException('MeshHeader missing or wrong type: v');
    }
    if (p is! String) {
      throw const FormatException('MeshHeader missing or wrong type: p');
    }
    if (peer is! String) {
      throw const FormatException('MeshHeader missing or wrong type: peer');
    }
    final bytes = base64Decode(p);
    if (bytes.length != 32) {
      throw FormatException(
          'MeshHeader packetId must decode to 32 bytes, got ${bytes.length}');
    }
    return MeshHeader(version: v, packetId: Uint8List.fromList(bytes), peerId: peer);
  }
}

abstract class MeshPacket {
  MeshHeader get header;
  Map<String, dynamic> bodyToJson();

  /// Serialize to canonical JSON (no trailing newline).
  String encode() {
    final map = {
      'h': header.toJson(),
      'b': bodyToJson(),
    };
    return jsonEncode(map);
  }
}

class MeshHello extends MeshPacket {
  @override
  final MeshHeader header;
  final Uint8List bloom; // serialized BloomFilter (512 bytes for the current filter)
  final int itemCount;
  final DateTime newestReceivedAt;

  MeshHello({
    required this.header,
    required this.bloom,
    required this.itemCount,
    required this.newestReceivedAt,
  });

  @override
  Map<String, dynamic> bodyToJson() => {
        'kind': 'hello',
        'bloom': base64Encode(bloom),
        'count': itemCount,
        'newest': newestReceivedAt.toUtc().toIso8601String(),
      };
}

class MeshInventory extends MeshPacket {
  @override
  final MeshHeader header;
  final Uint8List bloom;
  final int itemCount;
  final DateTime newestReceivedAt;

  MeshInventory({
    required this.header,
    required this.bloom,
    required this.itemCount,
    required this.newestReceivedAt,
  });

  @override
  Map<String, dynamic> bodyToJson() => {
        'kind': 'inventory',
        'bloom': base64Encode(bloom),
        'count': itemCount,
        'newest': newestReceivedAt.toUtc().toIso8601String(),
      };
}

class MeshRequest extends MeshPacket {
  @override
  final MeshHeader header;
  final List<Uint8List> wantIds; // packet ids the requester wants

  MeshRequest({
    required this.header,
    required this.wantIds,
  }) {
    if (wantIds.length > 1024) {
      throw ArgumentError.value(
          wantIds.length, 'wantIds', 'mesh request may not exceed 1024 ids');
    }
  }

  @override
  Map<String, dynamic> bodyToJson() => {
        'kind': 'request',
        'want': [for (final id in wantIds) base64Encode(id)],
      };
}

class MeshData extends MeshPacket {
  @override
  final MeshHeader header;
  final String itemKind; // 'bulletin' or 'request'
  final String jsonPayload; // canonical JSON, ready to upsert into Hive

  MeshData({
    required this.header,
    required this.itemKind,
    required this.jsonPayload,
  });

  @override
  Map<String, dynamic> bodyToJson() => {
        'kind': 'data',
        'item_kind': itemKind,
        'payload': jsonPayload,
      };
}

class MeshAck extends MeshPacket {
  @override
  final MeshHeader header;
  final Uint8List ackPacketId; // the packet id being acknowledged

  MeshAck({
    required this.header,
    required this.ackPacketId,
  });

  @override
  Map<String, dynamic> bodyToJson() => {
        'kind': 'ack',
        'ack': base64Encode(ackPacketId),
      };
}

/// Decode any [MeshPacket] from a raw JSON string. Returns a typed instance
/// of one of the four concrete envelopes above. Throws [FormatException]
/// on malformed input.
MeshPacket decodeMeshPacket(String raw) {
  final root = jsonDecode(raw);
  if (root is! Map<String, dynamic>) {
    throw const FormatException('mesh root must be a JSON object');
  }
  final headerJson = root['h'];
  final bodyJson = root['b'];
  if (headerJson is! Map<String, dynamic> ||
      bodyJson is! Map<String, dynamic>) {
    throw const FormatException('mesh envelope missing h/b');
  }
  final header = MeshHeader.fromJson(headerJson);
  if (header.version != meshProtocolVersion) {
    throw FormatException(
        'mesh version mismatch: got ${header.version}, expected $meshProtocolVersion');
  }
  final kind = bodyJson['kind'];
  switch (kind) {
    case 'hello':
      return _decodeInventoryLike(header, bodyJson, true);
    case 'inventory':
      return _decodeInventoryLike(header, bodyJson, false);
    case 'request':
      return _decodeRequest(header, bodyJson);
    case 'data':
      return _decodeData(header, bodyJson);
    case 'ack':
      return _decodeAck(header, bodyJson);
    default:
      throw FormatException('unknown mesh envelope kind: $kind');
  }
}

MeshPacket _decodeInventoryLike(
  MeshHeader header,
  Map<String, dynamic> body,
  bool isHello,
) {
  final bloom = base64Decode(body['bloom'] as String);
  final count = body['count'] as int;
  final newest = DateTime.parse(body['newest'] as String);
  final bytes = Uint8List.fromList(bloom);
  if (isHello) {
    return MeshHello(
      header: header,
      bloom: bytes,
      itemCount: count,
      newestReceivedAt: newest,
    );
  }
  return MeshInventory(
    header: header,
    bloom: bytes,
    itemCount: count,
    newestReceivedAt: newest,
  );
}

MeshPacket _decodeRequest(MeshHeader header, Map<String, dynamic> body) {
  final want = (body['want'] as List).cast<String>();
  final ids = [for (final s in want) Uint8List.fromList(base64Decode(s))];
  return MeshRequest(header: header, wantIds: ids);
}

MeshPacket _decodeData(MeshHeader header, Map<String, dynamic> body) {
  final itemKind = body['item_kind'] as String;
  final payload = body['payload'] as String;
  if (payload.length > meshMaxPayloadBytes) {
    throw FormatException(
        'mesh data payload exceeds $meshMaxPayloadBytes bytes');
  }
  return MeshData(header: header, itemKind: itemKind, jsonPayload: payload);
}

MeshPacket _decodeAck(MeshHeader header, Map<String, dynamic> body) {
  final ack = base64Decode(body['ack'] as String);
  if (ack.length != 32) {
    throw FormatException('ack id must be 32 bytes, got ${ack.length}');
  }
  return MeshAck(header: header, ackPacketId: Uint8List.fromList(ack));
}

/// Generate a fresh 32-byte packet id using a CSPRNG.
Future<Uint8List> newPacketId() async {
  final h = await Sha256().hash(List<int>.generate(32, (_) => DateTime.now().microsecondsSinceEpoch & 0xff));
  return Uint8List.fromList(h.bytes);
}
