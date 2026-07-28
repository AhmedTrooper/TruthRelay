import { describe, it, expect, beforeEach, vi } from 'vitest';
import { setActivePinia, createPinia } from 'pinia';
import { useThemeStore } from './theme';

beforeEach(() => {
  localStorage.clear();
  document.documentElement.className = '';
  // Force the OS to NOT prefer light so the store starts in dark.
  if (!('matchMedia' in window) || (window as any).matchMedia?.mock) {
    Object.defineProperty(window, 'matchMedia', {
      configurable: true,
      value: vi.fn().mockImplementation((query: string) => ({
        matches: false,
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      })),
    });
  } else {
    vi.spyOn(window, 'matchMedia').mockImplementation((query: string) => ({
      matches: false,
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      dispatchEvent: () => false,
      onchange: null,
    }));
  }
  setActivePinia(createPinia());
});

describe('theme store', () => {
  it('defaults to dark when the OS prefers neither scheme', () => {
    const store = useThemeStore();
    expect(store.theme).toBe('dark');
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });

  it('toggles between dark and light, flipping html.dark', async () => {
    const store = useThemeStore();
    store.toggle();
    await new Promise((r) => setTimeout(r, 0));
    expect(store.theme).toBe('light');
    expect(document.documentElement.classList.contains('dark')).toBe(false);

    store.toggle();
    await new Promise((r) => setTimeout(r, 0));
    expect(store.theme).toBe('dark');
    expect(document.documentElement.classList.contains('dark')).toBe(true);
  });

  it('persists the chosen theme to localStorage', async () => {
    const store = useThemeStore();
    store.toggle();
    await new Promise((r) => setTimeout(r, 0));
    expect(localStorage.getItem('truthrelay.theme')).toBe('light');
  });
});