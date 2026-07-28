import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../mesh/data/ble_discovery.dart' show DiscoveryStatus;
import '../../mesh/data/mesh_coordinator.dart' as coord;
import '../../mesh/data/wifi_direct_discovery.dart' as wifi show MeshPeer;
import 'sync_view_model.dart';

class SyncView extends ConsumerStatefulWidget {
  const SyncView({super.key});

  @override
  ConsumerState<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends ConsumerState<SyncView> {
  bool _busy = false;
  String? _lastResult;
  String? _lastError;
  SyncViewSnapshot _snapshot = SyncViewSnapshot.empty;
  List<coord.MeshPeer> _peers = const <coord.MeshPeer>[];
  DiscoveryStatus _status = DiscoveryStatus.idle;

  @override
  void initState() {
    super.initState();
    // Subscribe to mesh session results once so peer rows update live.
    ref.read(meshCoordinatorProvider).start();
    ref.read(meshCoordinatorProvider).results.listen((_) {
      if (mounted) setState(() {});
    });
    // Bridge broadcast streams into cached values (broadcast streams are
    // racy for late subscribers; this keeps a single live subscription per
    // stream alive for the lifetime of the screen).
    final discovery = ref.read(wifiDirectDiscoveryProvider);
    discovery.peers.listen((peers) {
      if (!mounted) return;
      setState(() {
        _peers = peers
            .map<coord.MeshPeer>(
              (wifi.MeshPeer p) => coord.MeshPeer(
                deviceAddress: p.deviceAddress,
                deviceName: p.deviceName,
              ),
            )
            .toList();
      });
    });
    discovery.status.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
    });
  }

  void _refresh() {
    final coordinator = ref.read(meshCoordinatorProvider);
    final vm = SyncViewModel(
      peers: _peers,
      status: _status,
      history: coordinator.history,
    );
    setState(() => _snapshot = vm.snapshot());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _pull() async {
    setState(() {
      _busy = true;
      _lastError = null;
      _lastResult = null;
    });
    try {
      final n = await ref.read(syncServiceProvider).pull();
      setState(() => _lastResult = 'Pulled $n items.');
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _push() async {
    setState(() {
      _busy = true;
      _lastError = null;
      _lastResult = null;
    });
    try {
      final n = await ref.read(syncServiceProvider).pushPending();
      setState(() => _lastResult = 'Pushed $n items.');
      ref.invalidate(pendingOutboxCountProvider);
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Force every known peer into the "needs sync" state. The coordinator
  /// re-runs its backoff gate, so peers that just synced are skipped.
  void _syncNow() {
    for (final row in _snapshot.peers) {
      ref.read(meshCoordinatorProvider).forceResync(row.deviceAddress);
    }
    setState(() {
      _lastResult = 'Re-triggered sync for ${_snapshot.peers.length} peer(s).';
      _lastError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _apiCard(context, api.baseUrl),
            const SizedBox(height: 16),
            _buttonRow(),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_lastResult != null) ...[
              const SizedBox(height: 12),
              Text(_lastResult!, style: const TextStyle(color: Colors.greenAccent)),
            ],
            if (_lastError != null) ...[
              const SizedBox(height: 12),
              Text(_lastError!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 24),
            _meshSection(context),
          ],
        ),
      ),
    );
  }

  Widget _apiCard(BuildContext context, String url) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API endpoint', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(url, style: const TextStyle(fontFamily: 'monospace')),
              const SizedBox(height: 8),
              Text(
                'Override via: flutter run --dart-define=TRUTHRELAY_API_URL=...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );

  Widget _buttonRow() => Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: _busy ? null : _pull,
                icon: const Icon(Icons.download),
                label: const Text('Pull'))),
        const SizedBox(width: 12),
        Expanded(
            child: FilledButton.tonalIcon(
                onPressed: _busy ? null : _push,
                icon: const Icon(Icons.upload),
                label: const Text('Push'))),
      ]);

  Widget _meshSection(BuildContext context) {
    final s = _snapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text('Local mesh', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          Text(_discoveryLabel(s.discoveryStatus), style: TextStyle(color: _discoveryColor(s.discoveryStatus))),
        ]),
        const SizedBox(height: 4),
        Text(
          'Sessions: ${s.totalSessions} (${s.totalFailedSessions} failed). '
          'Sent: ${s.totalItemsSent}, Received: ${s.totalItemsReceived}. '
          'Last sync: ${formatRelativeTime(s.lastSync)}.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (s.peers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No nearby peers detected. Wi-Fi Direct and BLE are scanning — the '
              'coordinator will trigger a session as soon as a peer appears.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          )
        else
          ...s.peers.map((row) => _peerTile(context, row)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: s.peers.isEmpty ? null : _syncNow,
          icon: const Icon(Icons.refresh),
          label: const Text('Sync now (reset peer cooldown)'),
        ),
      ],
    );
  }

  Widget _peerTile(BuildContext context, PeerSyncRow row) {
    final (icon, color) = _peerIcon(row);
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(row.deviceName),
        subtitle: Text(_peerSubtitle(row)),
        trailing: _statusChip(row.status),
      ),
    );
  }

  Widget _statusChip(PeerSyncStatus status) {
    switch (status) {
      case PeerSyncStatus.active:
        return const Chip(
          label: Text('active'),
          backgroundColor: Color(0xFF1e3a8a),
          labelStyle: TextStyle(color: Color(0xFFbfdbfe)),
        );
      case PeerSyncStatus.ok:
        return const Chip(
          label: Text('ok'),
          backgroundColor: Color(0xFF065f46),
          labelStyle: TextStyle(color: Color(0xFF6ee7b7)),
        );
      case PeerSyncStatus.failed:
        return const Chip(
          label: Text('failed'),
          backgroundColor: Color(0xFF7f1d1d),
          labelStyle: TextStyle(color: Color(0xFFfecaca)),
        );
      case PeerSyncStatus.idle:
        return const Chip(
          label: Text('idle'),
          backgroundColor: Color(0xFF1e293b),
          labelStyle: TextStyle(color: Color(0xFFcbd5e1)),
        );
    }
  }

  String _peerSubtitle(PeerSyncRow row) {
    final transport = transportLabelFor(row.transportLabel);
    final counts = '↑${row.lastSent}  ↓${row.lastReceived}';
    final when = row.lastAttempt == null ? 'no session yet' : formatRelativeTime(row.lastAttempt);
    return '$transport · $counts · $when';
  }

  (IconData, Color) _peerIcon(PeerSyncRow row) {
    switch (row.status) {
      case PeerSyncStatus.active:
        return (Icons.sync, const Color(0xFF7dd3fc));
      case PeerSyncStatus.ok:
        return (Icons.check_circle, const Color(0xFF6ee7b7));
      case PeerSyncStatus.failed:
        return (Icons.error_outline, const Color(0xFFfda4af));
      case PeerSyncStatus.idle:
        return (Icons.devices, const Color(0xFFcbd5e1));
    }
  }

  String _discoveryLabel(DiscoveryStatus s) {
    switch (s) {
      case DiscoveryStatus.idle:
        return 'idle';
      case DiscoveryStatus.scanning:
        return 'scanning…';
      case DiscoveryStatus.advertising:
        return 'advertising…';
      case DiscoveryStatus.advertisingAndScanning:
        return 'advertising + scanning';
      case DiscoveryStatus.error:
        return 'error';
      case DiscoveryStatus.denied:
        return 'permission denied';
    }
  }

  Color _discoveryColor(DiscoveryStatus s) {
    switch (s) {
      case DiscoveryStatus.scanning:
      case DiscoveryStatus.advertising:
      case DiscoveryStatus.advertisingAndScanning:
        return const Color(0xFF6ee7b7);
      case DiscoveryStatus.error:
      case DiscoveryStatus.denied:
        return const Color(0xFFfda4af);
      case DiscoveryStatus.idle:
        return Colors.grey;
    }
  }
}