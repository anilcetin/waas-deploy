-- 01-extensions.sql — Postgres extensions required by the WaaS platform.
-- Mounted into /docker-entrypoint-initdb.d, runs once on first container start.
-- EF Core will rely on:
--   gen_random_uuid()        — pgcrypto (default random UUID source)
--   uuid_generate_v4()       — uuid-ossp (legacy/compat calls)
-- Sprint 3 will add citext / pg_trgm / row-level-security helpers as needed.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";