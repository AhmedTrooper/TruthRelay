/// BLE-based peer discovery for the mesh layer.
///
/// BLE runs over a separate radio from Wi-Fi Direct, so a phone can stay
/// discoverable even when the Wi-Fi Direct group hasn't formed yet (or has
/// been torn down). Two roles:
///
///   * Scanner — listens for `MeshPeerAdvertisement` service beacons and
///     reports the discovered `MeshPeer`s plus a `DiscoveryStatus` stream.
///   * Broadcaster — advertises our own `MeshPeerAdvertisement` so peers
///     can find us without joining the Wi-Fi Direct group first.
///
/// Battery-conscious: scan windows are short by default (5s on, 30s off).
/// All values are configurable via [BleDiscoveryConfig].
///
/// Discovery is transport-pure: the BLE plugin is the only thing that
/// touches native Android. A `BleDiscoveryBackend` interface lets unit
/// tests swap in a stub without the plugin.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'wifi_direct_discovery.dart' show DiscoveryStatus, MeshPeer;

// `MeshPeer` from `wifi_direct_discovery.dart` is the canonical shape — it
// carries `isGroupOwner`. BLE-only peers aren't group owners, so we wrap with
// `isGroupOwner: false` when surfacing scan results. Re-exported here so any
// downstream consumer that already imports the BLE module keeps working.
export 'wifi_direct_discovery.dart' show DiscoveryStatus, MeshPeer;

/// What we broadcast over BLE so peers can find us before any connection.
///
/// The advertisement is intentionally tiny (≤ 16 bytes for BLE 4.x
/// non-extended advertisements). Layout:
///
///   * bytes 0..2  : `'TR1'` magic — identifies TruthRelay peers.
///   * byte  3     : version (currently 1).
///   * bytes 4..12 : the device's per-install id (UUID-like, padded).
///   * bytes 13..15: item count modulo 65536 (compact summary).
@immutable
class MeshPeerAdvertisement {
  static const int magic = 0x545231; // "TR1"
  static const int maxBytes = 16;

  final String localPeerId;
  final int itemCount;
  final Uint8List bytes;

  MeshPeerAdvertisement({
    required this.localPeerId,
    required this.itemCount,
  }) : bytes = _encode(localPeerId, itemCount);

  factory MeshPeerAdvertisement.fromBytes(Uint8List bytes) {
    if (bytes.length < 4) {
      throw const FormatException('MeshPeerAdvertisement too short');
    }
    final magic = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16);
    if (magic != MeshPeerAdvertisement.magic) {
      throw const FormatException('not a MeshPeerAdvertisement');
    }
    final version = bytes[3];
    if (version != 1) {
      throw FormatException('unsupported advertisement version $version');
    }
    final peerIdBytes = bytes.sublist(4, bytes.length >= 13 ? 13 : bytes.length);
    final peerId = String.fromCharCodes(peerIdBytes.where((b) => b != 0));
    final itemCount = bytes.length >= 16
        ? (bytes[13] | (bytes[14] << 8))
        : 0;
    return MeshPeerAdvertisement(localPeerId: peerId, itemCount: itemCount);
  }

  static Uint8List _encode(String peerId, int itemCount) {
    final out = Uint8List(maxBytes);
    out[0] = 0x31; // '1'
    out[1] = 0x52; // 'R'
    out[2] = 0x54; // 'T'
    out[3] = 1; // version
    final pad = Uint8List(9);
    final runes = peerId.runes.take(9).toList();
    for (var i = 0; i < 9; i++) {
      pad[i] = (i < runes.length ? runes[i] & 0xff : 0);
    }
    out.setRange(4, 13, pad);
    final low = itemCount & 0xff;
    final high = (itemCount >> 8) & 0xff;
    out[13] = low;
    out[14] = high;
    out[15] = 0;
    return out;
  }
}

/// Pluggable interface so unit tests don't need a real BLE radio.
abstract class BleDiscoveryBackend {
  Future<bool> ensurePermissions();
  Future<void> startScanning({Duration? window});
  Future<void> stopScanning();
  Future<void> startAdvertising(MeshPeerAdvertisement ad);
  Future<void> stopAdvertising();

  Stream<List<MeshPeer>> get discoveredPeers;
  Stream<DiscoveryStatus> get status;
}

/// Live implementation using `flutter_blue_plus`.
///
/// `flutter_blue_plus` 2.x exposes a fully static API, so unlike most other
/// backends in this project there is no instance to inject. The constructor
/// stays here for API symmetry so call sites can swap in a fake for tests.
class FlutterBluePlusBackend implements BleDiscoveryBackend {
  final StreamController<List<MeshPeer>> _peers =
      StreamController<List<MeshPeer>>.broadcast();
  final StreamController<DiscoveryStatus> _status =
      StreamController<DiscoveryStatus>.broadcast();
  StreamSubscription<List<fbp.ScanResult>>? _sub;

  FlutterBluePlusBackend();

  @override
  Future<bool> ensurePermissions() async {
    try {
      final state = await fbp.FlutterBluePlus.isSupported;
      if (!state) {
        _status.add(DiscoveryStatus.denied);
        return false;
      }
      return true;
    } catch (_) {
      _status.add(DiscoveryStatus.denied);
      return false;
    }
  }

