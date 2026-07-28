<script setup lang="ts">
import { RouterLink, RouterView, useRoute } from 'vue-router';
import { computed, h } from 'vue';
import { NConfigProvider, NMessageProvider, darkTheme, NLayout, NLayoutHeader, NLayoutContent, NMenu, NIcon } from 'naive-ui';

const route = useRoute();
const menuOptions = [
  { label: () => h(RouterLink, { to: '/' }, { default: () => 'Dashboard' }), key: '/' },
  { label: () => h(RouterLink, { to: '/bulletins' }, { default: () => 'Bulletins' }), key: '/bulletins' },
  { label: () => h(RouterLink, { to: '/requests' }, { default: () => 'Requests' }), key: '/requests' },
  { label: () => h(RouterLink, { to: '/moderators' }, { default: () => 'Moderators' }), key: '/moderators' },
  { label: () => h(RouterLink, { to: '/sync' }, { default: () => 'Sync' }), key: '/sync' },
];

const activeKey = computed(() => route.path);
</script>

<template>
  <NConfigProvider :theme="darkTheme">
    <NMessageProvider>
      <NLayout class="min-h-screen">
        <NLayoutHeader bordered class="px-6 py-3 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <NIcon size="22"><span>📡</span></NIcon>
            <h1 class="text-lg font-semibold m-0">TruthRelay Admin</h1>
          </div>
          <NMenu mode="horizontal" :options="menuOptions" :value="activeKey" responsive />
        </NLayoutHeader>
        <NLayoutContent class="p-6 max-w-6xl mx-auto">
          <RouterView />
        </NLayoutContent>
      </NLayout>
    </NMessageProvider>
  </NConfigProvider>
</template>