<script setup lang="ts">
import { ref, computed } from 'vue';
import {
  NConfigProvider,
  NMessageProvider,
  NIcon,
  darkTheme,
  lightTheme,
  type GlobalTheme,
  type GlobalThemeOverrides,
} from 'naive-ui';
import { RouterLink, RouterView } from 'vue-router';
import { storeToRefs } from 'pinia';
import { useThemeStore } from './lib/ui/theme';

const themeStore = useThemeStore();
const { theme: themeName } = storeToRefs(themeStore);

const activeTheme = computed<GlobalTheme>(() =>
  themeName.value === 'light' ? lightTheme : darkTheme,
);

const isMobileMenuOpen = ref(false);

const menuOptions = [
  { label: 'Dashboard', key: '/', icon: '📊' },
  { label: 'Bulletins', key: '/bulletins', icon: '📢' },
  { label: 'Requests', key: '/requests', icon: '🩸' },
  { label: 'Moderators', key: '/moderators', icon: '🛡️' },
  { label: 'Sync', key: '/sync', icon: '🔄' },
];

function toggleMobileMenu() {
  isMobileMenuOpen.value = !isMobileMenuOpen.value;
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
      <div class="min-h-screen bg-slate-50 dark:bg-slate-950 flex transition-colors duration-500 relative">
        
        <!-- Desktop Fixed Left Sidebar -->
        <aside
          class="hidden md:flex flex-col w-64 fixed inset-y-0 left-0 z-40 bg-white/80 dark:bg-slate-900/80 backdrop-blur-xl border-r border-slate-200/60 dark:border-slate-800/60"
        >
          <!-- Brand Logo -->
          <div class="h-16 px-6 flex items-center gap-3 border-b border-slate-200/60 dark:border-slate-800/60">
            <div class="w-9 h-9 rounded-xl flex items-center justify-center text-emerald-400 bg-emerald-500/10 shadow-glow">
              <NIcon size="20"><span>📡</span></NIcon>
            </div>
            <div>
              <h1 class="font-bold text-base leading-tight text-slate-900 dark:text-slate-100 tracking-tight m-0">TruthRelay</h1>
              <p class="text-[10px] uppercase tracking-widest text-emerald-600 dark:text-emerald-400 font-semibold m-0">Crisis Mesh</p>
            </div>
          </div>

          <!-- Navigation Links -->
          <nav class="flex-1 px-4 py-6 space-y-1 overflow-y-auto">
            <RouterLink 
              v-for="item in menuOptions" 
              :key="item.key" 
              :to="item.key"
              class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold transition-all duration-200 text-slate-600 dark:text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800/60 hover:text-slate-900 dark:hover:text-white"
              active-class="!text-emerald-600 dark:!text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10 shadow-sm"
            >
              <span class="text-lg">{{ item.icon }}</span>
              <span>{{ item.label }}</span>
            </RouterLink>
          </nav>

          <!-- Footer Status & Theme Toggle -->
          <div class="p-4 border-t border-slate-200/60 dark:border-slate-800/60 space-y-3">
            <div class="flex items-center justify-between px-2">
              <span class="flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
                <span class="relative flex h-2 w-2">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                  <span class="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
                </span>
                Relay Online
              </span>
              <button 
                @click="themeStore.toggle()"
                class="p-2 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800 text-xs font-semibold transition-colors text-slate-600 dark:text-slate-400"
              >
                {{ themeName === 'dark' ? '☀︎ Light' : '☾ Dark' }}
              </button>
            </div>
          </div>
        </aside>

        <!-- Mobile Top Bar with Hamburger Toggle -->
        <div class="md:hidden fixed top-0 left-0 right-0 z-40 h-16 px-4 bg-white/80 dark:bg-slate-950/80 backdrop-blur-xl border-b border-slate-200/60 dark:border-slate-800/60 flex items-center justify-between">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 rounded-lg flex items-center justify-center text-emerald-400 bg-emerald-500/10">
              <NIcon size="18"><span>📡</span></NIcon>
            </div>
            <span class="font-bold text-base text-slate-900 dark:text-slate-100">TruthRelay</span>
          </div>

          <div class="flex items-center gap-2">
            <button 
              @click="themeStore.toggle()"
              class="p-2 rounded-lg text-slate-600 dark:text-slate-400"
            >
              {{ themeName === 'dark' ? '☀︎' : '☾' }}
            </button>
            <button 
              @click="toggleMobileMenu" 
              class="p-2 rounded-lg text-slate-700 dark:text-slate-200 hover:bg-slate-100 dark:hover:bg-slate-800"
            >
              <span class="text-xl">☰</span>
            </button>
          </div>
        </div>

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
            class="md:hidden fixed inset-y-0 left-0 z-50 w-72 bg-white dark:bg-slate-900 border-r border-slate-200 dark:border-slate-800 p-6 flex flex-col justify-between shadow-2xl"
          >
            <div>
              <div class="flex items-center justify-between pb-6 border-b border-slate-200 dark:border-slate-800 mb-6">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-xl flex items-center justify-center text-emerald-400 bg-emerald-500/10">
                    <NIcon size="20"><span>📡</span></NIcon>
                  </div>
                  <span class="font-bold text-lg text-slate-900 dark:text-white">TruthRelay</span>
                </div>
                <button @click="closeMobileMenu" class="text-slate-400 text-xl font-bold p-1">✕</button>
              </div>

              <nav class="space-y-2">
                <RouterLink 
                  v-for="item in menuOptions" 
                  :key="item.key" 
                  :to="item.key"
                  @click="closeMobileMenu"
                  class="flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-semibold transition-all text-slate-600 dark:text-slate-400"
                  active-class="!text-emerald-600 dark:!text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10"
                >
                  <span class="text-lg">{{ item.icon }}</span>
                  <span>{{ item.label }}</span>
                </RouterLink>
              </nav>
            </div>

            <div class="pt-6 border-t border-slate-200 dark:border-slate-800">
              <span class="flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
                <span class="h-2 w-2 rounded-full bg-emerald-500"></span>
                Relay Active
              </span>
            </div>
          </aside>
        </transition>

        <!-- Main Content Area (offset by sidebar on desktop, header on mobile) -->
        <main class="flex-1 md:pl-64 pt-16 md:pt-0 w-full min-h-screen p-4 sm:p-6 lg:p-8">
          <RouterView v-slot="{ Component }">
            <transition name="fade" mode="out-in">
              <component :is="Component" />
            </transition>
          </RouterView>
        </main>

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