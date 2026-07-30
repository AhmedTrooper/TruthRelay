import axios from 'axios';

const baseURL = (import.meta.env.VITE_API_URL as string | undefined) ?? 'http://localhost:8080';

export const api = axios.create({
  baseURL,
  timeout: 10000,
  headers: { 'Content-Type': 'application/json' },
});

// Default admin token (must match TRUTHRELAY_ADMIN_TOKEN on the server).
export function getAdminToken(): string {
  return (
    localStorage.getItem('truthrelay.admin_token') ||
    (import.meta.env.VITE_ADMIN_TOKEN as string | undefined) ||
    'dev-token-change-me'
  );
}

export const ADMIN_TOKEN = getAdminToken();

api.interceptors.request.use((cfg) => {
  // Attach admin token automatically for /moderators writes if not already provided.
  if (cfg.method?.toLowerCase() === 'post' && cfg.url?.endsWith('/moderators')) {
    if (!cfg.headers.get('X-Admin-Token')) {
      cfg.headers.set('X-Admin-Token', getAdminToken());
    }
  }
  return cfg;
});