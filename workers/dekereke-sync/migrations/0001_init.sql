-- Migration 0001: initial engine schema.
--
-- MIGRATIONS ARE STRICTLY ADDITIVE (flextext ops rule): never rename,
-- retype or drop what shipped — old clients must keep working. New needs
-- get new columns/tables in a new numbered file.

-- One registered Dekereke database (metadata only — content lives in the
-- owner's git repo and blob storage).
CREATE TABLE databases (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  owner_install_id TEXT NOT NULL,
  created_at TEXT NOT NULL
);

-- One enrolled app installation (Companion or phone). Clients mint their
-- own id + secret locally BEFORE first contact (idempotent retry); the
-- server only ever stores the secret's SHA-256.
CREATE TABLE installs (
  id TEXT PRIMARY KEY,
  database_id TEXT NOT NULL,
  role TEXT NOT NULL,            -- 'owner' | 'colleague' | 'phone'
  status TEXT NOT NULL,          -- 'pending' | 'approved' | 'revoked'
  secret_hash TEXT NOT NULL,
  pubkey TEXT NOT NULL DEFAULT '',
  display_name TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL
);
CREATE INDEX idx_installs_database ON installs(database_id);

-- One-time invite links (secret travels in the URL fragment, QR-able).
CREATE TABLE invites (
  id TEXT PRIMARY KEY,
  database_id TEXT NOT NULL,
  role TEXT NOT NULL,
  secret_hash TEXT NOT NULL,
  created_at TEXT NOT NULL,
  expires_at TEXT,
  claimed_by_install_id TEXT,
  claimed_at TEXT
);
CREATE INDEX idx_invites_database ON invites(database_id);

-- Two-lane relay state per install (flextext desired/reported pattern):
-- the researcher writes only `desired`, the device writes only `reported`;
-- both lanes advance by CAS on their rev.
CREATE TABLE instances (
  install_id TEXT PRIMARY KEY,
  desired_rev INTEGER NOT NULL DEFAULT 0,
  desired_blob TEXT NOT NULL DEFAULT '',
  reported_rev INTEGER NOT NULL DEFAULT 0,
  reported_blob TEXT NOT NULL DEFAULT '',
  updated_at TEXT NOT NULL
);
