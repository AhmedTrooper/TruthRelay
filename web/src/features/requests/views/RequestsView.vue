<script setup lang="ts">
import { onMounted, h, ref, computed } from 'vue';
import { NDataTable, NButton, NInput, NSelect, type DataTableColumns } from 'naive-ui';
import { storeToRefs } from 'pinia';
import { useRequestsStore } from '../store';
import StatusBadge from '../../../components/StatusBadge.vue';
import type { HelpRequestView } from '../../../lib/api/endpoints';

const store = useRequestsStore();
const { items, loading } = storeToRefs(store);

const search = ref('');
const kindFilter = ref<string>('');

onMounted(() => store.refresh());

const kindOptions = [
  { label: 'All kinds', value: '' },
  { label: 'Blood', value: 'Blood' },
  { label: 'Missing', value: 'Missing' },
  { label: 'Supply', value: 'Supply' },
];

const filtered = computed(() => {
  const needle = search.value.trim().toLowerCase();
  return items.value.filter((r) => {
    if (kindFilter.value && r.kind !== kindFilter.value) return false;
    if (!needle) return true;
    return (
      r.title.toLowerCase().includes(needle) ||
      r.body.toLowerCase().includes(needle)
    );
  });
});

const urgentCount = computed(
  () =>
    items.value.filter(
      (r) => r.kind === 'Blood' || r.kind === 'Missing',
    ).length,
);

const columns: DataTableColumns<HelpRequestView> = [
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
    width: 140,
    render: (row) => h(StatusBadge, { kind: row.kind }),
  },
  {
    title: 'Location',
    key: 'location',
    width: 200,
    render: (row) => h('span', { class: 'text-sm text-slate-700 dark:text-slate-300' }, row.location ?? '—'),
  },
  {
    title: 'Contact',
    key: 'contact',
    width: 180,
    render: (row) => h('span', { class: 'text-sm text-slate-700 dark:text-slate-300 font-mono' }, row.contact ?? '—'),
  },
  {
    title: 'Received',
    key: 'received_at',
    width: 200,
    render: (row) => h('span', { class: 'text-xs text-slate-500 dark:text-slate-400 tabular-nums' }, row.received_at),
  },
];
</script>

<template>
  <div class="space-y-6 animate-fade-in">
    <header class="flex items-end justify-between flex-wrap gap-3">
      <div>
        <h1 class="text-2xl font-semibold m-0 text-slate-900 dark:text-slate-50">
          Help requests
        </h1>
        <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1">
          Citizens in distress — queued for moderator triage.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-xs uppercase tracking-widest text-rose-600 dark:text-rose-300 font-medium">
          {{ urgentCount }} urgent
        </span>
        <NButton @click="store.refresh()">Refresh</NButton>
      </div>
    </header>

    <div class="card-soft p-4 flex flex-wrap items-center gap-3">
      <NInput
        v-model:value="search"
        placeholder="Search body or title…"
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
        {{ filtered.length }} / {{ items.length }} shown
      </span>
    </div>

    <div class="card-soft p-2">
      <NDataTable
        :columns="columns"
        :data="filtered"
        :loading="loading"
        :bordered="false"
        size="medium"
        class="!rounded-lg"
      />
    </div>
  </div>
</template>