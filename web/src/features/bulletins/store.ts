import { defineStore } from 'pinia';
import { ref } from 'vue';
import { listBulletins, type BulletinView } from '../../lib/api/endpoints';

export const useBulletinsStore = defineStore('bulletins', () => {
  const items = ref<BulletinView[]>([]);
  const loading = ref(false);
  const error = ref<string | null>(null);

  async function refresh() {
    loading.value = true;
    error.value = null;
    try {
      const res = await listBulletins();
      items.value = Array.isArray(res) ? res : [];
    } catch (e: any) {
      error.value = e?.message ?? String(e);
      if (!Array.isArray(items.value)) {
        items.value = [];
      }
    } finally {
      loading.value = false;
    }
  }

  return { items, loading, error, refresh };
});