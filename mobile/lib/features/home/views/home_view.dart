import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../widgets/status_badge.dart';
import '../../bulletins/models/bulletin.dart';
import '../../requests/models/help_request.dart';

class HomeView extends ConsumerStatefulWidget {
  const HomeView({super.key});

  @override
  ConsumerState<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends ConsumerState<HomeView> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingOutboxCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TruthRelay'),
        bottom: TabBar(controller: _tab, tabs: const [
          Tab(text: 'Bulletins'),
          Tab(text: 'Requests'),
        ]),
        actions: [
          IconButton(
            tooltip: 'Sync',
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.sync),
                if (pending.valueOrNull != null && pending.valueOrNull! > 0)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '${pending.value}',
                        style: const TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: TabBarView(controller: _tab, children: const [
        _BulletinsTab(),
        _RequestsTab(),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/compose'),
        icon: const Icon(Icons.add),
        label: const Text('Post'),
      ),
    );
  }
}

class _BulletinsTab extends ConsumerWidget {
  const _BulletinsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(bulletinRepoProvider);
    return FutureBuilder<List<Bulletin>>(
      future: repo.list(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No bulletins yet.', style: TextStyle(color: Colors.grey)));
        }
        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(syncServiceProvider).pull();
            ref.invalidate(pendingOutboxCountProvider);
          },
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final b = items[i];
              return ListTile(
                title: Text(b.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(b.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusBadge(kind: b.kind, verified: b.isVerified),
                    const SizedBox(height: 4),
                    Text(b.moderatorName ?? '—', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                onTap: () => context.push('/detail/bulletin/${b.id}'),
              );
            },
          ),
        );
      },
    );
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(requestRepoProvider);
    return FutureBuilder<List<HelpRequest>>(
      future: repo.list(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final items = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No requests yet.', style: TextStyle(color: Colors.grey)));
        }
        return RefreshIndicator(
          onRefresh: () async {
            await ref.read(syncServiceProvider).pull();
          },
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 0),
            itemBuilder: (_, i) {
              final r = items[i];
              return ListTile(
                title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(r.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: StatusBadge(kind: r.kind),
                onTap: () => context.push('/detail/request/${r.id}'),
              );
            },
          ),
        );
      },
    );
  }
}