/// Unit tests for the Wi-Fi Direct discovery wrapper.
///
/// We test the parts we can isolate without invoking the platform channel:
///   * `MeshPeer.fromBleDevice` translates the plugin's payload faithfully
///   * Permission denial path emits [DiscoveryStatus.denied]
///   * `start` is idempotent and tolerates backend errors
///
/// The actual platform-channel calls are covered by manual + instrumented
/// tests on a real Android device.
library;

import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/wifi_direct_discovery.dart';
import 'package:mobile/features/mesh/src/mesh_discovery_backend.dart';

/// Test double that satisfies [MeshDiscoveryBackend] without touching the
/// platform channel. Each test mutates the booleans it cares about.
class _FakeBackend implements MeshDiscoveryBackend {
  _FakeBackend();

  bool askP2pResult = true;
  bool locationEnabledResult = true;
  bool wifiEnabledResult = true;
  bool initialized = false;
  bool shouldThrowOnStartScan = false;

  final _controller = StreamController<List<BleDiscoveredDevice>>.broadcast();
  StreamSubscription<List<BleDiscoveredDevice>>? _sub;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<bool> askP2pPermissions() async => askP2pResult;

  @override
  Future<bool> checkP2pPermissions() async => askP2pResult;

  @override
  Future<bool> checkLocationEnabled() async => locationEnabledResult;

  @override
  Future<bool> checkWifiEnabled() async => wifiEnabledResult;

  @override
  Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(
    void Function(List<BleDiscoveredDevice>) onData, {
    Function? onError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    if (shouldThrowOnStartScan) {
      throw StateError('backend unavailable');
    }
    _sub = _controller.stream.listen(onData, onError: onError);
    return _sub!;
  }

  @override
  Future<void> stopScan() async {
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    await _sub?.cancel();
  }

  /// Test helper: inject a peer-list event into the fake scan stream.
  void emit(List<BleDiscoveredDevice> devices) => _controller.add(devices);
}

void main() {
  group('MeshPeer.fromBleDevice', () {
    test('translates the plugin payload faithfully', () {
      const d = BleDiscoveredDevice(
        deviceAddress: 'aa:bb:cc:dd:ee:ff',
        deviceName: 'Pixel',
      );
      final p = MeshPeer.fromBleDevice(d);
      expect(p.deviceName, 'Pixel');
      expect(p.deviceAddress, 'aa:bb:cc:dd:ee:ff');
      expect(p.isGroupOwner, isTrue);
    });

    test('value equality holds for identical inputs', () {
      const d1 = BleDiscoveredDevice(deviceAddress: 'a', deviceName: 'b');
      const d2 = BleDiscoveredDevice(deviceAddress: 'a', deviceName: 'b');
      expect(MeshPeer.fromBleDevice(d1), MeshPeer.fromBleDevice(d2));
    });
  });

  group('ensurePermissions', () {
    test('returns false and emits denied when permission is denied', () async {
      final fake = _FakeBackend()..askP2pResult = false;
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      final ok = await d.ensurePermissions();
      expect(ok, isFalse);
      expect(d.currentStatus, DiscoveryStatus.denied);
    });

    test('returns false when Wi-Fi is off', () async {
      final fake = _FakeBackend()..wifiEnabledResult = false;
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      final ok = await d.ensurePermissions();
      expect(ok, isFalse);
      expect(d.currentStatus, DiscoveryStatus.denied);
    });

    test('returns true and leaves status unchanged when everything is on',
        () async {
      final fake = _FakeBackend();
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      final ok = await d.ensurePermissions();
      expect(ok, isTrue);
      // No status flip — we only move to `scanning` once start() runs.
      expect(d.currentStatus, DiscoveryStatus.idle);
    });
  });

  group('start / stop lifecycle', () {
    test('start initializes backend and transitions to scanning', () async {
      final fake = _FakeBackend();
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      await d.start();
      expect(fake.initialized, isTrue);
      expect(d.currentStatus, DiscoveryStatus.scanning);

      await d.stop();
      expect(d.currentStatus, DiscoveryStatus.idle);
    });

    test('start is idempotent (second call is a no-op)', () async {
      final fake = _FakeBackend();
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      await d.start();
      await d.start(); // must not re-initialize or re-scan
      expect(fake.initialized, isTrue);
      expect(d.currentStatus, DiscoveryStatus.scanning);

      await d.stop();
    });

    test('start emits error when the backend throws', () async {
      final fake = _FakeBackend()..shouldThrowOnStartScan = true;
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      await d.start();
      expect(d.currentStatus, DiscoveryStatus.error);

      await d.stop();
    });

    test('peer events propagate through the peers stream', () async {
      final fake = _FakeBackend();
      final d = WifiDirectDiscovery(backend: fake);
      addTearDown(d.dispose);

      await d.start();
      final received = <List<MeshPeer>>[];
      final sub = d.peers.listen(received.add);

      const device = BleDiscoveredDevice(
        deviceAddress: '11:22',
        deviceName: 'host-x',
      );
      fake.emit([device]);

      // Allow the broadcast stream to deliver.
      await Future<void>.delayed(Duration.zero);
      expect(received, hasLength(1));
      expect(received.first.single.deviceAddress, '11:22');
      expect(received.first.single.deviceName, 'host-x');

      await sub.cancel();
      await d.stop();
    });
  });
}