import { defineStore } from 'pinia';
import { ref } from 'vue';
import { fetchStats, type StatsView } from '../../lib/api/endpoints';

export const useDashboardStore = defineStore('dashboard', () => {
  const stats = ref<StatsView | null>(null);
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function refresh() {
    loading.value = true;
    error.value = null;
    try {
      stats.value = await fetchStats();
    } catch (e: any) {
      error.value = e?.message ?? String(e);
    } finally {
      loading.value = false;
    }
  }

  return { stats, loading, error, refresh };
});