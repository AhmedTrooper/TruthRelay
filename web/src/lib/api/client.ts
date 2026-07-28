import axios from 'axios';

const baseURL = (import.meta.env.VITE_API_URL as string | undefined) ?? 'http://localhost:8080';

export const api = axios.create({
  baseURL,
  timeout: 10000,
  headers: { 'Content-Type': 'application/json' },
});

// Default admin token (must match TRUTHRELAY_ADMIN_TOKEN on the server).
export const ADMIN_TOKEN =
  (import.meta.env.VITE_ADMIN_TOKEN as string | undefined) ?? 'dev-token';

api.interceptors.request.use((cfg) => {
  // Attach admin token automatically for /moderators writes.
  if (cfg.method?.toLowerCase() === 'post' && cfg.url?.endsWith('/moderators')) {
    cfg.headers.set('X-Admin-Token', ADMIN_TOKEN);
  }
  return cfg;
});