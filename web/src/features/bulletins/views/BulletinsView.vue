<script setup lang="ts">
import { onMounted, ref, h, computed } from 'vue';
import {
  NDataTable,
  NButton,
  NSpace,
  NTag,
  NInput,
  NSelect,
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

onMounted(() => store.refresh());

const kindOptions = [
  { label: 'All kinds', value: '' },
  { label: 'Verified update', value: 'VerifiedUpdate' },
  { label: 'Debunk', value: 'Debunk' },
  { label: 'Blood', value: 'Blood' },
  { label: 'Missing', value: 'Missing' },
  { label: 'Supply', value: 'Supply' },
];

const filtered = computed(() => {
  const needle = search.value.trim().toLowerCase();
  return items.value.filter((b) => {
    if (kindFilter.value && b.kind !== kindFilter.value) return false;
    if (!needle) return true;
    return (
      b.title.toLowerCase().includes(needle) ||
      b.body.toLowerCase().includes(needle)
    );
  });
});

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
    render: (row) => h(StatusBadge, { kind: row.kind, verified: row.kind === 'VerifiedUpdate' }),
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

    <div class="card-soft p-4 flex flex-wrap items-center gap-3">
      <NInput
        v-model:value="search"
        placeholder="Search title or body…"
        clearable
        class="max-w-xs"
      />
      <NSelect
        v-model:value="kindFilter"
        :options="kindOptions"
        placeholder="Filter by kind"
        style="width: 200px"
      />
      <span class="text-xs text-slate-500 dark:text-slate-400 ml-auto tabular-nums">
        Showing {{ filtered.length }} of {{ items.length }}
      </span>
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