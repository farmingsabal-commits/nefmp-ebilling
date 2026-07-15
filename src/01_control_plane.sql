-- =====================================================================================
-- NEFMP — Nepal Enterprise Financial Management Platform
-- SECTION 1: CONTROL PLANE DATABASE
-- Lives OUTSIDE every tenant database. One instance platform-wide.
-- Responsible for: Global Identity, Tenant Registry, Subscription/Licensing,
-- Connection Routing metadata, Platform-level Administration.
-- Database engine: PostgreSQL 15+
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS control_plane;
SET search_path TO control_plane, public;

-- -------------------------------------------------------------------------------------
-- 1.1 GLOBAL IDENTITY
-- One record per human being who can ever log into NEFMP, regardless of how many
-- tenants/organizations they belong to. Authentication happens ONLY at this layer.
-- -------------------------------------------------------------------------------------

CREATE TABLE global_identity (
    global_user_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email                   CITEXT NOT NULL UNIQUE,          -- platform-wide unique
    mobile_number           VARCHAR(20) UNIQUE,
    password_hash           TEXT,                             -- NULL if SSO-only account
    password_algo           VARCHAR(20) DEFAULT 'ARGON2ID',
    password_last_changed_at TIMESTAMPTZ,
    password_history        JSONB DEFAULT '[]',               -- last N hashes, for reuse prevention
    full_name               VARCHAR(200) NOT NULL,
    photo_url               TEXT,
    preferred_language      VARCHAR(10) DEFAULT 'en',          -- en, ne
    default_time_zone       VARCHAR(50) DEFAULT 'Asia/Kathmandu',
    mfa_enabled              BOOLEAN NOT NULL DEFAULT FALSE,
    mfa_method               VARCHAR(20),                      -- TOTP, SMS_OTP, EMAIL_OTP
    mfa_secret_encrypted     TEXT,
    status                   VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, LOCKED, DISABLED
    failed_login_attempts    INT NOT NULL DEFAULT 0,
    locked_until             TIMESTAMPTZ,
    is_platform_admin        BOOLEAN NOT NULL DEFAULT FALSE,   -- System Administrator (§11)
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE identity_external_login (
    external_login_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    global_user_id          UUID NOT NULL REFERENCES global_identity(global_user_id) ON DELETE CASCADE,
    provider                VARCHAR(30) NOT NULL,   -- GOOGLE, MICROSOFT, APPLE, SAML, LDAP
    provider_subject_id     VARCHAR(255) NOT NULL,  -- external unique id (sub claim, DN, etc.)
    provider_metadata       JSONB,
    linked_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (provider, provider_subject_id)
);

CREATE TABLE identity_trusted_device (
    device_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    global_user_id          UUID NOT NULL REFERENCES global_identity(global_user_id) ON DELETE CASCADE,
    device_fingerprint      VARCHAR(255) NOT NULL,
    device_name             VARCHAR(200),
    last_ip                 INET,
    last_seen_at            TIMESTAMPTZ,
    trusted_until           TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (global_user_id, device_fingerprint)
);

CREATE TABLE identity_login_history (
    login_id                BIGSERIAL PRIMARY KEY,
    global_user_id          UUID NOT NULL REFERENCES global_identity(global_user_id),
    login_at                TIMESTAMPTZ NOT NULL DEFAULT now(),
    ip_address              INET,
    device_fingerprint      VARCHAR(255),
    user_agent              TEXT,
    login_result            VARCHAR(20) NOT NULL,   -- SUCCESS, FAILED_PASSWORD, FAILED_MFA, LOCKED
    tenant_id               UUID                     -- NULL if platform-level login only
);
CREATE INDEX idx_login_history_user ON identity_login_history (global_user_id, login_at DESC);

-- -------------------------------------------------------------------------------------
-- 1.2 TENANT REGISTRY
-- One row per tenant (= one organization group with its OWN physical database,
-- per confirmed decision: database-per-tenant isolation).
-- -------------------------------------------------------------------------------------

CREATE TABLE tenant (
    tenant_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_code             VARCHAR(30) NOT NULL UNIQUE,      -- short slug, e.g. "acme-nepal"
    display_name            VARCHAR(200) NOT NULL,
    subscription_plan       VARCHAR(30) NOT NULL DEFAULT 'FREE',  -- FREE, STARTER, PROFESSIONAL,
                                                                    -- ENTERPRISE, GOVERNMENT, NGO, WHITE_LABEL
    deployment_model        VARCHAR(20) NOT NULL DEFAULT 'SHARED_CLOUD', -- SHARED_CLOUD, DEDICATED_CLOUD,
                                                                            -- PRIVATE_CLOUD, ON_PREMISE
    db_host                 VARCHAR(255) NOT NULL,
    db_port                 INT NOT NULL DEFAULT 5432,
    db_name                 VARCHAR(100) NOT NULL,
    db_credentials_secret_ref VARCHAR(255) NOT NULL,  -- pointer into secrets manager, never plaintext
    db_schema_version       VARCHAR(20) NOT NULL,       -- last migration version applied
    status                  VARCHAR(20) NOT NULL DEFAULT 'PROVISIONING',
                                -- PROVISIONING, ACTIVE, SUSPENDED, ARCHIVED, DELETION_PENDING
    provisioned_at          TIMESTAMPTZ,
    suspended_at            TIMESTAMPTZ,
    suspension_reason       TEXT,
    data_residency_region   VARCHAR(50) DEFAULT 'NP',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenant_provisioning_job (
    job_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id               UUID NOT NULL REFERENCES tenant(tenant_id),
    job_type                VARCHAR(30) NOT NULL,  -- CREATE_DB, RUN_MIGRATIONS, SEED_DEFAULTS, CREATE_ADMIN_USER
    status                  VARCHAR(20) NOT NULL DEFAULT 'PENDING', -- PENDING, RUNNING, SUCCEEDED, FAILED
    attempt_count           INT NOT NULL DEFAULT 0,
    last_error              TEXT,
    started_at              TIMESTAMPTZ,
    completed_at            TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Subscription limits per plan (§9 — Number of Users, Storage, API Calls, etc.)
CREATE TABLE tenant_subscription_limit (
    tenant_id               UUID PRIMARY KEY REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    max_users               INT,             -- NULL = unlimited (Free Core Edition, §227)
    max_organizations       INT,
    max_storage_gb          INT,
    max_api_calls_per_day   INT,
    ai_usage_quota          INT,
    custom_branding_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    white_label_allowed     BOOLEAN NOT NULL DEFAULT FALSE,
    effective_from          DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to            DATE
);

-- -------------------------------------------------------------------------------------
-- 1.3 TENANT MEMBERSHIP
-- Links a Global Identity to a Tenant. The actual ROLE assigned lives inside the
-- tenant's own database (core_platform.user_role_assignment) — this table only
-- establishes "this person may access this tenant" + which local user profile to use.
-- -------------------------------------------------------------------------------------

CREATE TABLE tenant_membership (
    membership_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    global_user_id          UUID NOT NULL REFERENCES global_identity(global_user_id),
    tenant_id               UUID NOT NULL REFERENCES tenant(tenant_id),
    tenant_local_user_id    UUID NOT NULL,     -- FK reference (logical, cross-db) to
                                                 -- tenant DB's core_platform.app_user.user_id
    status                  VARCHAR(20) NOT NULL DEFAULT 'ACTIVE', -- ACTIVE, SUSPENDED, REVOKED
    invited_at              TIMESTAMPTZ,
    accepted_at             TIMESTAMPTZ,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (global_user_id, tenant_id)
);
CREATE INDEX idx_membership_user ON tenant_membership (global_user_id);
CREATE INDEX idx_membership_tenant ON tenant_membership (tenant_id);

-- -------------------------------------------------------------------------------------
-- 1.4 PLATFORM ADMINISTRATION (marketplace, cross-tenant support, licensing audit)
-- -------------------------------------------------------------------------------------

CREATE TABLE platform_audit_log (
    audit_id                BIGSERIAL PRIMARY KEY,
    actor_global_user_id     UUID REFERENCES global_identity(global_user_id),
    tenant_id                UUID REFERENCES tenant(tenant_id),
    action                   VARCHAR(100) NOT NULL,   -- e.g. TENANT_SUSPENDED, PLAN_CHANGED
    details                  JSONB,
    ip_address                INET,
    created_at                TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================================
-- END SECTION 1 — CONTROL PLANE
-- =====================================================================================
