<script setup lang="ts">
import { onMounted, ref, h } from 'vue';
import {
  NDataTable,
  NButton,
  NSpace,
  NTag,
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

onMounted(() => store.refresh());

const columns: DataTableColumns<BulletinView> = [
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
    title: 'Moderator',
    key: 'moderator',
    width: 180,
    render: (row) =>
      h(
        NTag,
        { size: 'small', bordered: false },
        { default: () => row.moderator_name ?? row.moderator_id.slice(0, 8) },
      ),
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
      <h1 class="text-2xl font-semibold">Bulletins</h1>
      <NSpace>
        <NButton @click="store.refresh()">Refresh</NButton>
        <NButton type="primary" @click="showModal = true">New bulletin</NButton>
      </NSpace>
    </div>

    <NDataTable
      :columns="columns"
      :data="items"
      :loading="loading"
      :bordered="false"
      :single-line="false"
      size="medium"
    />

    <NewBulletinModal
      v-model:show="showModal"
      @posted="store.refresh()"
    />
  </div>
</template>