import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

class SyncView extends ConsumerStatefulWidget {
  const SyncView({super.key});

  @override
  ConsumerState<SyncView> createState() => _SyncViewState();
}

class _SyncViewState extends ConsumerState<SyncView> {
  bool _busy = false;
  String? _lastResult;
  String? _lastError;

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

  @override
  Widget build(BuildContext context) {
    final api = ref.read(apiClientProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sync')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('API endpoint', style: Theme.of(context).textTheme.labelMedium),
                    const SizedBox(height: 4),
                    SelectableText(api.baseUrl, style: const TextStyle(fontFamily: 'monospace')),
                    const SizedBox(height: 8),
                    Text(
                      'Override via: flutter run --dart-define=TRUTHRELAY_API_URL=...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: FilledButton.icon(onPressed: _busy ? null : _pull, icon: const Icon(Icons.download), label: const Text('Pull'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.tonalIcon(onPressed: _busy ? null : _push, icon: const Icon(Icons.upload), label: const Text('Push'))),
            ]),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_lastResult != null) ...[
              const SizedBox(height: 12),
              Text(_lastResult!, style: const TextStyle(color: Colors.greenAccent)),
            ],
            if (_lastError != null) ...[
              const SizedBox(height: 12),
              Text(_lastError!, style: const TextStyle(color: Colors.redAccent)),
            ],
          ],
        ),
      ),
    );
  }
}