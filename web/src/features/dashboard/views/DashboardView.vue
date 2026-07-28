<script setup lang="ts">
import { onMounted, onBeforeUnmount, computed } from 'vue';
import { storeToRefs } from 'pinia';
import { NEmpty, NSkeleton } from 'naive-ui';
import { useDashboardStore } from '../store';
import { useBulletinsStore } from '../../bulletins/store';
import { useRequestsStore } from '../../requests/store';
import StatCard from '../../../components/StatCard.vue';
import SectorDonut from '../../../components/SectorDonut.vue';
import StatusBadge from '../../../components/StatusBadge.vue';
import CanonicalPreview from '../../../components/CanonicalPreview.vue';

const dashboard = useDashboardStore();
const bulletins = useBulletinsStore();
const requests = useRequestsStore();

const { stats, loading, error } = storeToRefs(dashboard);
const { items: bulletinItems } = storeToRefs(bulletins);
const { items: requestItems } = storeToRefs(requests);

let refreshTimer: number | null = null;

onMounted(async () => {
  await refresh();
  refreshTimer = window.setInterval(refresh, 30_000);
});
onBeforeUnmount(() => {
  if (refreshTimer !== null) window.clearInterval(refreshTimer);
});

async function refresh() {
  await Promise.all([
    dashboard.refresh(),
    bulletins.refresh(),
    requests.refresh(),
  ]);
}

const recentBulletins = computed(() => bulletinItems.value.slice(0, 4));
const recentRequests = computed(() => requestItems.value.slice(0, 4));

const bulletinMix = computed(() => {
  const counts: Record<string, number> = {};
  for (const b of bulletinItems.value) {
    counts[b.kind] = (counts[b.kind] ?? 0) + 1;
  }
  return [
    { label: 'VerifiedUpdate', value: counts['VerifiedUpdate'] ?? 0, color: '' },
    { label: 'Debunk', value: counts['Debunk'] ?? 0, color: '' },
    { label: 'Blood', value: counts['Blood'] ?? 0, color: '' },
    { label: 'Missing', value: counts['Missing'] ?? 0, color: '' },
    { label: 'Supply', value: counts['Supply'] ?? 0, color: '' },
  ];
});

const featuredBulletin = computed(() => bulletinItems.value[0] ?? null);
const featuredPayload = computed(() =>
  featuredBulletin.value
    ? {
        kind: featuredBulletin.value.kind,
        title: featuredBulletin.value.title,
        body: featuredBulletin.value.body,
        created_at: featuredBulletin.value.created_at,
      }
    : null,
);

const bulletinsDelta = computed(() => {
  if (!stats.value || bulletinItems.value.length < 2) return null;
  // Heuristic: how recently did the freshest bulletin arrive? For a tiny
  // demo dataset this reads as a "freshness" hint.
  const newest = bulletinItems.value[0];
  const ageMs = newest
    ? Date.now() - new Date(newest.received_at).getTime()
    : Number.POSITIVE_INFINITY;
  if (ageMs < 60 * 60 * 1000) return 1;
  if (ageMs < 24 * 60 * 60 * 1000) return 0;
  return -1;
});
</script>

