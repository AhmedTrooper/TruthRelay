<script setup lang="ts">
import { onMounted, h } from 'vue';
import { NDataTable, NButton, type DataTableColumns } from 'naive-ui';
import { storeToRefs } from 'pinia';
import { useRequestsStore } from '../store';
import StatusBadge from '../../../components/StatusBadge.vue';
import type { HelpRequestView } from '../../../lib/api/endpoints';

const store = useRequestsStore();
const { items, loading } = storeToRefs(store);

onMounted(() => store.refresh());

const columns: DataTableColumns<HelpRequestView> = [
  {
    title: 'Title',
    key: 'title',
    render: (row) =>
      h('div', { class: 'font-medium' }, [
        h('div', row.title),
        h('div', { class: 'text-xs text-slate-400 mt-1 line-clamp-2' }, row.body),
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
    width: 180,
    render: (row) => h('span', { class: 'text-sm text-slate-300' }, row.location ?? '—'),
  },
  {
    title: 'Contact',
    key: 'contact',
    width: 180,
    render: (row) => h('span', { class: 'text-sm text-slate-300' }, row.contact ?? '—'),
  },
  {
    title: 'Received',
    key: 'received_at',
    width: 200,
    render: (row) => h('span', { class: 'text-xs text-slate-400' }, row.received_at),
  },
];
</script>

<template>
  <div class="space-y-4">
    <div class="flex items-center justify-between">
      <h1 class="text-2xl font-semibold">Help Requests</h1>
      <NButton @click="store.refresh()">Refresh</NButton>
    </div>

    <NDataTable
      :columns="columns"
      :data="items"
      :loading="loading"
      :bordered="false"
      size="medium"
    />
  </div>
</template>