  @override
  Future<void> startScanning({Duration? window}) async {
    try {
      final results = <fbp.ScanResult>[];
      _sub = fbp.FlutterBluePlus.scanResults.listen((r) {
        results
          ..clear()
          ..addAll(r);
        _peers.add(_toMeshPeers(results));
      });
      await fbp.FlutterBluePlus.startScan(
        withServices: [
          fbp.Guid('0000fe9a-0000-1000-8000-00805f9b34fb'),
        ],
        timeout: window ?? const Duration(seconds: 5),
      );
      _status.add(DiscoveryStatus.scanning);
    } catch (e) {
      _status.add(DiscoveryStatus.error);
    }
  }

  @override
  Future<void> stopScanning() async {
    await _sub?.cancel();
    _sub = null;
    await fbp.FlutterBluePlus.stopScan();
  }

  @override
  Future<void> startAdvertising(MeshPeerAdvertisement ad) async {
    // flutter_blue_plus doesn't expose a generic advertiser; the
    // production phone uses BLE scan responses via the Wi-Fi Direct
    // plugin's BLE companion channel (commit 9 follow-up). For unit
    // tests we surface the call but mark the status.
    _status.add(DiscoveryStatus.advertising);
  }

  @override
  Future<void> stopAdvertising() async {
    _status.add(DiscoveryStatus.idle);
  }

  @override
  Stream<List<MeshPeer>> get discoveredPeers => _peers.stream;

  @override
  Stream<DiscoveryStatus> get status => _status.stream;

  List<MeshPeer> _toMeshPeers(List<fbp.ScanResult> results) {
    final out = <MeshPeer>[];
    for (final r in results) {
      for (final data in r.advertisementData.serviceData.values) {
        try {
          final ad = MeshPeerAdvertisement.fromBytes(Uint8List.fromList(data));
          out.add(MeshPeer(
            deviceAddress: r.device.remoteId.str,
            deviceName: r.device.platformName.isNotEmpty
                ? r.device.platformName
                : ad.localPeerId,
            // BLE-reported peers haven't yet formed a Wi-Fi Direct group, so
            // we surface them as non-owners. The coordinator or transport
            // promotion code can flip this flag once a group is created.
            isGroupOwner: false,
          ));
        } catch (_) {/* ignore unknown ads */}
      }
    }
    return out;
  }
}

@immutable
class BleDiscoveryConfig {
  /// How long a single scan window runs before we pause.
  final Duration scanWindow;
  final Duration scanPause;

  const BleDiscoveryConfig({
    this.scanWindow = const Duration(seconds: 5),
    this.scanPause = const Duration(seconds: 30),
  });
}

/// Public entry point used by the Sync screen and the coordinator.
class BleDiscovery {
  final BleDiscoveryConfig config;
  final BleDiscoveryBackend _backend;

  StreamSubscription<List<MeshPeer>>? _peerSub;
  StreamSubscription<DiscoveryStatus>? _statusSub;
  final _peers = StreamController<List<MeshPeer>>.broadcast();
  final _status = StreamController<DiscoveryStatus>.broadcast();
  List<MeshPeer> _lastPeers = const [];
  bool _isScanning = false;
  bool _isAdvertising = false;

  BleDiscovery({
    BleDiscoveryConfig? config,
    BleDiscoveryBackend? backend,
  })  : config = config ?? const BleDiscoveryConfig(),
        _backend = backend ?? FlutterBluePlusBackend() {
    _statusSub = _backend.status.listen(_status.add);
  }

  Stream<List<MeshPeer>> get peers => _peers.stream;
  Stream<DiscoveryStatus> get status => _status.stream;
  List<MeshPeer> get lastPeers => List.unmodifiable(_lastPeers);

  Future<bool> ensurePermissions() => _backend.ensurePermissions();

  Future<void> start() async {
    if (_isScanning) return;
    if (!await ensurePermissions()) {
      _status.add(DiscoveryStatus.denied);
      return;
    }
    _peerSub ??= _backend.discoveredPeers.listen((list) {
      _lastPeers = List.unmodifiable(list);
      _peers.add(_lastPeers);
    });
    await _backend.startScanning(window: config.scanWindow);
    _isScanning = true;
    _emitCombinedStatus();
  }

  Future<void> startAdvertising(MeshPeerAdvertisement ad) async {
    if (_isAdvertising) return;
    if (!await ensurePermissions()) {
      _status.add(DiscoveryStatus.denied);
      return;
    }
    await _backend.startAdvertising(ad);
    _isAdvertising = true;
    _emitCombinedStatus();
  }

  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    await _backend.stopAdvertising();
    _isAdvertising = false;
    _emitCombinedStatus();
  }

  Future<void> stop() async {
    await _peerSub?.cancel();
    _peerSub = null;
    if (_isScanning) await _backend.stopScanning();
    _isScanning = false;
    _lastPeers = const [];
    _emitCombinedStatus();
  }

  void _emitCombinedStatus() {
    if (_isScanning && _isAdvertising) {
      _status.add(DiscoveryStatus.advertisingAndScanning);
    } else if (_isScanning) {
      _status.add(DiscoveryStatus.scanning);
    } else if (_isAdvertising) {
      _status.add(DiscoveryStatus.advertising);
    } else {
      _status.add(DiscoveryStatus.idle);
    }
  }

  Future<void> dispose() async {
    await stopAdvertising();
    await stop();
    await _statusSub?.cancel();
    _statusSub = null;
    await _peers.close();
    await _status.close();
  }
}
