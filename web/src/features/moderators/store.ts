import { defineStore } from 'pinia';
import { ref } from 'vue';
import { registerModerator, type ModeratorView } from '../../lib/api/endpoints';

const LS_KEY = 'truthrelay.moderator';

interface StoredModerator {
  id: string;
  name: string;
  public_key_b64: string;
  secret_key_b64: string;
  created_at: string;
}

function loadStored(): StoredModerator | null {
  try {
    const raw = localStorage.getItem(LS_KEY);
    return raw ? (JSON.parse(raw) as StoredModerator) : null;
  } catch {
    return null;
  }
}

function saveStored(m: StoredModerator | null) {
  if (m) localStorage.setItem(LS_KEY, JSON.stringify(m));
  else localStorage.removeItem(LS_KEY);
}

export const useModeratorStore = defineStore('moderator', () => {
  const stored = ref<StoredModerator | null>(loadStored());
  const serverView = ref<ModeratorView | null>(null);
  const busy = ref(false);
  const error = ref<string | null>(null);

  function setFromKeygen(payload: {
    name: string;
    public_key_b64: string;
    secret_key_b64: string;
    created_at: string;
  }) {
    // Server will assign the id; store without it for now.
    stored.value = { id: '', ...payload };
    saveStored(stored.value);
  }

  async function register() {
    if (!stored.value) throw new Error('no keygen payload');
    busy.value = true;
    error.value = null;
    try {
      const view = await registerModerator({
        name: stored.value.name,
        public_key_b64: stored.value.public_key_b64,
      });
      serverView.value = view;
      stored.value = { ...stored.value, id: view.id };
      saveStored(stored.value);
      return view;
    } catch (e: any) {
      error.value = e?.message ?? String(e);
      throw e;
    } finally {
      busy.value = false;
    }
  }

  function clear() {
    stored.value = null;
    serverView.value = null;
    saveStored(null);
  }

  async function refresh() {
    // The relay does not yet expose a list-moderators endpoint; the
    // stored moderator is hydrated from localStorage on construction so
    // there is nothing to fetch here. Kept for view-mount symmetry with
    // the other stores.
  }

  return {
    stored,
    serverView,
    busy,
    error,
    setFromKeygen,
    register,
    clear,
    refresh,
  };
});