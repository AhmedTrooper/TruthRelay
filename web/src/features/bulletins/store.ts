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
      items.value = await listBulletins();
    } catch (e: any) {
      error.value = e?.message ?? String(e);
    } finally {
      loading.value = false;
    }
  }

  return { items, loading, error, refresh };
});