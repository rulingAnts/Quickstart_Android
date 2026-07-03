# dekereke-sync-engine

The Companion Suite's Cloudflare Worker (backlog #3, plan §3): the
**engine only**, per decision D5 — enrollment, metadata, keys/invites and
the two-lane relay. It stores **no user blobs** and proxies **no audio**;
nothing here scales with users' data. Owner storage (Google Drive /
owner-R2) is accessed by devices directly.

Patterns are transplanted from flextext-r2-worker (see
`docs/HANDOFF.md`): client-minted credentials persisted before first
contact, atomic one-time invite claims with idempotent retry, an owner
approval step, CAS on rev columns (409 → refetch and reapply), strictly
additive D1 migrations.

## API (v1)

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /v1/health` | — | liveness |
| `POST /v1/databases` | — | owner bootstrap: register database + owner install (idempotent for the same install) |
| `POST /v1/databases/:db/invites` | owner | mint a one-time invite (`{inviteId, secret}` returned exactly once) |
| `POST /v1/claim` | — | atomic one-time claim; same-install retry is idempotent; creates a `pending` install |
| `POST /v1/databases/:db/installs/:id/approve` | owner | approval step |
| `GET /v1/installs/:id` | self | poll own enrollment status |
| `GET /v1/instances/:id?since=rev` | self / owner | poll a lane (self sees `desired`, owner sees `reported`); `204` when unchanged |
| `PUT /v1/instances/:id/desired` | owner | CAS write, researcher lane |
| `PUT /v1/instances/:id/reported` | self (approved) | CAS write, device lane |

Auth: `Authorization: Bearer <installId>:<installSecret>`; the server
stores only SHA-256 of secrets (install and invite alike).

## Development

```sh
npm ci
npm run typecheck
npm test          # builds with esbuild, runs vitest against Miniflare + real D1
```

## Deploying (maintainer only)

One-time: `wrangler d1 create dekereke-sync`, paste the id into
`wrangler.toml`, then `wrangler d1 migrations apply dekereke-sync
--remote` and `wrangler deploy` (or wire the same into a GitHub Actions
job with a scoped `CLOUDFLARE_API_TOKEN` secret — deploys are
GitHub-Actions-only, per the flextext ops model). Keep `workers_dev`
alive alongside any custom domain so deployed clients never break.

## Migrations

Strictly additive: never rename, retype or drop what shipped. New needs
get a new numbered file in `migrations/`.
