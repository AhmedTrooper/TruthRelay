import { api } from './client';
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
  return data;
}

export async function listBulletins(): Promise<BulletinView[]> {
  const { data } = await api.get<{ items: BulletinView[] }>('/api/v1/bulletins');
  return data.items;
}

export async function listRequests(): Promise<HelpRequestView[]> {
  const { data } = await api.get<{ items: HelpRequestView[] }>('/api/v1/requests');
  return data.items;
}

export async function listModerators(): Promise<ModeratorView[]> {
  // The server doesn't expose a list endpoint, so we fetch by id from the
  // bulletin list (which embeds moderator_name). For v1 that's enough.
  return [];
}

export async function registerModerator(input: {
  name: string;
  public_key_b64: string;
}): Promise<ModeratorView> {
  const { data } = await api.post<ModeratorView>('/api/v1/moderators', input);
  return data;
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
  return data;
}