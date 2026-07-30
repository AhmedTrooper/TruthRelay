<script setup lang="ts">
import { ref, computed } from 'vue';
import { NModal, NForm, NFormItem, NInput, NSelect, NButton, NSpace, NAlert, useMessage } from 'naive-ui';
import { useModeratorStore } from '../../moderators/store';
import { postSignedBulletin } from '../../../lib/api/endpoints';
import type { BulletinPayload } from '../../../lib/canonical';
import { decodeBase64, encodeBase64 } from '../../../lib/crypto';
import * as ed from '@noble/ed25519';

import { getAdminToken } from '../../../lib/api/client';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ (e: 'update:show', v: boolean): void; (e: 'posted'): void }>();

const moderator = useModeratorStore();
const message = useMessage();

const kind = ref<'VerifiedUpdate' | 'Debunk'>('VerifiedUpdate');
const title = ref('');
const body = ref('');
const submitting = ref(false);
const autoRegistering = ref(false);
const error = ref<string | null>(null);
const customAdminToken = ref(getAdminToken());

function saveAdminToken() {
  if (customAdminToken.value.trim()) {
    localStorage.setItem('truthrelay.admin_token', customAdminToken.value.trim());
    message.success('Admin Token saved locally!');
  }
}

const kindOptions = [
  { label: 'Verified update', value: 'VerifiedUpdate' },
  { label: 'Debunk', value: 'Debunk' },
];

const hasKey = computed(() => !!moderator.stored?.secret_key_b64);
const isRegistered = computed(() => !!moderator.stored?.id);
const hasInput = computed(() => title.value.trim().length > 0 && body.value.trim().length > 0);

const ready = computed(() => isRegistered.value && hasInput.value);

async function quickGenerateAndRegister() {
  autoRegistering.value = true;
  error.value = null;
  try {
    const secretKey = ed.utils.randomSecretKey();
    const pubKey = await ed.getPublicKeyAsync(secretKey);
    moderator.setFromKeygen({
      name: 'Admin Moderator',
      public_key_b64: encodeBase64(pubKey),
      secret_key_b64: encodeBase64(secretKey),
      created_at: new Date().toISOString(),
    });
    await moderator.register();
    message.success('Generated and registered moderator keypair!');
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? String(e);
    error.value = 'Key registration failed: ' + msg;
    message.error(error.value);
  } finally {
    autoRegistering.value = false;
  }
}

async function registerExistingKey() {
  if (!moderator.stored) return;
  autoRegistering.value = true;
  error.value = null;
  try {
    await moderator.register();
    message.success('Registered keypair on server!');
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? String(e);
    error.value = 'Registration failed: ' + msg;
    message.error(error.value);
  } finally {
    autoRegistering.value = false;
  }
}

async function submit() {
  if (!ready.value || !moderator.stored) return;
  submitting.value = true;
  error.value = null;
  try {
    const payload: BulletinPayload = {
      kind: kind.value,
      title: title.value.trim(),
      body: body.value.trim(),
      created_at: new Date().toISOString(),
    };
    const secretKey = decodeBase64(moderator.stored.secret_key_b64);
    await postSignedBulletin(moderator.stored.id, payload, secretKey);
    message.success('Bulletin signed & posted!');
    title.value = '';
    body.value = '';
    emit('posted');
    emit('update:show', false);
  } catch (e: any) {
    const msg = e?.response?.data?.message ?? e?.message ?? String(e);
    error.value = msg;
    message.error(msg);
  } finally {
    submitting.value = false;
  }
}
</script>

<template>
  <NModal
    :show="props.show"
    @update:show="(v: boolean) => emit('update:show', v)"
    preset="card"
    title="Sign & post bulletin"
    style="max-width: 600px"
    class="!rounded-2xl"
  >
    <NForm>
      <!-- Keypair Status Alert -->
      <NAlert v-if="!hasKey" type="warning" title="No Moderator Keypair Loaded" class="!rounded-xl mb-4">
        You need an Ed25519 moderator keypair to sign bulletins.
        <div class="mt-3">
          <NButton size="small" type="primary" :loading="autoRegistering" @click="quickGenerateAndRegister">
            ⚡ Quick Generate & Register Keypair
          </NButton>
        </div>
      </NAlert>

      <NAlert v-else-if="!isRegistered" type="info" title="Keypair Loaded (Unregistered on Server)" class="!rounded-xl mb-4">
        Keypair for <strong>{{ moderator.stored?.name }}</strong> is saved locally but not yet registered on the server.
        <div class="mt-3">
          <NButton size="small" type="primary" :loading="autoRegistering" @click="registerExistingKey">
            Register Keypair on Server
          </NButton>
        </div>
      </NAlert>

      <NFormItem label="Kind">
        <NSelect v-model:value="kind" :options="kindOptions" class="!rounded-xl" />
      </NFormItem>
      <NFormItem label="Title">
        <NInput v-model:value="title" placeholder="e.g. Hospital A is open and accepting blood donors" class="!rounded-xl" />
      </NFormItem>
      <NFormItem label="Body">
        <NInput v-model:value="body" type="textarea" :rows="5" placeholder="Detailed information..." class="!rounded-xl" />
      </NFormItem>
      
      <NAlert v-if="error" type="error" :title="error" class="!rounded-xl mb-4">
        <div v-if="error.toLowerCase().includes('unauthorized') || error.toLowerCase().includes('token')" class="mt-2 space-y-2">
          <div class="text-xs">Enter your server's <code>TRUTHRELAY_ADMIN_TOKEN</code>:</div>
          <div class="flex items-center gap-2">
            <NInput v-model:value="customAdminToken" type="password" show-password-on="click" placeholder="dev-token-change-me" size="small" class="!rounded-lg" />
            <NButton size="small" type="primary" secondary @click="saveAdminToken">Save Token</NButton>
          </div>
        </div>
      </NAlert>
      
      <div v-if="isRegistered && !hasInput" class="text-slate-400 text-xs mb-3 font-medium">
        ℹ️ Enter a title and body to enable signing.
      </div>

      <NSpace justify="end">
        <NButton @click="emit('update:show', false)">Cancel</NButton>
        <NButton type="primary" :loading="submitting" :disabled="!ready" @click="submit">
          Sign & post
        </NButton>
      </NSpace>
    </NForm>
  </NModal>
</template>