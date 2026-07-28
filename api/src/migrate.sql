-- TruthRelay SQLite schema. Applied at server startup via include_str!().

PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS moderators (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    public_key  BLOB NOT NULL,
    created_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bulletins (
    id           TEXT PRIMARY KEY,
    kind         TEXT NOT NULL,
    title        TEXT NOT NULL,
    body         TEXT NOT NULL,
    sha256       TEXT NOT NULL UNIQUE,
    status       TEXT NOT NULL DEFAULT 'Active',
    moderator_id TEXT NOT NULL REFERENCES moderators(id),
    signature    BLOB NOT NULL,
    payload_json TEXT NOT NULL,
    created_at   TEXT NOT NULL,
    received_at  TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_bulletins_received ON bulletins(received_at);
CREATE INDEX IF NOT EXISTS idx_bulletins_status   ON bulletins(status);

CREATE TABLE IF NOT EXISTS help_requests (
    id          TEXT PRIMARY KEY,
    kind        TEXT NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL,
    location    TEXT,
    contact     TEXT,
    status      TEXT NOT NULL DEFAULT 'Active',
    created_at  TEXT NOT NULL,
    received_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_requests_received ON help_requests(received_at);

CREATE TABLE IF NOT EXISTS seen_packets (
    packet_id   TEXT NOT NULL,
    peer_addr   TEXT NOT NULL,
    first_seen_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (packet_id, peer_addr)
);