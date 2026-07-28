<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed } from 'vue';
import {
  NCard,
  NButton,
  NSpace,
  NAlert,
  NInput,
  NTag,
  NSwitch,
  useMessage,
} from 'naive-ui';
import dayjs from 'dayjs';
import { api } from '../../../lib/api/client';
import { pullSync } from '../../../lib/api/endpoints';
import { useBulletinsStore } from '../../bulletins/store';
import { useRequestsStore } from '../../requests/store';

const message = useMessage();
const bulletins = useBulletinsStore();
const requests = useRequestsStore();

const since = ref('1970-01-01T00:00:00Z');
const busy = ref(false);
const lastResult = ref<string | null>(null);
const lastError = ref<string | null>(null);
const lastPayload = ref<any | null>(null);

const probeBusy = ref(false);
const probe = ref<{ ok: boolean; latencyMs: number | null; error?: string } | null>(null);

const autoRefresh = ref(false);
let autoTimer: number | null = null;

const peerOutboxForwarding = ref(false);

async function pull() {
  busy.value = true;
  lastError.value = null;
  lastResult.value = null;
  try {
    const res = await pullSync(since.value || '1970-01-01T00:00:00Z');
    lastPayload.value = res;
    lastResult.value = `Pulled ${res.bulletins.length} bulletins, ${res.requests.length} requests.`;
    message.success('Sync complete');
    await Promise.all([bulletins.refresh(), requests.refresh()]);
  } catch (e: any) {
    lastError.value = e?.message ?? String(e);
    message.error(lastError.value ?? 'unknown error');
  } finally {
    busy.value = false;
  }
}

async function probeRelay() {
  probeBusy.value = true;
  probe.value = null;
  const started = performance.now();
  try {
    await api.get('/api/v1/stats');
    probe.value = { ok: true, latencyMs: Math.round(performance.now() - started) };
  } catch (e: any) {
    probe.value = {
      ok: false,
      latencyMs: Math.round(performance.now() - started),
      error: e?.message ?? String(e),
    };
  } finally {
    probeBusy.value = false;
  }
}

async function toggleAutoRefresh(v: boolean) {
  autoRefresh.value = v;
  if (v) {
    await pull();
    autoTimer = window.setInterval(pull, 60_000);
  } else if (autoTimer !== null) {
    window.clearInterval(autoTimer);
    autoTimer = null;
  }
}

onMounted(() => probeRelay());
onBeforeUnmount(() => {
  if (autoTimer !== null) window.clearInterval(autoTimer);
});

const formattedSince = computed(() =>
  since.value ? dayjs(since.value).format('YYYY-MM-DD HH:mm:ss [UTC]') : '—',
);

const formattedServerTime = computed(() => {
  if (!lastPayload.value?.server_time) return '—';
  return dayjs(lastPayload.value.server_time).format('YYYY-MM-DD HH:mm:ss [UTC]');
});
</script>

<template>
  <div class="space-y-6 max-w-3xl animate-fade-in">
    <header>
      <h1 class="text-2xl font-semibold m-0 text-slate-900 dark:text-slate-50">
        Sync
      </h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1">
        Pull bulletins and requests from the relay since a given timestamp.
      </p>
    </header>

    <NCard title="Relay health">
      <NSpace vertical>
        <div class="flex items-center gap-3 flex-wrap">
          <NButton :loading="probeBusy" @click="probeRelay">Probe relay</NButton>
          <NTag v-if="probe?.ok" type="success" round>
            online · {{ probe.latencyMs }} ms
          </NTag>
          <NTag v-else-if="probe && !probe.ok" type="error" round>
            unreachable · {{ probe.error }}
          </NTag>
          <NTag v-else>probing…</NTag>
          <NSpace align="center" class="ml-auto">
            <span class="text-xs text-slate-500 dark:text-slate-400">Auto-refresh every 60s</span>
            <NSwitch :value="autoRefresh" @update:value="toggleAutoRefresh" />
          </NSpace>
        </div>
      </NSpace>
    </NCard>

    <NCard title="Pull from server">
      <NSpace vertical>
        <NInput v-model:value="since" placeholder="RFC3339 timestamp" />
        <p class="text-xs text-slate-500 dark:text-slate-400 m-0">
          Since <code>{{ formattedSince }}</code>
        </p>
        <NSpace>
          <NButton type="primary" :loading="busy" @click="pull">
            Pull since…
          </NButton>
        </NSpace>
        <NAlert
          v-if="lastResult"
          type="success"
          :title="lastResult"
          :show-icon="true"
        >
          Server reported time: <code>{{ formattedServerTime }}</code>
        </NAlert>
        <NAlert v-if="lastError" type="error" :title="lastError" />
        <details v-if="lastPayload" class="text-xs">
          <summary class="cursor-pointer text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100">
            Show raw response
          </summary>
          <pre class="mt-2 max-h-80 overflow-auto rounded-lg border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-950/70 p-3 font-mono text-[11px]">{{ JSON.stringify(lastPayload, null, 2) }}</pre>
        </details>
      </NSpace>
    </NCard>

    <NCard title="Peer outbox forwarding (coming soon)">
      <NSpace vertical>
        <p class="text-sm text-slate-600 dark:text-slate-300 m-0">
          When a peer (offline phone) hands us its queued messages, this dashboard will let you
          forward them to the relay. The endpoint is part of the mesh-sync work in progress.
        </p>
        <NSpace align="center">
          <NTag :type="peerOutboxForwarding ? 'success' : 'default'" round>
            {{ peerOutboxForwarding ? 'armed' : 'idle' }}
          </NTag>
          <NButton size="small" @click="peerOutboxForwarding = !peerOutboxForwarding">
            {{ peerOutboxForwarding ? 'Disable' : 'Enable' }} forwarding
          </NButton>
        </NSpace>
      </NSpace>
    </NCard>
  </div>
</template>