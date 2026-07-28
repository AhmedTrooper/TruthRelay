/// Unit tests for the BLE-based mesh discovery layer.
///
/// All tests run against a fake [BleDiscoveryBackend] so they do not require
/// real BLE hardware. The fake captures the most recently encoded
/// [MeshPeerAdvertisement] and emits scripted scan results, exactly the way
/// `flutter_blue_plus` would in production.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/ble_discovery.dart';

/// In-memory backend that lets the test dictate the peer list and status
/// stream without any plugin involvement.
class _FakeBackend implements BleDiscoveryBackend {
  final _peers = StreamController<List<MeshPeer>>.broadcast();
  final _status = StreamController<DiscoveryStatus>.broadcast();
  MeshPeerAdvertisement? lastAdvertisement;
  bool advertising = false;
  bool scanning = false;
  bool supportsBle = true;
  int stopCalls = 0;

  @override
  Future<bool> ensurePermissions() async {
    if (!supportsBle) {
      _status.add(DiscoveryStatus.denied);
      return false;
    }
    return true;
  }

  @override
  Future<void> startScanning({Duration? window}) async {
    scanning = true;
    _status.add(DiscoveryStatus.scanning);
  }

  @override
  Future<void> stopScanning() async {
    scanning = false;
    _status.add(DiscoveryStatus.idle);
    stopCalls += 1;
  }

  @override
  Future<void> startAdvertising(MeshPeerAdvertisement ad) async {
    advertising = true;
    lastAdvertisement = ad;
    _status.add(DiscoveryStatus.advertising);
  }

  @override
  Future<void> stopAdvertising() async {
    advertising = false;
    _status.add(DiscoveryStatus.idle);
  }

  @override
  Stream<List<MeshPeer>> get discoveredPeers => _peers.stream;

  @override
  Stream<DiscoveryStatus> get status => _status.stream;

  void emit(List<MeshPeer> peers) {
    if (!_peers.isClosed) _peers.add(peers);
  }

  Future<void> dispose() async {
    await _peers.close();
    await _status.close();
  }
}

void main() {
  test('MeshPeerAdvertisement round-trips peer id + item count', () {
    final ad = MeshPeerAdvertisement(localPeerId: 'phone-1', itemCount: 42);
    expect(ad.bytes.length, lessThanOrEqualTo(MeshPeerAdvertisement.maxBytes));
    final decoded = MeshPeerAdvertisement.fromBytes(ad.bytes);
    expect(decoded.localPeerId, 'phone-1');
    expect(decoded.itemCount, 42);
  });

  test('MeshPeerAdvertisement rejects unknown magic', () {
    final bogus = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0x01]);
    expect(() => MeshPeerAdvertisement.fromBytes(bogus),
        throwsA(isA<FormatException>()));
  });

  test('MeshPeerAdvertisement rejects unsupported version', () {
    final bytes = Uint8List.fromList([0x31, 0x52, 0x54, 0x99, 0x00, 0x00, 0x00]);
    expect(() => MeshPeerAdvertisement.fromBytes(bytes),
        throwsA(isA<FormatException>()));
  });

  test('BleDiscovery.start forwards scan results to peers stream', () async {
    final fake = _FakeBackend();
    final discovery = BleDiscovery(backend: fake);
    final received = <List<MeshPeer>>[];
    final sub = discovery.peers.listen(received.add);

    await discovery.start();
    fake.emit(const [
      MeshPeer(
        deviceAddress: 'AA:BB:CC:DD:EE:FF',
        deviceName: 'scan-a',
        isGroupOwner: false,
      ),
    ]);
    fake.emit(const [
      MeshPeer(
        deviceAddress: '11:22:33:44:55:66',
        deviceName: 'scan-b',
        isGroupOwner: false,
      ),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    await discovery.stop();
    await fake.dispose();

    expect(received, hasLength(2));
    expect(received.last.single.deviceName, 'scan-b');
    expect(received.last.single.isGroupOwner, isFalse);
  });

  test('BleDiscovery.startAdvertising captures the broadcast payload',
      () async {
    final fake = _FakeBackend();
    final discovery = BleDiscovery(backend: fake);
    await discovery.start();
    await discovery.startAdvertising(
      MeshPeerAdvertisement(localPeerId: 'me', itemCount: 7),
    );
    expect(fake.lastAdvertisement, isNotNull);
    expect(fake.lastAdvertisement!.itemCount, 7);
    expect(fake.lastAdvertisement!.localPeerId, 'me');
    await discovery.stopAdvertising();
    await fake.dispose();
  });

  test('BleDiscovery combined lifecycle status reflects advertising + scan',
      () async {
    final fake = _FakeBackend();
    final discovery = BleDiscovery(backend: fake);
    final statuses = <DiscoveryStatus>[];
    final sub = discovery.status.listen(statuses.add);
    await discovery.start();
    await discovery.startAdvertising(
      MeshPeerAdvertisement(localPeerId: 'me', itemCount: 1),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    await discovery.dispose();
    await fake.dispose();
    expect(statuses, contains(DiscoveryStatus.advertisingAndScanning));
  });

  test('BleDiscovery surfaces denial when the backend returns false',
      () async {
    final fake = _FakeBackend()..supportsBle = false;
    final discovery = BleDiscovery(backend: fake);
    final statuses = <DiscoveryStatus>[];
    final sub = discovery.status.listen(statuses.add);
    final granted = await discovery.ensurePermissions();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await sub.cancel();
    await fake.dispose();
    expect(granted, isFalse);
    expect(statuses, contains(DiscoveryStatus.denied));
  });

  test('BleDiscovery.dispose stops scanning and closes streams', () async {
    final fake = _FakeBackend();
    final discovery = BleDiscovery(backend: fake);
    await discovery.start();
    await discovery.dispose();
    expect(fake.stopCalls, 1);
    expect(discovery.peers.isBroadcast, isTrue);
  });
}
