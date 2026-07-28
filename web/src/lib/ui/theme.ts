import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

type Theme = 'dark' | 'light';

const STORAGE_KEY = 'truthrelay.theme';

function readInitial(): Theme {
  if (typeof window === 'undefined') return 'dark';
  const stored = window.localStorage.getItem(STORAGE_KEY);
  if (stored === 'dark' || stored === 'light') return stored;
  return window.matchMedia?.('(prefers-color-scheme: light)').matches
    ? 'light'
    : 'dark';
}

/**
 * Single source of truth for the active colour theme.
 * Keeps `<html class="dark">` in sync so Tailwind's class-based dark mode
 * picks up every utility on the page.
 */
export const useThemeStore = defineStore('theme', () => {
  const theme = ref<Theme>(readInitial());

  function apply(next: Theme) {
    if (typeof document === 'undefined') return;
    document.documentElement.classList.toggle('dark', next === 'dark');
    document.documentElement.style.colorScheme = next;
  }

  function toggle() {
    theme.value = theme.value === 'dark' ? 'light' : 'dark';
  }

  apply(theme.value);

  watch(theme, (next) => {
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(STORAGE_KEY, next);
    }
    apply(next);
  });

  return { theme, toggle };
});