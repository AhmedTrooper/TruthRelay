<script setup lang="ts">
import { onMounted, ref, h, computed } from 'vue';
import {
  NDataTable,
  NButton,
  NSpace,
  NTag,
  NInput,
  NSwitch,
  type DataTableColumns,
} from 'naive-ui';
import { storeToRefs } from 'pinia';
import { useBulletinsStore } from '../store';
import StatusBadge from '../../../components/StatusBadge.vue';
import NewBulletinModal from '../components/NewBulletinModal.vue';
import type { BulletinView } from '../../../lib/api/endpoints';

const store = useBulletinsStore();
const { items, loading } = storeToRefs(store);

const showModal = ref(false);
const search = ref('');
const kindFilter = ref<string>('');
const signedOnly = ref(false);

onMounted(() => store.refresh());

const kindChips = [
  { label: 'All', value: '', accent: 'from-slate-500/10 to-slate-500/0' },
  { label: 'Verified update', value: 'VerifiedUpdate', accent: 'from-sky-500/10 to-sky-500/0' },
  { label: 'Debunk', value: 'Debunk', accent: 'from-rose-500/10 to-rose-500/0' },
  { label: 'Blood', value: 'Blood', accent: 'from-rose-500/10 to-rose-500/0' },
  { label: 'Missing', value: 'Missing', accent: 'from-amber-500/10 to-amber-500/0' },
  { label: 'Supply', value: 'Supply', accent: 'from-violet-500/10 to-violet-500/0' },
];

const filtered = computed(() => {
  const needle = search.value.trim().toLowerCase();
  return items.value.filter((b) => {
    if (kindFilter.value && b.kind !== kindFilter.value) return false;
    if (signedOnly.value && !b.signature_b64) return false;
    if (!needle) return true;
    return (
      b.title.toLowerCase().includes(needle) ||
      b.body.toLowerCase().includes(needle) ||
      (b.moderator_name ?? '').toLowerCase().includes(needle)
    );
  });
});

function isVerified(b: BulletinView): boolean {
  return b.kind === 'VerifiedUpdate';
}

const columns: DataTableColumns<BulletinView> = [
  {
    title: 'Title',
    key: 'title',
    render: (row) =>
      h('div', { class: 'font-medium' }, [
        h('div', row.title),
        h('div', { class: 'text-xs text-slate-500 dark:text-slate-400 mt-1 line-clamp-2' }, row.body),
      ]),
  },
  {
    title: 'Kind',
    key: 'kind',
    width: 160,
    render: (row) => h(StatusBadge, { kind: row.kind, verified: isVerified(row) }),
  },
  {
    title: 'Moderator',
    key: 'moderator',
    width: 180,
    render: (row) =>
      h(
        NTag,
        { size: 'small', bordered: false, round: true },
        { default: () => row.moderator_name ?? row.moderator_id.slice(0, 8) },
      ),
  },
  {
    title: 'Received',
    key: 'received_at',
    width: 200,
    render: (row) => h('span', { class: 'text-xs text-slate-500 dark:text-slate-400 tabular-nums' }, row.received_at),
  },
  {
    title: 'Hash',
    key: 'sha256',
    width: 140,
    render: (row) =>
      h(
        'code',
        { class: 'text-[11px] text-slate-500 dark:text-slate-400 font-mono' },
        row.sha256.slice(0, 10) + '…',
      ),
  },
];
</script>

<template>
  <div class="space-y-6 animate-fade-in">
    <header class="flex items-end justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold m-0 text-slate-900 dark:text-slate-50">
          Bulletins
        </h1>
        <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1">
          Sign a crisis update and broadcast it to every connected peer.
        </p>
      </div>
      <NSpace>
        <NButton @click="store.refresh()">Refresh</NButton>
        <NButton type="primary" @click="showModal = true">
          + New bulletin
        </NButton>
      </NSpace>
    </header>

    <div class="card-soft p-4 space-y-4">
      <div class="flex items-center flex-wrap gap-2">
        <button
          v-for="c in kindChips"
          :key="c.value"
          type="button"
          class="px-3 py-1.5 rounded-full text-xs font-semibold tracking-wide border transition focus:outline-none focus:ring-2 focus:ring-emerald-400"
          :class="
            kindFilter === c.value
              ? `bg-gradient-to-br ${c.accent} border-emerald-400 dark:border-emerald-400 text-slate-900 dark:text-slate-50`
              : 'bg-slate-50 dark:bg-slate-900 border-slate-200 dark:border-slate-800 text-slate-600 dark:text-slate-400 hover:border-slate-300 dark:hover:border-slate-700'
          "
          @click="kindFilter = c.value"
        >
          {{ c.label }}
        </button>
      </div>

      <div class="flex flex-wrap items-center gap-3">
        <NInput
          v-model:value="search"
          placeholder="Search title, body, or moderator…"
          clearable
          class="max-w-xs"
        />
        <NSpace align="center" class="ml-auto">
          <span class="text-xs text-slate-500 dark:text-slate-400">Signed only</span>
          <NSwitch v-model:value="signedOnly" size="small" />
          <span class="text-xs text-slate-500 dark:text-slate-400 tabular-nums">
            Showing {{ filtered.length }} of {{ items.length }}
          </span>
        </NSpace>
      </div>
    </div>

    <div class="card-soft p-2">
      <NDataTable
        :columns="columns"
        :data="filtered"
        :loading="loading"
        :bordered="false"
        :single-line="false"
        size="medium"
        class="!rounded-lg"
      />
    </div>

    <NewBulletinModal
      v-model:show="showModal"
      @posted="store.refresh()"
    />
  </div>
</template>