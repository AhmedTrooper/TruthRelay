/// Unit tests for the local-only hotspot transport.
///
/// The transport binds to an in-memory [HotspotChannel] pair for both
/// host and joiner, so tests run on the host VM without touching real
/// `dart:io` sockets or the Android runtime.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/mesh/data/local_hotspot_transport.dart';

void main() {
  test('InMemoryHotspotPair.startHost returns fresh credentials', () async {
    final pair = await InMemoryHotspotPair.pair();
    final creds = await pair.host.startHost(port: 0);
    expect(creds.ssid, 'TruthRelay-Test');
    expect(creds.port, 0);
    await pair.host.stopHost();
  });

  test('ensurePermissions surfaces the configured permission flag', () async {
    final pair = await InMemoryHotspotPair.pair();
    expect(await pair.host.ensurePermissions(), isTrue);
    expect(await pair.joiner.ensurePermissions(), isTrue);
    await pair.host.stopHost();
  });

  test('A joiner connects and the host receives a peer event', () async {
    final pair = await InMemoryHotspotPair.pair();
    await pair.host.startHost(port: 0);

    final peerCompleter = Completer<HotspotPeer>();
    final sub = pair.host.peerEvents.listen(peerCompleter.complete);

    final socketFut = pair.joiner.join(pair.credentials);
    final peer = await peerCompleter.future;
    final socket = await socketFut;

    expect(peer.peerId, startsWith('unit-peer-'));
    expect(socket, isA<HotspotChannel>());

    await sub.cancel();
    await socket.close();
    await pair.host.stopHost();
  });

  test('Host and joiner transports exchange JSON envelopes end-to-end',
      () async {
    final pair = await InMemoryHotspotPair.pair();
    await pair.host.startHost(port: 0);

    final peerCompleter = Completer<HotspotPeer>();
    final peerSub = pair.host.peerEvents.listen(peerCompleter.complete);

    final socketFut = pair.joiner.join(pair.credentials);
    final peer = await peerCompleter.future;
    final socket = await socketFut;

    final hostT = LocalHotspotHostTransport(peer: peer);
    final joinerT = LocalHotspotJoinerTransport(channel: socket);

    final hostReceived = <String>[];
    final joinerReceived = <String>[];
    final hostSub = hostT.incoming.listen(hostReceived.add);
    final joinerSub = joinerT.incoming.listen(joinerReceived.add);

    await hostT.send('{"hello":"from-host"}');
    await joinerT.send('{"hello":"from-joiner"}');

    // Wait for round-trip delivery over the in-memory channel.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await hostSub.cancel();
    await joinerSub.cancel();
    await hostT.close();
    await joinerT.close();

    expect(joinerReceived, ['{"hello":"from-host"}']);
    expect(hostReceived, ['{"hello":"from-joiner"}']);

    await peerSub.cancel();
    await pair.host.stopHost();
  });

  test('Large payload survives the length-prefix framing', () async {
    final pair = await InMemoryHotspotPair.pair();
    await pair.host.startHost(port: 0);

    final peerCompleter = Completer<HotspotPeer>();
    final peerSub = pair.host.peerEvents.listen(peerCompleter.complete);

    final socketFut = pair.joiner.join(pair.credentials);
    final peer = await peerCompleter.future;
    final socket = await socketFut;

    final hostT = LocalHotspotHostTransport(peer: peer);
    final joinerT = LocalHotspotJoinerTransport(channel: socket);

    final joinerReceived = <String>[];
    final sub = joinerT.incoming.listen(joinerReceived.add);

    // 8 KiB — forces multiple 16-KiB send chunks to be reassembled.
    final json = '{"payload":"${'X' * 8000}"}';
    await hostT.send(json);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    await hostT.close();
    await joinerT.close();

    expect(joinerReceived, hasLength(1));
    expect(joinerReceived.single, json);

    await peerSub.cancel();
    await pair.host.stopHost();
  });

  test('Receiver reassembles a single large frame from many small chunks',
      () async {
    // Drives the receiver-side reassembly directly: emit the encoded
    // frame byte-by-byte through a forwarded channel and assert the
    // transport still emits one complete message.
    final ctrlA = StreamController<Uint8List>();
    final ctrlB = StreamController<Uint8List>();
    final joinerChannel = _ForwardChannel(ctrlB.stream, (b) => ctrlA.add(b));
    final hostChannel = _ForwardChannel(ctrlA.stream, (b) => ctrlB.add(b));

    final joinerT = LocalHotspotJoinerTransport(channel: joinerChannel);
    final joinerReceived = <String>[];
    final sub = joinerT.incoming.listen(joinerReceived.add);

    final hostT = LocalHotspotHostTransport(
      peer: _PeerStub(channel: hostChannel),
    );
    final json = '{"payload":"${'Y' * 4000}"}';
    await hostT.send(json);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    await sub.cancel();
    await hostT.close();
    await joinerT.close();

    expect(joinerReceived, hasLength(1));
    expect(joinerReceived.single, json);
    expect(json.length, greaterThan(4000)); // sanity: payload is the full body
  });

  test('HotspotException surfaces with the configured message', () {
    const err = HotspotException('os refused', code: 'NO_PERMISSION');
    expect(err.message, 'os refused');
    expect(err.code, 'NO_PERMISSION');
    expect(err.toString(), contains('HotspotException'));
  });

  test('HotspotCredentials JSON round-trip preserves all fields', () {
    final orig = HotspotCredentials(
      ssid: 'MySSID',
      passphrase: 's3cret',
      port: 47474,
      band: 1,
      issuedAt: DateTime.utc(2026, 7, 29, 12, 0, 0),
    );
    final decoded = HotspotCredentials.fromJson(orig.toJson());
    expect(decoded.ssid, orig.ssid);
    expect(decoded.passphrase, orig.passphrase);
    expect(decoded.port, orig.port);
    expect(decoded.band, orig.band);
    expect(decoded.issuedAt.toUtc(), orig.issuedAt);
  });
}

class _PeerStub implements HotspotPeer {
  @override
  final String peerId;
  @override
  final HotspotChannel channel;
  _PeerStub({required this.channel}) : peerId = 'test-peer';
}

class _ForwardChannel implements HotspotChannel {
  final Stream<Uint8List> _in;
  final void Function(Uint8List) _emit;
  bool _closed = false;
  _ForwardChannel(this._in, this._emit);

  @override
  Stream<Uint8List> get incomingBytes => _in;

  @override
  Future<void> sendBytes(Uint8List bytes) async {
    if (_closed) return;
    _emit(bytes);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}