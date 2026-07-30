<script setup lang="ts">
import { ref, computed } from 'vue';
import {
  NConfigProvider,
  NMessageProvider,
  NIcon,
  NTooltip,
  darkTheme,
  lightTheme,
  type GlobalTheme,
  type GlobalThemeOverrides,
} from 'naive-ui';
import { RouterLink, RouterView, useRoute } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useThemeStore } from './lib/ui/theme';

const themeStore = useThemeStore();
const { theme: themeName } = storeToRefs(themeStore);
const route = useRoute();

const activeTheme = computed<GlobalTheme>(() =>
  themeName.value === 'light' ? lightTheme : darkTheme,
);

const isSidebarCollapsed = ref(false);
const isMobileMenuOpen = ref(false);

const menuOptions = [
  { label: 'Dashboard', key: '/', icon: '📊', description: 'Crisis telemetry overview' },
  { label: 'Bulletins', key: '/bulletins', icon: '📢', description: 'Signed updates broadcast' },
  { label: 'Requests', key: '/requests', icon: '🩸', description: 'Triage help queue' },
  { label: 'Moderators', key: '/moderators', icon: '🛡️', description: 'Keypairs & identity' },
  { label: 'Sync', key: '/sync', icon: '🔄', description: 'P2P mesh replication' },
];

const currentPageTitle = computed(() => {
  const current = menuOptions.find((m) => m.key === route.path);
  return current ? current.label : 'TruthRelay';
});

function toggleSidebar() {
  if (typeof window !== 'undefined' && window.innerWidth < 768) {
    isMobileMenuOpen.value = !isMobileMenuOpen.value;
  } else {
    isSidebarCollapsed.value = !isSidebarCollapsed.value;
  }
}

