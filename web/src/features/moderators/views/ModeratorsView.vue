<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import {
  NCard,
  NInput,
  NButton,
  NSpace,
  NAlert,
  NTag,
  useMessage,
} from 'naive-ui';
import { useModeratorStore } from '../store';

const moderator = useModeratorStore();
const message = useMessage();

const pasted = ref('');
const parsed = ref<any | null>(null);
const parseError = ref<string | null>(null);

function tryParse() {
  parseError.value = null;
  parsed.value = null;
  try {
    const obj = JSON.parse(pasted.value);
    if (!obj.public_key_b64 || !obj.secret_key_b64 || !obj.name) {
      throw new Error('JSON must include name, public_key_b64, secret_key_b64');
    }
    parsed.value = obj;
  } catch (e: any) {
    parseError.value = e?.message ?? String(e);
  }
}

async function save() {
  moderator.setFromKeygen(parsed.value);
  message.success('Saved locally. Registering with server…');
  try {
    await moderator.register();
    message.success('Registered on server');
  } catch (e: any) {
    message.warning('Saved locally but server registration failed: ' + (e?.message ?? e));
  }
}

const registered = computed(() => !!moderator.stored?.id);
const shortKey = computed(() =>
  moderator.stored?.public_key_b64
    ? `${moderator.stored.public_key_b64.slice(0, 16)}…`
    : '',
);

onMounted(async () => {
  await moderator.refresh();
});
</script>

<template>
  <div class="space-y-6 max-w-3xl animate-fade-in">
    <header>
      <h1 class="text-2xl font-semibold m-0 text-slate-900 dark:text-slate-50">
        Moderators
      </h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1">
        Mint a keypair on the relay, import it here, then sign bulletins with it.
      </p>
    </header>

    <NAlert v-if="!moderator.stored" type="info" title="No keypair loaded">
      Run <code class="text-xs">cargo run -- keygen --name your-name</code> in the <code>api/</code> folder,
      then paste the JSON output below.
    </NAlert>

    <NCard v-if="moderator.stored" title="Current keypair">
      <NSpace vertical>
        <div class="flex items-center gap-2">
          <span class="text-slate-500 dark:text-slate-400 text-sm">Name:</span>
          <NTag round>{{ moderator.stored.name }}</NTag>
          <NTag v-if="registered" type="success" size="small">Registered on server</NTag>
          <NTag v-else type="warning" size="small">Local only</NTag>
        </div>
        <div>
          <span class="text-slate-500 dark:text-slate-400 text-sm">Moderator ID:</span>
          <code class="text-xs ml-1">{{ moderator.stored.id || '(pending)' }}</code>
        </div>
        <div>
          <span class="text-slate-500 dark:text-slate-400 text-sm">Public key:</span>
          <code class="text-xs ml-1 break-all">{{ moderator.stored.public_key_b64 }}</code>
        </div>
        <div class="text-xs text-slate-500 dark:text-slate-400">
          Fingerprint: <code class="font-mono">{{ shortKey }}</code>
        </div>
        <NSpace>
          <NButton v-if="!registered" type="primary" :loading="moderator.busy" @click="moderator.register()">
            Register on server
          </NButton>
          <NButton @click="moderator.clear()">Clear</NButton>
        </NSpace>
      </NSpace>
    </NCard>

    <NCard title="Import keygen JSON">
      <NSpace vertical>
        <NInput
          v-model:value="pasted"
          type="textarea"
          :rows="6"
          placeholder='{"name":"...","public_key_b64":"...","secret_key_b64":"...","created_at":"..."}'
        />
        <NSpace>
          <NButton @click="tryParse">Parse</NButton>
          <NButton v-if="parsed" type="primary" @click="save">Save & register</NButton>
        </NSpace>
        <NAlert v-if="parseError" type="error" :title="parseError" />
        <div v-if="parsed" class="text-xs text-slate-500 dark:text-slate-400 space-y-1">
          <div>Name: <span class="text-slate-700 dark:text-slate-200">{{ parsed.name }}</span></div>
          <div class="break-all">Public key: <code>{{ parsed.public_key_b64 }}</code></div>
        </div>
      </NSpace>
    </NCard>
  </div>
</template>