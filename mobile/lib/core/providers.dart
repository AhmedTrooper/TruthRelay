import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/bulletins/data/bulletin_repository.dart';
import '../features/requests/data/request_repository.dart';
import '../features/settings/data/moderator_settings_repository.dart';
import '../features/sync/data/api_client.dart';
import '../features/sync/data/outbox_repository.dart';
import '../features/sync/data/sync_service.dart';

final bulletinRepoProvider = Provider<BulletinRepository>((_) => BulletinRepository());
final requestRepoProvider = Provider<RequestRepository>((_) => RequestRepository());
final outboxRepoProvider = Provider<OutboxRepository>((_) => OutboxRepository());
final moderatorSettingsRepoProvider = Provider<ModeratorSettingsRepository>((_) => ModeratorSettingsRepository());

final apiClientProvider = Provider<ApiClient>((_) => ApiClient());

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(
      api: ref.watch(apiClientProvider),
      bulletins: ref.watch(bulletinRepoProvider),
      requests: ref.watch(requestRepoProvider),
      outbox: ref.watch(outboxRepoProvider),
    ));

final pendingOutboxCountProvider = FutureProvider.autoDispose<int>((ref) async {
  return ref.watch(outboxRepoProvider).countPending();
});