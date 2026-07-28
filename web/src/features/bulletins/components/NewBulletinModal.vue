<script setup lang="ts">
import { ref, computed } from 'vue';
import { NModal, NForm, NFormItem, NInput, NSelect, NButton, NSpace, useMessage } from 'naive-ui';
import { useModeratorStore } from '../../moderators/store';
import { postSignedBulletin } from '../../../lib/api/endpoints';
import type { BulletinPayload } from '../../../lib/canonical';
import { decodeBase64 } from '../../../lib/crypto';

const props = defineProps<{ show: boolean }>();
const emit = defineEmits<{ (e: 'update:show', v: boolean): void; (e: 'posted'): void }>();

const moderator = useModeratorStore();
const message = useMessage();

const kind = ref<'VerifiedUpdate' | 'Debunk'>('VerifiedUpdate');
const title = ref('');
const body = ref('');
const submitting = ref(false);
const error = ref<string | null>(null);

const kindOptions = [
  { label: 'Verified update', value: 'VerifiedUpdate' },
  { label: 'Debunk', value: 'Debunk' },
];

const ready = computed(
  () => !!moderator.stored?.id && title.value.trim().length > 0 && body.value.trim().length > 0,
);

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
    message.success('Bulletin posted');
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
  >
    <NForm>
      <NFormItem label="Kind">
        <NSelect v-model:value="kind" :options="kindOptions" />
      </NFormItem>
      <NFormItem label="Title">
        <NInput v-model:value="title" placeholder="Hospital A is open" />
      </NFormItem>
      <NFormItem label="Body">
        <NInput v-model:value="body" type="textarea" :rows="5" />
      </NFormItem>
      <div v-if="error" class="text-rose-400 text-sm mb-2">{{ error }}</div>
      <div v-if="!moderator.stored" class="text-amber-400 text-sm mb-2">
        No keypair loaded. Visit Moderators first.
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