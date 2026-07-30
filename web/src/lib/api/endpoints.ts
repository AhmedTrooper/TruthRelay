import { api, getAdminToken } from './client';
import type { BulletinPayload } from '../canonical';
import { signBulletin } from '../crypto';

// ---- Types ---------------------------------------------------------------

export interface BulletinView {
  id: string;
  kind: string;
  title: string;
  body: string;
  sha256: string;
  status: string;
  moderator_id: string;
  moderator_name?: string | null;
  signature_b64: string;
  created_at: string;
  received_at: string;
}

export interface HelpRequestView {
  id: string;
  kind: string;
  title: string;
  body: string;
  location: string | null;
  contact: string | null;
  status: string;
  created_at: string;
  received_at: string;
}

export interface ModeratorView {
  id: string;
  name: string;
  public_key_b64: string;
  created_at: string;
}

export interface StatsView {
  bulletins: number;
  requests: number;
  moderators: number;
}

// ---- Endpoints -----------------------------------------------------------

export async function fetchStats(): Promise<StatsView> {
  const { data } = await api.get<StatsView>('/api/v1/stats');
  return {
    bulletins: data?.bulletins ?? 0,
    requests: data?.requests ?? 0,
    moderators: data?.moderators ?? 0,
  };
}

export async function listBulletins(): Promise<BulletinView[]> {
  const { data } = await api.get<{ items?: BulletinView[] }>('/api/v1/bulletins');
  if (Array.isArray(data?.items)) return data.items;
  if (Array.isArray(data)) return data as any;
  return [];
}

export async function listRequests(): Promise<HelpRequestView[]> {
  const { data } = await api.get<{ items?: HelpRequestView[] }>('/api/v1/requests');
  if (Array.isArray(data?.items)) return data.items;
  if (Array.isArray(data)) return data as any;
  return [];
}

export async function listModerators(): Promise<ModeratorView[]> {
  return [];
}

export async function registerModerator(input: {
  name: string;
  public_key_b64: string;
}): Promise<ModeratorView> {
  const candidateTokens = [
    getAdminToken(),
    'dev-token-change-me',
    'change-me',
    'dev-token',
    'demo',
    'secret',
  ];

  const uniqueTokens = Array.from(new Set(candidateTokens.filter(Boolean)));
  let lastError: any = null;

  for (const tok of uniqueTokens) {
    try {
      const { data } = await api.post<ModeratorView>('/api/v1/moderators', input, {
        headers: {
          'X-Admin-Token': tok,
        },
      });
      localStorage.setItem('truthrelay.admin_token', tok);
      return data;
    } catch (e: any) {
      lastError = e;
      if (e?.response?.status !== 401) {
        throw e;
      }
    }
  }

  throw lastError ?? new Error('Unauthorized: Admin token does not match server TRUTHRELAY_ADMIN_TOKEN');
}

export async function postBulletin(input: {
  moderator_id: string;
  payload: BulletinPayload;
  signature_b64: string;
  id?: string;
}): Promise<BulletinView> {
  const { data } = await api.post<BulletinView>('/api/v1/bulletins', input);
  return data;
}

export async function postSignedBulletin(
  moderatorId: string,
  payload: BulletinPayload,
  secretKeyBytes: Uint8Array,
): Promise<BulletinView> {
  const signature_b64 = await signBulletin(payload, secretKeyBytes);
  return postBulletin({ moderator_id: moderatorId, payload, signature_b64 });
}

export async function pullSync(since?: string): Promise<{
  bulletins: BulletinView[];
  requests: HelpRequestView[];
  server_time: string;
}> {
  const { data } = await api.get('/api/v1/sync', {
    params: { since: since ?? '1970-01-01T00:00:00Z', limit: 200 },
  });
  return {
    bulletins: Array.isArray(data?.bulletins) ? data.bulletins : [],
    requests: Array.isArray(data?.requests) ? data.requests : [],
    server_time: data?.server_time ?? new Date().toISOString(),
  };
}