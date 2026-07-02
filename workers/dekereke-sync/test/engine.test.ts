import { createHash, randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { Miniflare } from 'miniflare';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';

/** A client-minted credential, exactly as the apps will mint them. */
function mintInstall(name = 'Test Device') {
  const id = randomBytes(12).toString('base64url');
  const secret = randomBytes(18).toString('base64url');
  return {
    id,
    secret,
    auth: `Bearer ${id}:${secret}`,
    body: {
      id,
      secretHash: createHash('sha256').update(secret).digest('hex'),
      pubkey: 'test-pubkey',
      displayName: name,
    },
  };
}

let mf: Miniflare;

beforeAll(async () => {
  mf = new Miniflare({
    modules: true,
    scriptPath: 'dist/index.mjs',
    d1Databases: { DB: 'test-db' },
  });
});

afterAll(async () => {
  await mf.dispose();
});

beforeEach(async () => {
  // Fresh schema per test: drop and re-apply the migration.
  const db = await mf.getD1Database('DB');
  for (const table of ['databases', 'installs', 'invites', 'instances']) {
    await db.prepare(`DROP TABLE IF EXISTS ${table}`).run();
  }
  const sql = readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8');
  // Strip -- comments BEFORE splitting: comment prose may contain ';'.
  for (const statement of sql
    .replace(/^\s*--.*$/gm, '')
    .split(';')
    .map((s) => s.trim())
    .filter((s) => s.length > 0)) {
    await db.prepare(statement).run();
  }
});

async function call(
  method: string,
  path: string,
  options: { auth?: string; body?: unknown } = {},
): Promise<{ status: number; body: any }> {
  const response = await mf.dispatchFetch(`http://engine.local${path}`, {
    method,
    headers: {
      ...(options.auth ? { authorization: options.auth } : {}),
      ...(options.body !== undefined ? { 'content-type': 'application/json' } : {}),
    },
    ...(options.body !== undefined ? { body: JSON.stringify(options.body) } : {}),
  });
  const text = await response.text();
  return { status: response.status, body: text ? JSON.parse(text) : null };
}

/** Bootstraps a database with an owner install; returns both. */
async function bootstrap() {
  const owner = mintInstall('Owner PC');
  const created = await call('POST', '/v1/databases', {
    body: { name: 'Fayu', install: owner.body },
  });
  expect(created.status).toBe(201);
  return { owner, databaseId: created.body.databaseId as string };
}

/** Full enrollment of a new install via a fresh invite. */
async function enroll(owner: ReturnType<typeof mintInstall>, databaseId: string, role = 'colleague') {
  const invite = await call('POST', `/v1/databases/${databaseId}/invites`, {
    auth: owner.auth,
    body: { role },
  });
  expect(invite.status).toBe(201);
  const device = mintInstall('Enrolled Device');
  const claim = await call('POST', '/v1/claim', {
    body: { inviteId: invite.body.inviteId, inviteSecret: invite.body.secret, install: device.body },
  });
  expect(claim.status).toBe(201);
  return { device, invite: invite.body };
}

describe('health', () => {
  it('responds without auth', async () => {
    const res = await call('GET', '/v1/health');
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });
});

describe('database bootstrap', () => {
  it('creates database + approved owner install', async () => {
    const { owner } = await bootstrap();
    const status = await call('GET', `/v1/installs/${owner.body.id}`, { auth: owner.auth });
    expect(status.status).toBe(200);
    expect(status.body).toMatchObject({ status: 'approved', role: 'owner' });
  });

  it('is idempotent for the exact same install (crash retry)', async () => {
    const owner = mintInstall();
    const first = await call('POST', '/v1/databases', {
      body: { name: 'Fayu', install: owner.body },
    });
    const retry = await call('POST', '/v1/databases', {
      body: { name: 'Fayu', install: owner.body },
    });
    expect(retry.status).toBe(200);
    expect(retry.body.databaseId).toBe(first.body.databaseId);
  });

  it('rejects an id collision with a different secret', async () => {
    const owner = mintInstall();
    await call('POST', '/v1/databases', { body: { name: 'A', install: owner.body } });
    const imposter = { ...owner.body, secretHash: createHash('sha256').update('x').digest('hex') };
    const res = await call('POST', '/v1/databases', { body: { name: 'B', install: imposter } });
    expect(res.status).toBe(409);
  });

  it('validates the install shape', async () => {
    const res = await call('POST', '/v1/databases', {
      body: { name: 'A', install: { id: 'short', secretHash: 'nope' } },
    });
    expect(res.status).toBe(400);
  });
});

describe('invites and enrollment', () => {
  it('owner invites, device claims once, owner approves', async () => {
    const { owner, databaseId } = await bootstrap();
    const { device } = await enroll(owner, databaseId);

    const pending = await call('GET', `/v1/installs/${device.body.id}`, { auth: device.auth });
    expect(pending.body.status).toBe('pending');

    const approve = await call(
      'POST',
      `/v1/databases/${databaseId}/installs/${device.body.id}/approve`,
      { auth: owner.auth },
    );
    expect(approve.status).toBe(200);
    expect(approve.body.status).toBe('approved');

    const approved = await call('GET', `/v1/installs/${device.body.id}`, { auth: device.auth });
    expect(approved.body.status).toBe('approved');
  });

  it('non-owners cannot mint invites or approve', async () => {
    const { owner, databaseId } = await bootstrap();
    const { device } = await enroll(owner, databaseId);
    const invite = await call('POST', `/v1/databases/${databaseId}/invites`, {
      auth: device.auth,
      body: {},
    });
    expect(invite.status).toBe(403);
  });

  it('an invite is one-time: second claimant gets 409, same claimant may retry', async () => {
    const { owner, databaseId } = await bootstrap();
    const invite = await call('POST', `/v1/databases/${databaseId}/invites`, {
      auth: owner.auth,
      body: {},
    });
    const first = mintInstall('First');
    const claim1 = await call('POST', '/v1/claim', {
      body: { inviteId: invite.body.inviteId, inviteSecret: invite.body.secret, install: first.body },
    });
    expect(claim1.status).toBe(201);

    // Idempotent retry by the SAME install.
    const retry = await call('POST', '/v1/claim', {
      body: { inviteId: invite.body.inviteId, inviteSecret: invite.body.secret, install: first.body },
    });
    expect(retry.status).toBe(200);
    expect(retry.body.databaseId).toBe(databaseId);

    // A different install is refused.
    const second = mintInstall('Second');
    const claim2 = await call('POST', '/v1/claim', {
      body: { inviteId: invite.body.inviteId, inviteSecret: invite.body.secret, install: second.body },
    });
    expect(claim2.status).toBe(409);
  });

  it('claims with a wrong secret look like a missing invite', async () => {
    const { owner, databaseId } = await bootstrap();
    const invite = await call('POST', `/v1/databases/${databaseId}/invites`, {
      auth: owner.auth,
      body: {},
    });
    const device = mintInstall();
    const res = await call('POST', '/v1/claim', {
      body: { inviteId: invite.body.inviteId, inviteSecret: 'wrong', install: device.body },
    });
    expect(res.status).toBe(404);
  });
});

describe('two-lane relay', () => {
  async function approvedDevice() {
    const { owner, databaseId } = await bootstrap();
    const { device } = await enroll(owner, databaseId, 'phone');
    await call('POST', `/v1/databases/${databaseId}/installs/${device.body.id}/approve`, {
      auth: owner.auth,
    });
    return { owner, device, databaseId };
  }

  it('owner writes desired, device polls it; 204 when unchanged', async () => {
    const { owner, device } = await approvedDevice();

    const write = await call('PUT', `/v1/instances/${device.body.id}/desired`, {
      auth: owner.auth,
      body: { expectedRev: 0, blob: '{"task":"t1"}' },
    });
    expect(write.status).toBe(200);
    expect(write.body.rev).toBe(1);

    const poll = await call('GET', `/v1/instances/${device.body.id}?since=0`, {
      auth: device.auth,
    });
    expect(poll.status).toBe(200);
    expect(poll.body).toEqual({ rev: 1, blob: '{"task":"t1"}' });

    const unchanged = await call('GET', `/v1/instances/${device.body.id}?since=1`, {
      auth: device.auth,
    });
    expect(unchanged.status).toBe(204);
  });

  it('device writes reported, owner reads it', async () => {
    const { owner, device } = await approvedDevice();
    const write = await call('PUT', `/v1/instances/${device.body.id}/reported`, {
      auth: device.auth,
      body: { expectedRev: 0, blob: '{"done":3}' },
    });
    expect(write.status).toBe(200);
    const poll = await call('GET', `/v1/instances/${device.body.id}?since=0`, {
      auth: owner.auth,
    });
    expect(poll.status).toBe(200);
    expect(poll.body).toEqual({ rev: 1, blob: '{"done":3}' });
  });

  it('CAS conflicts return 409 with the current rev', async () => {
    const { owner, device } = await approvedDevice();
    await call('PUT', `/v1/instances/${device.body.id}/desired`, {
      auth: owner.auth,
      body: { expectedRev: 0, blob: 'a' },
    });
    const stale = await call('PUT', `/v1/instances/${device.body.id}/desired`, {
      auth: owner.auth,
      body: { expectedRev: 0, blob: 'b' },
    });
    expect(stale.status).toBe(409);
    expect(stale.body.currentRev).toBe(1);
  });

  it('lane ownership is enforced both ways', async () => {
    const { owner, device } = await approvedDevice();
    const deviceWritesDesired = await call('PUT', `/v1/instances/${device.body.id}/desired`, {
      auth: device.auth,
      body: { expectedRev: 0, blob: 'x' },
    });
    expect(deviceWritesDesired.status).toBe(403);
    const ownerWritesReported = await call('PUT', `/v1/instances/${device.body.id}/reported`, {
      auth: owner.auth,
      body: { expectedRev: 0, blob: 'x' },
    });
    expect(ownerWritesReported.status).toBe(403);
  });

  it('pending installs cannot use the relay yet', async () => {
    const { owner, databaseId } = await bootstrap();
    const { device } = await enroll(owner, databaseId, 'phone'); // NOT approved
    const poll = await call('GET', `/v1/instances/${device.body.id}?since=0`, {
      auth: device.auth,
    });
    expect(poll.status).toBe(403);
    const write = await call('PUT', `/v1/instances/${device.body.id}/reported`, {
      auth: device.auth,
      body: { expectedRev: 0, blob: 'x' },
    });
    expect(write.status).toBe(403);
  });
});

describe('auth', () => {
  it('rejects missing and bogus credentials', async () => {
    const { owner, databaseId } = await bootstrap();
    expect((await call('POST', `/v1/databases/${databaseId}/invites`, { body: {} })).status).toBe(401);
    expect(
      (
        await call('POST', `/v1/databases/${databaseId}/invites`, {
          auth: `Bearer ${owner.body.id}:wrong-secret`,
          body: {},
        })
      ).status,
    ).toBe(401);
  });

  it('unknown routes: 401 without credentials (no route leaking), 404 with',
    async () => {
      expect((await call('GET', '/v1/nope')).status).toBe(401);
      const { owner } = await bootstrap();
      expect((await call('GET', '/v1/nope', { auth: owner.auth })).status).toBe(404);
    });
});