function closeMobileMenu() {
  isMobileMenuOpen.value = false;
}

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
      <div class="min-h-screen bg-slate-50 dark:bg-slate-950 flex transition-colors duration-500 relative overflow-x-hidden">
        
        <!-- Desktop Left Sidebar -->
        <aside
          class="hidden md:flex flex-col fixed inset-y-0 left-0 z-40 bg-white/80 dark:bg-slate-900/80 backdrop-blur-xl border-r border-slate-200/60 dark:border-slate-800/60 transition-all duration-300 ease-in-out"
          :class="isSidebarCollapsed ? 'w-20' : 'w-64'"
        >
          <!-- Brand Logo Header -->
          <div 
            class="h-16 px-4 flex items-center border-b border-slate-200/60 dark:border-slate-800/60 transition-all"
            :class="isSidebarCollapsed ? 'justify-center' : 'px-6 gap-3'"
          >
            <div class="w-9 h-9 rounded-xl flex items-center justify-center text-emerald-400 bg-emerald-500/10 shadow-glow shrink-0">
              <NIcon size="20"><span>📡</span></NIcon>
            </div>
            <div v-if="!isSidebarCollapsed" class="min-w-0">
              <h1 class="font-bold text-base leading-tight text-slate-900 dark:text-slate-100 tracking-tight m-0 truncate">TruthRelay</h1>
              <p class="text-[10px] uppercase tracking-widest text-emerald-600 dark:text-emerald-400 font-semibold m-0 truncate">Crisis Mesh</p>
            </div>
          </div>

          <!-- Navigation Links -->
          <nav class="flex-1 px-3 py-6 space-y-1 overflow-y-auto">
            <template v-for="item in menuOptions" :key="item.key">
              <NTooltip v-if="isSidebarCollapsed" placement="right" trigger="hover">
                <template #trigger>
                  <RouterLink 
                    :to="item.key"
                    class="flex items-center justify-center p-3 rounded-xl transition-all duration-200 text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800/60 hover:text-slate-900 dark:hover:text-white"
                    active-class="!text-emerald-600 dark:!text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10 shadow-sm"
                  >
                    <span class="text-xl">{{ item.icon }}</span>
                  </RouterLink>
                </template>
                {{ item.label }}
              </NTooltip>

              <RouterLink 
                v-else
                :to="item.key"
                class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold transition-all duration-200 text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800/60 hover:text-slate-900 dark:hover:text-white"
                active-class="!text-emerald-600 dark:!text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10 shadow-sm"
              >
                <span class="text-lg">{{ item.icon }}</span>
                <span class="truncate">{{ item.label }}</span>
              </RouterLink>
            </template>
          </nav>

          <!-- Sidebar Footer -->
          <div class="p-4 border-t border-slate-200/60 dark:border-slate-800/60 space-y-3">
            <div 
              class="flex items-center justify-between"
              :class="isSidebarCollapsed ? 'flex-col gap-3 items-center justify-center' : 'px-2'"
            >
              <NTooltip v-if="isSidebarCollapsed" placement="right" trigger="hover">
                <template #trigger>
                  <span class="relative flex h-3 w-3">
                    <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                    <span class="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
                  </span>
                </template>
                Relay Online
              </NTooltip>

              <span v-else class="flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                Relay Online
              </span>

              <button 
                @click="themeStore.toggle()"
                class="p-2 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800 text-xs font-semibold transition-colors text-slate-600 dark:text-slate-400"
                :title="themeName === 'dark' ? 'Switch to Light Mode' : 'Switch to Dark Mode'"
              >
                {{ themeName === 'dark' ? '☀︎' : '☾' }}
                <span v-if="!isSidebarCollapsed" class="ml-1">{{ themeName === 'dark' ? 'Light' : 'Dark' }}</span>
              </button>
            </div>
          </div>
        </aside>

        <!-- Mobile Drawer Overlay & Sidebar -->
        <transition name="fade">
          <div 
            v-if="isMobileMenuOpen" 
            class="md:hidden fixed inset-0 z-50 bg-slate-950/60 backdrop-blur-sm"
            @click="closeMobileMenu"
          ></div>
        </transition>

        <transition name="slide">
          <aside 
            v-if="isMobileMenuOpen"
            class="md:hidden fixed inset-y-0 left-0 z-50 w-72 sm:w-80 h-full max-h-[100dvh] bg-white/95 dark:bg-slate-900/95 backdrop-blur-2xl border-r border-slate-200 dark:border-slate-800 p-3 sm:p-5 flex flex-col justify-between shadow-2xl overflow-hidden"
          >
            <!-- Header -->
            <div class="flex items-center justify-between pb-3 border-b border-slate-200 dark:border-slate-800 shrink-0">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-xl flex items-center justify-center text-emerald-400 bg-emerald-500/10 shrink-0">
                  <NIcon size="18"><span>📡</span></NIcon>
                </div>
                <div>
                  <span class="font-bold text-base text-slate-900 dark:text-white leading-tight block">TruthRelay</span>
                  <span class="text-[9px] uppercase tracking-widest text-emerald-600 dark:text-emerald-400 font-semibold block">Crisis Mesh</span>
                </div>
              </div>
              <button 
                @click="closeMobileMenu" 
                class="text-slate-400 hover:text-slate-600 dark:hover:text-slate-200 text-lg font-bold p-1 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800/80 transition-colors"
                aria-label="Close menu"
              >
                ✕
              </button>
            </div>

            <!-- Scrollable Nav Links Area with Touch Momentum & Compact Spacing -->
            <div class="flex-1 my-2 overflow-y-auto custom-scrollbar touch-pan-y space-y-1 pr-1">
              <nav class="space-y-1">
                <RouterLink 
                  v-for="item in menuOptions" 
                  :key="item.key" 
                  :to="item.key"
                  @click="closeMobileMenu"
                  class="flex items-center gap-3 px-3 py-2 rounded-xl text-sm font-semibold transition-all text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800/70 hover:text-slate-900 dark:hover:text-white"
                  active-class="!text-emerald-600 dark:!text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10"
                >
                  <span class="text-base shrink-0">{{ item.icon }}</span>
                  <span class="truncate">{{ item.label }}</span>
                </RouterLink>
              </nav>
            </div>

            <!-- Footer -->
            <div class="pt-2.5 border-t border-slate-200 dark:border-slate-800 flex items-center justify-between shrink-0">
              <span class="flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                Relay Active
              </span>
              <button 
                @click="themeStore.toggle()"
                class="px-2.5 py-1 rounded-lg text-slate-600 dark:text-slate-400 text-xs font-semibold hover:bg-slate-100 dark:hover:bg-slate-800 border border-slate-200/60 dark:border-slate-800/60 transition-colors"
              >
                {{ themeName === 'dark' ? '☀︎ Light' : '☾ Dark' }}
              </button>
            </div>
          </aside>
        </transition>

        <!-- Right Side Data Wrapper with Sticky Top Menubar -->
        <div 
          class="flex-1 flex flex-col min-w-0 w-full transition-all duration-300 ease-in-out"
          :class="isSidebarCollapsed ? 'md:pl-20' : 'md:pl-64'"
        >
          <!-- Top Menubar Navbar -->
          <header class="sticky top-0 z-30 h-16 px-4 sm:px-6 bg-white/80 dark:bg-slate-900/80 backdrop-blur-xl border-b border-slate-200/60 dark:border-slate-800/60 flex items-center justify-between min-w-0 w-full">
            
            <!-- Left Side: Mandatory Menu Bar Icon & Current Page Title -->
            <div class="flex items-center gap-3 min-w-0">
              <!-- Mandatory Menu Bar Icon -->
              <button
                type="button"
                @click="toggleSidebar"
                class="p-2.5 rounded-xl text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800/80 border border-slate-200/80 dark:border-slate-800/80 transition-all flex items-center justify-center shrink-0 shadow-xs hover:border-emerald-500/30"
                title="Toggle Sidebar Menu"
                aria-label="Toggle Sidebar Menu"
              >
                <span class="text-lg leading-none font-bold">☰</span>
              </button>

              <div class="h-5 w-px bg-slate-200 dark:bg-slate-800 hidden sm:block shrink-0"></div>

              <div class="flex items-center gap-2 min-w-0">
                <span class="font-bold text-lg text-slate-900 dark:text-slate-100 tracking-tight truncate">
                  {{ currentPageTitle }}
                </span>
                <span class="hidden sm:inline-flex items-center text-[10px] uppercase font-bold tracking-widest px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border border-emerald-500/20 shrink-0">
                  Live
                </span>
              </div>
            </div>

            <!-- Right Side: Action Badges & Quick Controls -->
            <div class="flex items-center gap-3 shrink-0">
              <div class="hidden sm:flex items-center gap-2 text-xs font-semibold px-3 py-1.5 rounded-full bg-slate-100 dark:bg-slate-800/60 text-slate-600 dark:text-slate-400 border border-slate-200/60 dark:border-slate-700/60">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                Mesh Active
              </div>

              <button 
                type="button"
                @click="themeStore.toggle()"
                class="p-2.5 rounded-xl border border-slate-200/80 dark:border-slate-800/80 hover:bg-slate-100 dark:hover:bg-slate-800/80 text-xs font-semibold transition-all text-slate-600 dark:text-slate-300 flex items-center gap-1.5 shadow-xs"
                title="Toggle Theme"
              >
                <span>{{ themeName === 'dark' ? '☀︎' : '☾' }}</span>
                <span class="hidden md:inline">{{ themeName === 'dark' ? 'Light' : 'Dark' }}</span>
              </button>
            </div>
          </header>

          <!-- Main Content Area -->
          <main class="flex-1 w-full max-w-full min-w-0 p-4 sm:p-6 lg:p-8">
            <RouterView v-slot="{ Component }">
              <transition name="fade" mode="out-in">
                <component :is="Component" />
              </transition>
            </RouterView>
          </main>
        </div>

      </div>
    </NMessageProvider>
  </NConfigProvider>
</template>

<style>
.slide-enter-active,
.slide-leave-active {
  transition: transform 300ms ease-in-out;
}
.slide-enter-from,
.slide-leave-to {
  transform: translateX(-100%);
}
</style>