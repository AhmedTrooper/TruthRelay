<script setup lang="ts">
import { onMounted, computed } from 'vue';
import { storeToRefs } from 'pinia';
import { useDashboardStore } from '../store';
import { useBulletinsStore } from '../../bulletins/store';
import { useRequestsStore } from '../../requests/store';
import StatusBadge from '../../../components/StatusBadge.vue';

const dashboard = useDashboardStore();
const bulletins = useBulletinsStore();
const requests = useRequestsStore();

const { stats, loading, error } = storeToRefs(dashboard);

onMounted(async () => {
  await Promise.all([dashboard.refresh(), bulletins.refresh(), requests.refresh()]);
});

const recentBulletins = computed(() => bulletins.items.slice(0, 5));
const recentRequests = computed(() => requests.items.slice(0, 5));
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-semibold">Dashboard</h1>

    <div v-if="loading" class="text-slate-400">Loading…</div>
    <div v-else-if="error" class="text-rose-400">{{ error }}</div>

    <div v-else class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <div class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <div class="text-sm text-slate-400">Bulletins</div>
        <div class="text-3xl font-bold mt-1">{{ stats?.bulletins ?? 0 }}</div>
      </div>
      <div class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <div class="text-sm text-slate-400">Help Requests</div>
        <div class="text-3xl font-bold mt-1">{{ stats?.requests ?? 0 }}</div>
      </div>
      <div class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <div class="text-sm text-slate-400">Moderators</div>
        <div class="text-3xl font-bold mt-1">{{ stats?.moderators ?? 0 }}</div>
      </div>
    </div>

    <section class="grid grid-cols-1 lg:grid-cols-2 gap-4">
      <div class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <h2 class="font-semibold mb-3">Recent bulletins</h2>
        <ul class="space-y-2">
          <li
            v-for="b in recentBulletins"
            :key="b.id"
            class="border border-slate-800 rounded p-3"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium">{{ b.title }}</span>
              <StatusBadge :kind="b.kind" />
            </div>
            <div class="text-xs text-slate-400 mt-1">
              {{ b.moderator_name ?? b.moderator_id }} · {{ b.received_at }}
            </div>
          </li>
          <li v-if="!recentBulletins.length" class="text-slate-500 text-sm">No bulletins yet.</li>
        </ul>
      </div>

      <div class="rounded-lg border border-slate-800 bg-slate-900/40 p-4">
        <h2 class="font-semibold mb-3">Recent requests</h2>
        <ul class="space-y-2">
          <li
            v-for="r in recentRequests"
            :key="r.id"
            class="border border-slate-800 rounded p-3"
          >
            <div class="flex items-center justify-between">
              <span class="font-medium">{{ r.title }}</span>
              <StatusBadge :kind="r.kind" />
            </div>
            <div class="text-xs text-slate-400 mt-1">
              {{ r.location ?? '—' }} · {{ r.received_at }}
            </div>
          </li>
          <li v-if="!recentRequests.length" class="text-slate-500 text-sm">No requests yet.</li>
        </ul>
      </div>
    </section>
  </div>
</template>