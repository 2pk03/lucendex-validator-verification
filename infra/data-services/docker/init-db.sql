-- Lucendex Database Initialization
-- This script runs automatically when PostgreSQL container first starts
-- It sets up schemas, roles, and applies all migrations

\echo 'Initializing Lucendex database...'

-- Create schemas
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS metering;

\echo '✓ Schemas created'

-- Create audit trigger function (used by all tables)
CREATE OR REPLACE FUNCTION core.audit_trigger_func()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'INSERT') THEN
        NEW.created_at = COALESCE(NEW.created_at, now());
        NEW.updated_at = now();
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        NEW.updated_at = now();
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

\echo '✓ Audit function created'

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

\echo '✓ Extensions enabled'

-- Create schema_migrations tracking table
CREATE TABLE IF NOT EXISTS core.schema_migrations (
    version INT PRIMARY KEY,
    name TEXT NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

\echo '✓ Migration tracking table created'

-- Create roles if they don't exist
-- Note: passwords will be set via ALTER ROLE by deployment script
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'indexer_rw') THEN
        CREATE ROLE indexer_rw LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'router_ro') THEN
        CREATE ROLE router_ro LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'api_ro') THEN
        CREATE ROLE api_ro LOGIN;
    END IF;
END
$$;

\echo '✓ Roles created'

-- Grant schema permissions to roles
GRANT USAGE ON SCHEMA core TO indexer_rw;
GRANT CREATE ON SCHEMA core TO indexer_rw;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA core TO indexer_rw;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA core TO indexer_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT ALL ON TABLES TO indexer_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT ALL ON SEQUENCES TO indexer_rw;

-- Read-only permissions for router and API
GRANT USAGE ON SCHEMA core TO router_ro, api_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA core TO router_ro, api_ro;
ALTER DEFAULT PRIVILEGES IN SCHEMA core GRANT SELECT ON TABLES TO router_ro, api_ro;

\echo '✓ Permissions granted'

-- Note: Role creation with passwords must be done via environment variables
-- The roles (indexer_rw, router_ro, api_ro) are created by the deployment script
-- using the passwords from .env file

\echo 'Database initialization complete'
\echo 'Migrations will auto-run on indexer startup'