<template>
  <div class="space-y-8 animate-fade-in">
    <header class="flex items-end justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold m-0 text-slate-900 dark:text-slate-50">
          Mission control
        </h1>
        <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1">
          A 30-second read on what your relay is currently broadcasting.
        </p>
      </div>
      <button
        type="button"
        class="text-xs text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100"
        @click="refresh"
      >
        ↻ Refresh
      </button>
    </header>

    <div v-if="loading && !stats" class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      <NSkeleton v-for="i in 4" :key="i" height="96" rounded />
    </div>
    <div v-else-if="error" class="rounded-lg border border-rose-300 dark:border-rose-500/40 bg-rose-50 dark:bg-rose-500/10 p-4 text-rose-700 dark:text-rose-200">
      Could not reach relay: {{ error }}
    </div>

    <template v-else>
      <section class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          label="Verified bulletins"
          :value="stats?.bulletins ?? 0"
          accent="emerald"
          :delta="bulletinsDelta"
          hint="signed by registered moderators"
        />
        <StatCard
          label="Help requests"
          :value="stats?.requests ?? 0"
          accent="amber"
          hint="queued for moderator review"
        />
        <StatCard
          label="Moderators"
          :value="stats?.moderators ?? 0"
          accent="sky"
          hint="registered keypairs"
        />
        <StatCard
          label="Mesh peers (24h)"
          :value="bulletinItems.length + requestItems.length"
          accent="violet"
          hint="combined local cache"
        />
      </section>

      <section class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="card-soft p-5 lg:col-span-1">
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold m-0 text-slate-900 dark:text-slate-100">
              Bulletin mix
            </h2>
            <span class="text-xs text-slate-500">all kinds</span>
          </div>
          <SectorDonut :slices="bulletinMix" />
        </div>

        <div class="card-soft p-5 lg:col-span-2">
          <div class="flex items-center justify-between mb-3 gap-2">
            <h2 class="font-semibold m-0 text-slate-900 dark:text-slate-100">
              Latest signed bulletin
            </h2>
            <StatusBadge v-if="featuredBulletin" :kind="featuredBulletin.kind" :verified="true" />
          </div>
          <template v-if="featuredBulletin && featuredPayload">
            <p class="text-sm text-slate-700 dark:text-slate-300 m-0 mb-2">
              <strong>{{ featuredBulletin.title }}</strong> — {{ featuredBulletin.body }}
            </p>
            <CanonicalPreview
              :payload="featuredPayload"
              :signature="featuredBulletin.signature_b64"
              :sha256="featuredBulletin.sha256"
            />
          </template>
          <NEmpty v-else description="No bulletins signed yet" size="small" />
        </div>
      </section>

      <section class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="card-soft p-5">
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold m-0 text-slate-900 dark:text-slate-100">
              Recent bulletins
            </h2>
            <router-link
              to="/bulletins"
              class="text-xs text-emerald-600 dark:text-emerald-300 hover:underline"
            >
              See all →
            </router-link>
          </div>
          <ul class="divide-y divide-slate-200 dark:divide-slate-800">
            <li
              v-for="b in recentBulletins"
              :key="b.id"
              class="py-2 flex items-start gap-3"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-400 mt-2 shrink-0"></span>
              <div class="flex-1 min-w-0">
                <p class="font-medium m-0 truncate text-slate-900 dark:text-slate-100">
                  {{ b.title }}
                </p>
                <p class="text-xs text-slate-500 dark:text-slate-400 m-0">
                  {{ b.moderator_name ?? b.moderator_id.slice(0, 8) }} · {{ b.received_at }}
                </p>
              </div>
              <StatusBadge :kind="b.kind" />
            </li>
            <li v-if="!recentBulletins.length" class="py-3 text-sm text-slate-500">
              No bulletins yet. Sign one from <router-link to="/bulletins" class="text-emerald-600 dark:text-emerald-300 hover:underline">Bulletins</router-link>.
            </li>
          </ul>
        </div>

        <div class="card-soft p-5">
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold m-0 text-slate-900 dark:text-slate-100">
              Recent help requests
            </h2>
            <router-link
              to="/requests"
              class="text-xs text-emerald-600 dark:text-emerald-300 hover:underline"
            >
              See all →
            </router-link>
          </div>
          <ul class="divide-y divide-slate-200 dark:divide-slate-800">
            <li
              v-for="r in recentRequests"
              :key="r.id"
              class="py-2 flex items-start gap-3"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-amber-400 mt-2 shrink-0"></span>
              <div class="flex-1 min-w-0">
                <p class="font-medium m-0 truncate text-slate-900 dark:text-slate-100">
                  {{ r.title }}
                </p>
                <p class="text-xs text-slate-500 dark:text-slate-400 m-0">
                  {{ r.location ?? '—' }} · {{ r.received_at }}
                </p>
              </div>
              <StatusBadge :kind="r.kind" />
            </li>
            <li v-if="!recentRequests.length" class="py-3 text-sm text-slate-500">
              No help requests queued.
            </li>
          </ul>
        </div>
      </section>
    </template>
  </div>
</template>