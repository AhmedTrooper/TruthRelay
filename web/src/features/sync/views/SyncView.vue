<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount, computed, watch } from 'vue';
import {
  NButton,
  NSpace,
  NAlert,
  NInput,
  NTag,
  NSwitch,
  NEmpty,
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
const peerOutboxJson = ref('');
const forwardingBusy = ref(false);
const lastForwardResult = ref<string | null>(null);
const lastForwardError = ref<string | null>(null);
const lastForwardPayload = ref<any | null>(null);

const AUDIT_KEY = 'truthrelay.mesh-forward.audit';
const AUDIT_LIMIT = 20;

interface ForwardAuditEntry {
  ts: string;
  bulletins: number;
  requests: number;
  accepted: number;
  duplicates: number;
  rejected: number;
  ok: boolean;
}

function loadAudit(): ForwardAuditEntry[] {
  try {
    const raw = localStorage.getItem(AUDIT_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

const audit = ref<ForwardAuditEntry[]>(loadAudit());

function recordAudit(entry: ForwardAuditEntry) {
  // Newest first; cap at AUDIT_LIMIT.
  const next = [entry, ...audit.value].slice(0, AUDIT_LIMIT);
  audit.value = next;
  try {
    localStorage.setItem(AUDIT_KEY, JSON.stringify(next));
  } catch {
    /* localStorage may be unavailable (Safari private mode); fall through. */
  }
}

function clearAudit() {
  audit.value = [];
  try {
    localStorage.removeItem(AUDIT_KEY);
  } catch {
    /* ignore */
  }
}

watch(audit, (val) => {
  // Persist on every change — localStorage write is cheap and keeps the
  // audit log live across reloads.
  try {
    localStorage.setItem(AUDIT_KEY, JSON.stringify(val));
  } catch {
    /* ignore */
  }
});

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

async function forwardPeerOutbox() {
  forwardingBusy.value = true;
  lastForwardError.value = null;
  lastForwardResult.value = null;
  let parsed: any[];
  try {
    parsed = JSON.parse(peerOutboxJson.value || '[]');
    if (!Array.isArray(parsed)) {
      throw new Error('payload must be a JSON array');
    }
  } catch (e: any) {
    lastForwardError.value = e?.message ?? String(e);
    message.error(lastForwardError.value ?? 'unknown error');
    forwardingBusy.value = false;
    return;
  }
  const bulletins_ = parsed.filter((x) => x?.kind === 'bulletin');
  const requests_ = parsed.filter((x) => x?.kind === 'request');
  try {
    const res = await api.post('/api/v1/mesh/forward', {
      forwarder_peer_id: 'web-admin',
      bulletins: bulletins_,
      requests: requests_,
    });
    const data = res.data as {
      accepted: number;
      duplicates: number;
      rejected: number;
    };
    lastForwardPayload.value = data;
    lastForwardResult.value = `Forwarded ${bulletins_.length} bulletins, ${requests_.length} requests — accepted=${data.accepted}, duplicates=${data.duplicates}, rejected=${data.rejected}.`;
    message.success('Forwarded to relay');
    recordAudit({
      ts: new Date().toISOString(),
      bulletins: bulletins_.length,
      requests: requests_.length,
      accepted: data.accepted,
      duplicates: data.duplicates,
      rejected: data.rejected,
      ok: true,
    });
    await Promise.all([bulletins.refresh(), requests.refresh()]);
  } catch (e: any) {
    lastForwardError.value = e?.message ?? String(e);
    message.error(lastForwardError.value ?? 'unknown error');
    recordAudit({
      ts: new Date().toISOString(),
      bulletins: bulletins_.length,
      requests: requests_.length,
      accepted: 0,
      duplicates: 0,
      rejected: bulletins_.length + requests_.length,
      ok: false,
    });
  } finally {
    forwardingBusy.value = false;
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
  <div class="space-y-6 max-w-4xl mx-auto">
    <header 
      v-motion
      :initial="{ opacity: 0, y: -20 }"
      :enter="{ opacity: 1, y: 0, transition: { duration: 500, ease: 'easeOut' } }"
      class="flex flex-col gap-1"
    >
      <h1 class="text-3xl font-bold m-0 text-slate-900 dark:text-white tracking-tight">
        Sync Control
      </h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 m-0 font-medium">
        Pull bulletins and requests from the relay since a given timestamp.
      </p>
    </header>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 100, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Relay Health</h2>
      <NSpace vertical size="large">
        <div class="flex items-center gap-3 flex-wrap">
          <NButton :loading="probeBusy" @click="probeRelay">Probe Relay</NButton>
          <NTag v-if="probe?.ok" type="success" round class="!font-semibold">
            online · {{ probe.latencyMs }} ms
          </NTag>
          <NTag v-else-if="probe && !probe.ok" type="error" round class="!font-semibold">
            unreachable · {{ probe.error }}
          </NTag>
          <NTag v-else round>probing…</NTag>
          <NSpace align="center" class="ml-auto">
            <span class="text-xs font-semibold text-slate-500 dark:text-slate-400 uppercase tracking-wider">Auto-refresh (60s)</span>
            <NSwitch :value="autoRefresh" @update:value="toggleAutoRefresh" />
          </NSpace>
        </div>
      </NSpace>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 200, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Pull From Server</h2>
      <NSpace vertical size="large">
        <NInput v-model:value="since" placeholder="RFC3339 timestamp" class="!rounded-xl" />
        <p class="text-xs text-slate-500 dark:text-slate-400 m-0 font-medium">
          Since <code class="bg-slate-100 dark:bg-slate-900 px-2 py-0.5 rounded font-mono">{{ formattedSince }}</code>
        </p>
        <NSpace>
          <NButton type="primary" :loading="busy" @click="pull">
            Pull Since…
          </NButton>
        </NSpace>
        <NAlert
          v-if="lastResult"
          type="success"
          :title="lastResult"
          :show-icon="true"
          class="!rounded-xl"
        >
          Server reported time: <code>{{ formattedServerTime }}</code>
        </NAlert>
        <NAlert v-if="lastError" type="error" :title="lastError" class="!rounded-xl" />
        <details v-if="lastPayload" class="text-xs">
          <summary class="cursor-pointer text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 font-semibold">
            Show raw response
          </summary>
          <pre class="mt-2 max-h-80 overflow-auto rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-950/70 p-3 font-mono text-[11px]">{{ JSON.stringify(lastPayload, null, 2) }}</pre>
        </details>
      </NSpace>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 300, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Peer Outbox Forwarding</h2>
      <NSpace vertical size="large">
        <p class="text-sm text-slate-600 dark:text-slate-300 m-0 leading-relaxed">
          When a peer (offline phone) hands us its queued messages, forward them through this
          dashboard to the relay. The server re-verifies every signature and deduplicates by
          <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded font-mono text-xs">sha256</code> and request <code class="bg-slate-100 dark:bg-slate-900 px-1.5 py-0.5 rounded font-mono text-xs">id</code>, so partial success is expected.
        </p>
        <NInput
          v-model:value="peerOutboxJson"
          type="textarea"
          placeholder='[{"kind":"bulletin","sha256":"…","title":"…","body":"…"}]'
          :rows="5"
          class="!rounded-xl font-mono text-xs"
        />
        <NSpace align="center" class="pt-1">
          <NTag :type="peerOutboxForwarding ? 'success' : 'default'" round class="!font-bold uppercase tracking-wider text-[10px]">
            {{ peerOutboxForwarding ? 'armed' : 'idle' }}
          </NTag>
          <NButton
            size="small"
            @click="peerOutboxForwarding = !peerOutboxForwarding"
          >
            {{ peerOutboxForwarding ? 'Disable' : 'Enable' }} Forwarding
          </NButton>
          <NButton
            type="primary"
            size="small"
            :loading="forwardingBusy"
            :disabled="!peerOutboxForwarding"
            @click="forwardPeerOutbox"
          >
            Forward to Relay
          </NButton>
        </NSpace>
        <NAlert
          v-if="lastForwardResult"
          type="success"
          :title="lastForwardResult"
          :show-icon="true"
          class="!rounded-xl"
        />
        <NAlert
          v-if="lastForwardError"
          type="error"
          :title="lastForwardError"
          class="!rounded-xl"
        />
        <details v-if="lastForwardPayload" class="text-xs">
          <summary class="cursor-pointer text-slate-500 hover:text-slate-900 dark:text-slate-400 dark:hover:text-slate-100 font-semibold">
            Show raw response
          </summary>
          <pre class="mt-2 max-h-80 overflow-auto rounded-xl border border-slate-200 dark:border-slate-800 bg-slate-50 dark:bg-slate-950/70 p-3 font-mono text-[11px]">{{ JSON.stringify(lastForwardPayload, null, 2) }}</pre>
        </details>
      </NSpace>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 400, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Forward Audit Log</h2>
        <NButton v-if="audit.length" size="tiny" tertiary @click="clearAudit">
          Clear Log
        </NButton>
      </div>
      <NSpace vertical size="large">
        <p class="text-xs text-slate-500 dark:text-slate-400 m-0">
          Last {{ AUDIT_LIMIT }} forward attempts made through this browser. Stored
          locally — never sent to the relay.
        </p>
        <div v-if="!audit.length" class="py-4">
          <NEmpty size="small" description="No forwards yet from this device" />
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-xs">
            <thead>
              <tr class="text-left text-slate-400 dark:text-slate-500 border-b border-slate-200 dark:border-slate-800 font-semibold uppercase tracking-wider text-[10px]">
                <th class="py-2 pr-3">When</th>
                <th class="py-2 pr-3">Items</th>
                <th class="py-2 pr-3">Accepted</th>
                <th class="py-2 pr-3">Duplicates</th>
                <th class="py-2 pr-3">Rejected</th>
                <th class="py-2 pr-3">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100 dark:divide-slate-900">
              <tr
                v-for="(row, i) in audit"
                :key="i"
                class="hover:bg-slate-50 dark:hover:bg-slate-900/40 transition-colors"
              >
                <td class="py-2.5 pr-3 text-slate-600 dark:text-slate-300 tabular-nums font-mono">
                  {{ dayjs(row.ts).format('MMM D HH:mm:ss') }}
                </td>
                <td class="py-2.5 pr-3 tabular-nums font-medium">
                  {{ row.bulletins + row.requests }}
                  <span class="text-slate-400 text-[10px]">({{ row.bulletins }}b + {{ row.requests }}r)</span>
                </td>
                <td class="py-2.5 pr-3 text-emerald-600 dark:text-emerald-400 font-semibold tabular-nums">{{ row.accepted }}</td>
                <td class="py-2.5 pr-3 text-slate-500 dark:text-slate-400 tabular-nums">{{ row.duplicates }}</td>
                <td class="py-2.5 pr-3 text-rose-600 dark:text-rose-400 font-semibold tabular-nums">{{ row.rejected }}</td>
                <td class="py-2.5 pr-3">
                  <NTag :type="row.ok ? 'success' : 'error'" size="small" round class="!font-bold uppercase tracking-wider text-[10px]">
                    {{ row.ok ? 'ok' : 'failed' }}
                  </NTag>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </NSpace>
    </div>
  </div>
</template>