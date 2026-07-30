<script setup lang="ts">
import { onMounted, h, ref, computed } from 'vue';
import { NDataTable, NInput, NSelect, type DataTableColumns } from 'naive-ui';
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
  <div class="space-y-6">
    <header 
      v-motion
      :initial="{ opacity: 0, y: -20 }"
      :enter="{ opacity: 1, y: 0, transition: { duration: 500, ease: 'easeOut' } }"
      class="flex items-end justify-between flex-wrap gap-3"
    >
      <div>
        <h1 class="text-3xl font-bold m-0 text-slate-900 dark:text-white tracking-tight">
          Help Requests
        </h1>
        <p class="text-sm text-slate-500 dark:text-slate-400 m-0 mt-1 font-medium">
          Citizens in distress — queued for moderator triage.
        </p>
      </div>
      <div class="flex items-center gap-4">
        <span class="text-xs uppercase tracking-widest text-rose-600 dark:text-rose-400 font-bold bg-rose-50 dark:bg-rose-500/10 px-3 py-1.5 rounded-full border border-rose-200 dark:border-rose-500/30">
          <span class="inline-block w-2 h-2 rounded-full bg-rose-500 animate-pulse mr-1"></span>
          {{ urgentCount }} urgent
        </span>
        <button
          type="button"
          class="text-xs font-semibold px-4 py-2 rounded-full border border-slate-200 dark:border-slate-800 text-slate-500 hover:text-emerald-600 hover:border-emerald-200 dark:text-slate-400 dark:hover:text-emerald-400 dark:hover:border-emerald-800 transition-all shadow-sm bg-white dark:bg-slate-900"
          @click="store.refresh()"
        >
          ↻ Refresh
        </button>
      </div>
    </header>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 150, duration: 500, ease: 'easeOut' } }"
      class="surface-tile p-4 flex flex-wrap items-center gap-4"
    >
      <NInput
        v-model:value="search"
        placeholder="Search body or title…"
        clearable
        class="max-w-sm flex-1 !rounded-xl"
      />
      <NSelect
        v-model:value="kindFilter"
        :options="kindOptions"
        placeholder="Filter by kind"
        style="width: 200px"
      />
      <span class="text-xs font-bold text-slate-400 dark:text-slate-500 tabular-nums bg-slate-100 dark:bg-slate-900 px-3 py-1 rounded-full ml-auto">
        {{ filtered.length }} / {{ items.length }} shown
      </span>
    </div>

    <div 
      v-motion
      :initial="{ opacity: 0, y: 20 }"
      :enter="{ opacity: 1, y: 0, transition: { delay: 250, duration: 500, ease: 'easeOut' } }"
      class="surface-tile p-1 sm:p-2"
    >
      <NDataTable
        :columns="columns"
        :data="filtered"
        :loading="loading"
        :bordered="false"
        size="medium"
        class="!rounded-xl"
      />
    </div>
  </div>
</template>