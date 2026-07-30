<script setup lang="ts">
import { ref, computed, onMounted } from 'vue';
import {
  NInput,
  NButton,
  NSpace,
  NAlert,
  NTag,
  useMessage,
} from 'naive-ui';
import { getAdminToken } from '../../../lib/api/client';
import { useModeratorStore } from '../store';

const moderator = useModeratorStore();
const message = useMessage();

const pasted = ref('');
const parsed = ref<any | null>(null);
const parseError = ref<string | null>(null);
const adminToken = ref(getAdminToken());

function updateAdminToken() {
  localStorage.setItem('truthrelay.admin_token', adminToken.value.trim());
  message.success('Admin token saved');
}

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
  <div class="space-y-6 max-w-4xl mx-auto">
    <header 
      v-motion
      :initial="{ opacity: 0, y: -20 }"
      :enter="{ opacity: 1, y: 0, transition: { duration: 500, ease: 'easeOut' } }"
      class="flex flex-col gap-1"
    >
      <h1 class="text-3xl font-bold m-0 text-slate-900 dark:text-white tracking-tight">
        Moderator Keys
      </h1>
      <p class="text-sm text-slate-500 dark:text-slate-400 m-0 font-medium">
        Mint a keypair on the relay, import it here, then sign bulletins with it.
      </p>
    </header>

    <NAlert v-if="!moderator.stored" type="info" title="No keypair loaded" class="!rounded-xl">
      Run <code class="text-xs bg-slate-200 dark:bg-slate-800 px-2 py-0.5 rounded">cargo run -- keygen --name your-name</code> in the <code>api/</code> folder,
      then paste the JSON output below.
    </NAlert>

    <div 
      v-if="moderator.stored" 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 150, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Current Keypair</h2>
      <NSpace vertical size="large">
        <div class="flex items-center gap-3 flex-wrap">
          <span class="text-slate-500 dark:text-slate-400 text-sm font-medium">Name:</span>
          <NTag round class="!font-semibold">{{ moderator.stored.name }}</NTag>
          <NTag v-if="registered" type="success" size="small" round>Registered on server</NTag>
          <NTag v-else type="warning" size="small" round>Local only</NTag>
        </div>
        <div>
          <span class="text-slate-500 dark:text-slate-400 text-sm font-medium">Moderator ID:</span>
          <code class="text-xs ml-2 bg-slate-100 dark:bg-slate-900 px-2 py-1 rounded-md font-mono">{{ moderator.stored.id || '(pending)' }}</code>
        </div>
        <div>
          <span class="text-slate-500 dark:text-slate-400 text-sm font-medium">Public Key:</span>
          <code class="text-xs ml-2 break-all bg-slate-100 dark:bg-slate-900 px-2 py-1 rounded-md font-mono text-emerald-600 dark:text-emerald-400">{{ moderator.stored.public_key_b64 }}</code>
        </div>
        <div class="text-xs text-slate-500 dark:text-slate-400 font-medium">
          Fingerprint: <code class="font-mono bg-slate-100 dark:bg-slate-900 px-2 py-1 rounded-md">{{ shortKey }}</code>
        </div>
        <NSpace class="pt-2">
          <NButton v-if="!registered" type="primary" :loading="moderator.busy" @click="moderator.register()">
            Register on server
          </NButton>
          <NButton @click="moderator.clear()">Clear Keypair</NButton>
        </NSpace>
      </NSpace>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 250, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Import Keygen JSON</h2>
      <NSpace vertical size="large">
        <NInput
          v-model:value="pasted"
          type="textarea"
          :rows="5"
          placeholder='{"name":"...","public_key_b64":"...","secret_key_b64":"...","created_at":"..."}'
          class="!rounded-xl"
        />
        <NSpace>
          <NButton @click="tryParse">Parse JSON</NButton>
          <NButton v-if="parsed" type="primary" @click="save">Save & Register</NButton>
        </NSpace>
        <NAlert v-if="parseError" type="error" :title="parseError" class="!rounded-xl" />
        <div v-if="parsed" class="text-xs text-slate-500 dark:text-slate-400 space-y-2 bg-slate-100 dark:bg-slate-900 p-3 rounded-xl">
          <div>Name: <span class="text-slate-900 dark:text-slate-100 font-semibold">{{ parsed.name }}</span></div>
          <div class="break-all font-mono">Public key: <code class="text-emerald-500">{{ parsed.public_key_b64 }}</code></div>
        </div>
      </NSpace>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 350, duration: 500, ease: 'easeOut' } }"
      class="surface-tile space-y-4"
    >
      <h2 class="text-lg font-bold text-slate-900 dark:text-white m-0">Relay Admin Token</h2>
      <p class="text-xs text-slate-500 dark:text-slate-400 m-0">
        Used for <code>POST /api/v1/moderators</code> authorization. Default: <code>dev-token-change-me</code>.
      </p>
      <div class="flex items-center gap-3">
        <NInput
          v-model:value="adminToken"
          type="password"
          show-password-on="click"
          placeholder="dev-token-change-me"
          class="!rounded-xl max-w-md"
        />
        <NButton type="primary" secondary @click="updateAdminToken">Save Token</NButton>
      </div>
    </div>
  </div>
</template>