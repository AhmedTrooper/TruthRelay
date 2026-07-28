<script setup lang="ts">
import { ref } from 'vue';
import { NCard, NButton, NSpace, NAlert, NInput, useMessage } from 'naive-ui';
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

async function pull() {
  busy.value = true;
  lastError.value = null;
  lastResult.value = null;
  try {
    const res = await pullSync(since.value || '1970-01-01T00:00:00Z');
    lastResult.value = `Pulled ${res.bulletins.length} bulletins, ${res.requests.length} requests. Server time: ${res.server_time}`;
    message.success('Sync complete');
    await Promise.all([bulletins.refresh(), requests.refresh()]);
  } catch (e: any) {
    lastError.value = e?.message ?? String(e);
    message.error(lastError.value ?? 'unknown error');
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <div class="space-y-6 max-w-2xl">
    <h1 class="text-2xl font-semibold">Sync</h1>

    <NCard title="Pull from server">
      <NSpace vertical>
        <NInput v-model:value="since" placeholder="RFC3339 timestamp" />
        <NSpace>
          <NButton type="primary" :loading="busy" @click="pull">Pull since…</NButton>
        </NSpace>
        <NAlert v-if="lastResult" type="success" :title="lastResult" />
        <NAlert v-if="lastError" type="error" :title="lastError" />
      </NSpace>
    </NCard>
  </div>
</template>