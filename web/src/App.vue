<script setup lang="ts">
import { computed, h } from 'vue';
import {
  NConfigProvider,
  NMessageProvider,
  NLayout,
  NLayoutSider,
  NLayoutHeader,
  NLayoutContent,
  NMenu,
  NIcon,
  NButton,
  darkTheme,
  lightTheme,
  type GlobalTheme,
  type GlobalThemeOverrides,
} from 'naive-ui';
import { RouterLink, RouterView, useRoute } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useThemeStore } from './lib/ui/theme';

const route = useRoute();
const themeStore = useThemeStore();
const { theme: themeName } = storeToRefs(themeStore);

const activeTheme = computed<GlobalTheme>(() =>
  themeName.value === 'light' ? lightTheme : darkTheme,
);

const menuOptions = [
  { label: () => h(RouterLink, { to: '/' }, { default: () => 'Dashboard' }), key: '/' },
  { label: () => h(RouterLink, { to: '/bulletins' }, { default: () => 'Bulletins' }), key: '/bulletins' },
  { label: () => h(RouterLink, { to: '/requests' }, { default: () => 'Requests' }), key: '/requests' },
  { label: () => h(RouterLink, { to: '/moderators' }, { default: () => 'Moderators' }), key: '/moderators' },
  { label: () => h(RouterLink, { to: '/sync' }, { default: () => 'Sync' }), key: '/sync' },
];

const activeKey = computed(() => route.path);

const themeOverrides = computed<GlobalThemeOverrides>(() => ({
  common: {
    primaryColor: '#10b981',
    primaryColorHover: '#34d399',
    primaryColorPressed: '#059669',
  },
}));
</script>

<template>
  <NConfigProvider :theme="activeTheme" :theme-overrides="themeOverrides">
    <NMessageProvider>
      <NLayout has-sider class="min-h-screen">
        <NLayoutSider
          bordered
          collapse-mode="width"
          :collapsed-width="64"
          :width="220"
          show-trigger
          class="!bg-slate-50 dark:!bg-slate-950"
        >
          <div class="px-4 py-5 flex items-center gap-3 border-b border-slate-200 dark:border-slate-800">
            <div
              class="w-9 h-9 rounded-lg flex items-center justify-center text-emerald-400 bg-emerald-500/10 shadow-glow"
            >
              <NIcon size="20"><span>📡</span></NIcon>
            </div>
            <div v-if="!$route" class="leading-tight">
              <p class="font-semibold m-0 text-slate-900 dark:text-slate-100">TruthRelay</p>
              <p class="text-[10px] uppercase tracking-widest text-slate-500 dark:text-slate-400 m-0">
                Admin
              </p>
            </div>
          </div>
          <NMenu
            mode="vertical"
            :options="menuOptions"
            :value="activeKey"
            class="!bg-transparent"
          />
        </NLayoutSider>
        <NLayout>
          <NLayoutHeader
            bordered
            class="px-6 py-3 flex items-center justify-between !bg-white/70 dark:!bg-slate-950/60 backdrop-blur"
          >
            <div>
              <p class="text-xs uppercase tracking-widest text-slate-500 dark:text-slate-400 m-0">
                Crisis-tech admin
              </p>
              <p class="text-sm font-medium text-slate-800 dark:text-slate-100 m-0">
                Verify bulletins, watch the mesh, dispatch moderators.
              </p>
            </div>
            <div class="flex items-center gap-3">
              <span class="hidden md:inline-flex items-center gap-1 text-xs text-slate-500 dark:text-slate-400">
                <span class="w-2 h-2 rounded-full bg-emerald-400 animate-pulse-slow"></span>
                Relay online
              </span>
              <NButton size="small" @click="themeStore.toggle()">
                {{ themeName === 'dark' ? '☀︎ Light' : '☾ Dark' }}
              </NButton>
            </div>
          </NLayoutHeader>
          <NLayoutContent class="p-6 max-w-6xl mx-auto">
            <RouterView v-slot="{ Component }">
              <transition name="fade" mode="out-in">
                <component :is="Component" />
              </transition>
            </RouterView>
          </NLayoutContent>
        </NLayout>
      </NLayout>
    </NMessageProvider>
  </NConfigProvider>
</template>

<style>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 180ms ease, transform 220ms ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
  transform: translateY(6px);
}
</style>