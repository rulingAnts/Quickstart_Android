/**
 * Dekereke Companion Suite engine (decision D5): enrollment, metadata and
 * the two-lane relay ONLY — no user blobs, nothing that scales with users'
 * data. Patterns transplanted from flextext-r2-worker (see
 * docs/HANDOFF.md): client-minted credentials, atomic one-time invite
 * claims with idempotent retry, owner approval step, CAS on rev columns,
 * 4xx never retried client-side.
 *
 * All requests/responses are JSON. Authentication:
 *   Authorization: Bearer <installId>:<installSecret>
 * The server stores only SHA-256(secret).
 */

export interface Env {
  DB: D1Database;
}

type Role = 'owner' | 'colleague' | 'phone';

interface InstallRow {
  id: string;
  database_id: string;
  role: Role;
  status: 'pending' | 'approved' | 'revoked';
  secret_hash: string;
  pubkey: string;
  display_name: string;
}

const HEX_64 = /^[0-9a-f]{64}$/;
const ID_SHAPE = /^[A-Za-z0-9_-]{8,128}$/;

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function badRequest(message: string): Response {
  return json(400, { error: message });
}

/** Random URL-safe token (ids, invite secrets). */
function randomToken(bytes = 18): string {
  const raw = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...raw)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}

async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  try {
    const body = (await request.json()) as unknown;
    return typeof body === 'object' && body !== null ? (body as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/** Resolves the calling install from the Authorization header. */
async function authenticate(request: Request, env: Env): Promise<InstallRow | null> {
  const header = request.headers.get('authorization') ?? '';
  const match = /^Bearer\s+([^:]+):(.+)$/.exec(header);
  if (!match) return null;
  const [, id, secret] = match;
  const row = await env.DB.prepare('SELECT * FROM installs WHERE id = ?')
    .bind(id)
    .first<InstallRow>();
  if (!row) return null;
  if ((await sha256Hex(secret!)) !== row.secret_hash) return null;
  return row;
}

interface InstallInput {
  id: string;
  secretHash: string;
  pubkey: string;
  displayName: string;
}

function parseInstallInput(value: unknown): InstallInput | string {
  if (typeof value !== 'object' || value === null) return 'install object is required';
  const install = value as Record<string, unknown>;
  const id = install.id;
  const secretHash = install.secretHash;
  if (typeof id !== 'string' || !ID_SHAPE.test(id)) {
    return 'install.id must be 8-128 URL-safe characters (client-minted)';
  }
  if (typeof secretHash !== 'string' || !HEX_64.test(secretHash)) {
    return 'install.secretHash must be lowercase hex SHA-256 of the client-minted secret';
  }
  return {
    id,
    secretHash,
    pubkey: typeof install.pubkey === 'string' ? install.pubkey : '',
    displayName: typeof install.displayName === 'string' ? install.displayName : '',
  };
}

const now = () => new Date().toISOString();

/** POST /v1/databases — owner bootstrap: register database + owner install. */
async function createDatabase(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  if (!body) return badRequest('JSON body required');
  const name = body.name;
  if (typeof name !== 'string' || name.length === 0 || name.length > 200) {
    return badRequest('name is required');
  }
  const install = parseInstallInput(body.install);
  if (typeof install === 'string') return badRequest(install);

  const existing = await env.DB.prepare('SELECT * FROM installs WHERE id = ?')
    .bind(install.id)
    .first<InstallRow>();
  if (existing) {
    // Idempotent retry of the same bootstrap (crash between POST and
    // persist on the client side): same install, same secret → same result.
    if (existing.secret_hash === install.secretHash && existing.role === 'owner') {
      return json(200, { databaseId: existing.database_id, installId: existing.id });
    }
    return json(409, { error: 'install id already exists' });
  }

  const databaseId = randomToken();
  const createdAt = now();
  await env.DB.batch([
    env.DB.prepare(
      'INSERT INTO databases (id, name, owner_install_id, created_at) VALUES (?, ?, ?, ?)',
    ).bind(databaseId, name, install.id, createdAt),
    env.DB.prepare(
      `INSERT INTO installs (id, database_id, role, status, secret_hash, pubkey, display_name, created_at)
       VALUES (?, ?, 'owner', 'approved', ?, ?, ?, ?)`,
    ).bind(install.id, databaseId, install.secretHash, install.pubkey, install.displayName, createdAt),
    env.DB.prepare(
      'INSERT INTO instances (install_id, updated_at) VALUES (?, ?)',
    ).bind(install.id, createdAt),
  ]);
  return json(201, { databaseId, installId: install.id });
}

/** POST /v1/databases/:dbId/invites — owner mints a one-time invite. */
async function createInvite(
  request: Request,
  env: Env,
  caller: InstallRow,
  databaseId: string,
): Promise<Response> {
  if (caller.role !== 'owner' || caller.database_id !== databaseId) {
    return json(403, { error: 'only the database owner can create invites' });
  }
  const body = (await readJson(request)) ?? {};
  const role = body.role ?? 'colleague';
  if (role !== 'colleague' && role !== 'phone') {
    return badRequest("role must be 'colleague' or 'phone'");
  }
  const inviteId = randomToken(9);
  const secret = randomToken();
  await env.DB.prepare(
    'INSERT INTO invites (id, database_id, role, secret_hash, created_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(inviteId, databaseId, role, await sha256Hex(secret), now())
    .run();
  // The secret is returned exactly once; clients put it in a URL fragment.
  return json(201, { inviteId, secret, role });
}

/** POST /v1/claim — atomic one-time claim of an invite. */
async function claimInvite(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  if (!body) return badRequest('JSON body required');
  const inviteId = body.inviteId;
  const inviteSecret = body.inviteSecret;
  if (typeof inviteId !== 'string' || typeof inviteSecret !== 'string') {
    return badRequest('inviteId and inviteSecret are required');
  }
  const install = parseInstallInput(body.install);
  if (typeof install === 'string') return badRequest(install);

  const invite = await env.DB.prepare('SELECT * FROM invites WHERE id = ?')
    .bind(inviteId)
    .first<{
      id: string;
      database_id: string;
      role: Role;
      secret_hash: string;
      expires_at: string | null;
      claimed_by_install_id: string | null;
    }>();
  if (!invite || (await sha256Hex(inviteSecret)) !== invite.secret_hash) {
    return json(404, { error: 'invite not found' });
  }
  if (invite.expires_at !== null && invite.expires_at < now()) {
    return json(410, { error: 'invite expired' });
  }
  if (invite.claimed_by_install_id !== null) {
    // Idempotent retry: the SAME install re-claiming gets the same answer.
    if (invite.claimed_by_install_id === install.id) {
      return json(200, { databaseId: invite.database_id, role: invite.role, status: 'pending' });
    }
    return json(409, { error: 'invite already used' });
  }

  // Atomic one-time claim: only one racer's UPDATE matches the NULL guard.
  const claimed = await env.DB.prepare(
    'UPDATE invites SET claimed_by_install_id = ?, claimed_at = ? WHERE id = ? AND claimed_by_install_id IS NULL',
  )
    .bind(install.id, now(), inviteId)
    .run();
  if (claimed.meta.changes === 0) {
    return json(409, { error: 'invite already used' });
  }

  const createdAt = now();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO installs (id, database_id, role, status, secret_hash, pubkey, display_name, created_at)
       VALUES (?, ?, ?, 'pending', ?, ?, ?, ?)`,
    ).bind(install.id, invite.database_id, invite.role, install.secretHash, install.pubkey, install.displayName, createdAt),
    env.DB.prepare('INSERT INTO instances (install_id, updated_at) VALUES (?, ?)').bind(
      install.id,
      createdAt,
    ),
  ]);
  return json(201, { databaseId: invite.database_id, role: invite.role, status: 'pending' });
}

/** POST /v1/databases/:dbId/installs/:id/approve — owner approval step. */
async function approveInstall(
  env: Env,
  caller: InstallRow,
  databaseId: string,
  installId: string,
): Promise<Response> {
  if (caller.role !== 'owner' || caller.database_id !== databaseId) {
    return json(403, { error: 'only the database owner can approve installs' });
  }
  const result = await env.DB.prepare(
    "UPDATE installs SET status = 'approved' WHERE id = ? AND database_id = ? AND status = 'pending'",
  )
    .bind(installId, databaseId)
    .run();
  if (result.meta.changes === 0) {
    const row = await env.DB.prepare('SELECT status FROM installs WHERE id = ? AND database_id = ?')
      .bind(installId, databaseId)
      .first<{ status: string }>();
    if (!row) return json(404, { error: 'install not found' });
    return json(200, { status: row.status }); // idempotent re-approve
  }
  return json(200, { status: 'approved' });
}

/** GET /v1/installs/:id — an install polls its own enrollment status. */
function installStatus(caller: InstallRow, installId: string): Response {
  if (caller.id !== installId) return json(403, { error: 'not your install' });
  return json(200, {
    status: caller.status,
    role: caller.role,
    databaseId: caller.database_id,
  });
}

interface InstanceRow {
  install_id: string;
  desired_rev: number;
  desired_blob: string;
  reported_rev: number;
  reported_blob: string;
}

/** GET /v1/instances/:id?since=rev — poll the desired lane (204 unchanged). */
async function pollInstance(
  env: Env,
  caller: InstallRow,
  installId: string,
  since: number,
): Promise<Response> {
  const owns = caller.id === installId;
  const owner = caller.role === 'owner';
  if (!owns && !owner) return json(403, { error: 'forbidden' });
  if (!owns && owner) {
    const target = await env.DB.prepare('SELECT database_id FROM installs WHERE id = ?')
      .bind(installId)
      .first<{ database_id: string }>();
    if (!target || target.database_id !== caller.database_id) {
      return json(404, { error: 'install not found' });
    }
  }
  if (owns && caller.status !== 'approved') {
    return json(403, { error: `install is ${caller.status}` });
  }
  const row = await env.DB.prepare('SELECT * FROM instances WHERE install_id = ?')
    .bind(installId)
    .first<InstanceRow>();
  if (!row) return json(404, { error: 'instance not found' });
  const payload = owns
    ? { rev: row.desired_rev, blob: row.desired_blob }
    : { rev: row.reported_rev, blob: row.reported_blob };
  if (payload.rev <= since) return new Response(null, { status: 204 });
  return json(200, payload);
}

/**
 * PUT /v1/instances/:id/desired|reported — CAS write to one lane.
 * The researcher writes only `desired` (for installs of their database);
 * the device writes only its own `reported`. 409 → refetch and reapply.
 */
async function writeLane(
  request: Request,
  env: Env,
  caller: InstallRow,
  installId: string,
  lane: 'desired' | 'reported',
): Promise<Response> {
  if (lane === 'reported') {
    if (caller.id !== installId) return json(403, { error: 'reported lane is device-only' });
    if (caller.status !== 'approved') return json(403, { error: `install is ${caller.status}` });
  } else {
    if (caller.role !== 'owner') return json(403, { error: 'desired lane is owner-only' });
    const target = await env.DB.prepare('SELECT database_id FROM installs WHERE id = ?')
      .bind(installId)
      .first<{ database_id: string }>();
    if (!target || target.database_id !== caller.database_id) {
      return json(404, { error: 'install not found' });
    }
  }
  const body = await readJson(request);
  if (!body) return badRequest('JSON body required');
  const expectedRev = body.expectedRev;
  const blob = body.blob;
  if (typeof expectedRev !== 'number' || !Number.isInteger(expectedRev) || expectedRev < 0) {
    return badRequest('expectedRev must be a non-negative integer');
  }
  if (typeof blob !== 'string') return badRequest('blob must be a string');

  const result = await env.DB.prepare(
    `UPDATE instances SET ${lane}_rev = ?, ${lane}_blob = ?, updated_at = ?
     WHERE install_id = ? AND ${lane}_rev = ?`,
  )
    .bind(expectedRev + 1, blob, now(), installId, expectedRev)
    .run();
  if (result.meta.changes === 0) {
    const row = await env.DB.prepare(
      `SELECT ${lane}_rev AS rev FROM instances WHERE install_id = ?`,
    )
      .bind(installId)
      .first<{ rev: number }>();
    if (!row) return json(404, { error: 'instance not found' });
    return json(409, { error: 'revision conflict', currentRev: row.rev });
  }
  return json(200, { rev: expectedRev + 1 });
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '');
    const method = request.method;

    if (method === 'GET' && path === '/v1/health') {
      return json(200, { ok: true, service: 'dekereke-sync-engine' });
    }
    if (method === 'POST' && path === '/v1/databases') {
      return createDatabase(request, env);
    }
    if (method === 'POST' && path === '/v1/claim') {
      return claimInvite(request, env);
    }

    // Everything below requires a valid install credential.
    const caller = await authenticate(request, env);
    if (!caller) return json(401, { error: 'invalid credentials' });
    if (caller.status === 'revoked') return json(403, { error: 'install is revoked' });

    let match: RegExpExecArray | null;
    if (method === 'POST' && (match = /^\/v1\/databases\/([^/]+)\/invites$/.exec(path))) {
      return createInvite(request, env, caller, match[1]!);
    }
    if (
      method === 'POST' &&
      (match = /^\/v1\/databases\/([^/]+)\/installs\/([^/]+)\/approve$/.exec(path))
    ) {
      return approveInstall(env, caller, match[1]!, match[2]!);
    }
    if (method === 'GET' && (match = /^\/v1\/installs\/([^/]+)$/.exec(path))) {
      return installStatus(caller, match[1]!);
    }
    if (method === 'GET' && (match = /^\/v1\/instances\/([^/]+)$/.exec(path))) {
      const since = Number(url.searchParams.get('since') ?? '-1');
      return pollInstance(env, caller, match[1]!, Number.isFinite(since) ? since : -1);
    }
    if (method === 'PUT' && (match = /^\/v1\/instances\/([^/]+)\/desired$/.exec(path))) {
      return writeLane(request, env, caller, match[1]!, 'desired');
    }
    if (method === 'PUT' && (match = /^\/v1\/instances\/([^/]+)\/reported$/.exec(path))) {
      return writeLane(request, env, caller, match[1]!, 'reported');
    }

    return json(404, { error: 'not found' });
  },
} satisfies ExportedHandler<Env>;
