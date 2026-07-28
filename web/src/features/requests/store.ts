import { defineStore } from 'pinia';
import { ref } from 'vue';
import { listRequests, type HelpRequestView } from '../../lib/api/endpoints';

export const useRequestsStore = defineStore('requests', () => {
  const items = ref<HelpRequestView[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function refresh() {
    loading.value = true;
    error.value = null;
    try {
      items.value = await listRequests();
    } catch (e: any) {
      error.value = e?.message ?? String(e);
    } finally {
      loading.value = false;
    }
  }

  return { items, loading, error, refresh };
});