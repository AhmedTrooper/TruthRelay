import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../widgets/status_badge.dart';
import '../../bulletins/models/bulletin.dart';
import '../../requests/models/help_request.dart';

class DetailView extends ConsumerWidget {
  final DetailKind kind;
  final String id;
  const DetailView({super.key, required this.kind, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kind == DetailKind.bulletin) {
      final repo = ref.watch(bulletinRepoProvider);
      return FutureBuilder<Bulletin?>(
        future: repo.get(id),
        builder: (context, snap) {
          if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          final b = snap.data;
          if (b == null) return Scaffold(appBar: AppBar(), body: const Text('Not found'));
          return _Scaffold(
            title: b.title,
            body: b.body,
            badge: StatusBadge(kind: b.kind, verified: b.isVerified),
            extra: 'Status: ${b.status}\nReceived: ${b.receivedAt}',
          );
        },
      );
    }
    final repo = ref.watch(requestRepoProvider);
    return FutureBuilder<List<HelpRequest>>(
      future: repo.list(limit: 1000),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final r = snap.data!.where((x) => x.id == id).cast<HelpRequest?>().firstOrNull;
        if (r == null) return Scaffold(appBar: AppBar(), body: const Text('Not found'));
        return _Scaffold(
          title: r.title,
          body: r.body,
          badge: StatusBadge(kind: r.kind),
          extra: 'Location: ${r.location ?? '—'}\nContact: ${r.contact ?? '—'}',
        );
      },
    );
  }
}

enum DetailKind { bulletin, request }

class _Scaffold extends StatelessWidget {
  final String title;
  final String body;
  final Widget badge;
  final String? extra;
  const _Scaffold({required this.title, required this.body, required this.badge, this.extra});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Row(children: [badge]),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(body),
            if (extra != null) ...[
              const SizedBox(height: 24),
              Text(extra!, style: const TextStyle(color: Colors.grey)),
            ],
          ],
        ),
      ),
    );
  }
}