-- =====================================================================================
-- NEFMP — SECTION 2: CORE TENANT PLATFORM SCHEMA
-- This schema is deployed INSIDE every individual tenant database
-- (database-per-tenant model, per confirmed architecture decision).
-- Contains: Organization hierarchy, Fiscal Year + BS/AD calendar, minimal RBAC,
-- Master Data shared across all modules.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS core_platform;
SET search_path TO core_platform, public;

-- -------------------------------------------------------------------------------------
-- 2.1 ORGANIZATION HIERARCHY
-- Tenant -> Organization -> Branch -> Department -> Cost Center -> Project (§9, §13-19)
-- tenant_id is stored here too (denormalized) even though isolation is by database,
-- so cross-checks / exports / backups retain unambiguous provenance.
-- -------------------------------------------------------------------------------------

CREATE TABLE organization (
    org_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id                UUID NOT NULL,             -- mirrors control_plane.tenant.tenant_id
    legal_name               VARCHAR(300) NOT NULL,
    trade_name                VARCHAR(300),
    pan_number                 VARCHAR(20),
    vat_number                 VARCHAR(20),
    registration_number        VARCHAR(50),
    ird_office                 VARCHAR(100),
    company_type               VARCHAR(50),    -- Pvt Ltd, Public Ltd, NGO, INGO, Sole Prop, etc.
    industry                   VARCHAR(100),
    country                    VARCHAR(100) DEFAULT 'Nepal',
    province                   VARCHAR(100),
    district                   VARCHAR(100),
    municipality               VARCHAR(100),
    address_line               TEXT,
    contact_number             VARCHAR(30),
    email                      CITEXT,
    website                    VARCHAR(255),
    logo_url                   TEXT,
    digital_stamp_url          TEXT,
    base_currency              CHAR(3) NOT NULL DEFAULT 'NPR',
    reporting_currency          CHAR(3) NOT NULL DEFAULT 'NPR',
    fiscal_calendar_type        VARCHAR(20) NOT NULL DEFAULT 'BS',  -- BS or GREGORIAN (display pref)
    time_zone                   VARCHAR(50) NOT NULL DEFAULT 'Asia/Kathmandu',
    status                      VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE branch (
    branch_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    UUID NOT NULL REFERENCES organization(org_id),
    branch_code                VARCHAR(30) NOT NULL,
    branch_name                 VARCHAR(200) NOT NULL,
    address                      TEXT,
    contact_number               VARCHAR(30),
    branch_manager_user_id       UUID,   -- FK to app_user, added after app_user defined
    default_cost_center_id        UUID,
    status                        VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, branch_code)
);

CREATE TABLE department (
    department_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL REFERENCES organization(org_id),
    department_code               VARCHAR(30) NOT NULL,
    department_name               VARCHAR(200) NOT NULL,
    department_head_user_id        UUID,
    cost_center_id                  UUID,
    status                          VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, department_code)
);

CREATE TABLE cost_center (
    cost_center_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL REFERENCES organization(org_id),
    parent_cost_center_id         UUID REFERENCES cost_center(cost_center_id),
    cost_center_code               VARCHAR(30) NOT NULL,
    cost_center_name                VARCHAR(200) NOT NULL,
    branch_id                        UUID REFERENCES branch(branch_id),
    department_id                    UUID REFERENCES department(department_id),
    status                            VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, cost_center_code)
);

CREATE TABLE project (
    project_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                        UUID NOT NULL REFERENCES organization(org_id),
    project_code                   VARCHAR(30) NOT NULL,
    project_name                    VARCHAR(200) NOT NULL,
    client_customer_id                UUID,        -- FK added after customer table exists
    start_date                        DATE,
    end_date                          DATE,
    budget_amount                     NUMERIC(18,2),
    funding_source                     VARCHAR(200),
    project_manager_user_id             UUID,
    currency                             CHAR(3) DEFAULT 'NPR',
    status                                VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, project_code)
);

ALTER TABLE branch ADD CONSTRAINT fk_branch_cost_center
    FOREIGN KEY (default_cost_center_id) REFERENCES cost_center(cost_center_id);
ALTER TABLE department ADD CONSTRAINT fk_department_cost_center
    FOREIGN KEY (cost_center_id) REFERENCES cost_center(cost_center_id);

-- -------------------------------------------------------------------------------------
-- 2.2 FISCAL YEAR — Gregorian storage, Bikram Sambat presentation (confirmed decision)
-- -------------------------------------------------------------------------------------

-- Authoritative BS <-> AD day-level mapping. Populated from Nepal government calendar
-- data (BS month lengths are irregular and NOT computable by fixed formula).
CREATE TABLE bs_ad_calendar_reference (
    bs_year                 SMALLINT NOT NULL,
    bs_month                SMALLINT NOT NULL,      -- 1 = Baisakh ... 12 = Chaitra
    bs_day                  SMALLINT NOT NULL,
    ad_date                 DATE NOT NULL UNIQUE,
    PRIMARY KEY (bs_year, bs_month, bs_day)
);
CREATE INDEX idx_bs_calendar_ad_date ON bs_ad_calendar_reference (ad_date);

CREATE TABLE fiscal_year (
    fiscal_year_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                     UUID NOT NULL REFERENCES organization(org_id),
    fiscal_year_code             VARCHAR(20) NOT NULL,       -- e.g. "2083/84"
    start_date_ad                 DATE NOT NULL,               -- ALL logic operates on this
    end_date_ad                   DATE NOT NULL,
    start_date_bs_display           VARCHAR(12),               -- e.g. "2083-04-01" cached for UI
    end_date_bs_display              VARCHAR(12),
    status                            VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
                                        -- DRAFT, OPEN, ADJUSTMENT, CLOSING, CLOSED, ARCHIVED
    is_current                        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, fiscal_year_code),
    CHECK (end_date_ad > start_date_ad)
);

CREATE TABLE accounting_period (
    period_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    fiscal_year_id            UUID NOT NULL REFERENCES fiscal_year(fiscal_year_id),
    period_number              SMALLINT NOT NULL,     -- 1..12 (+13 adjustment period if used)
    period_name                 VARCHAR(30) NOT NULL,  -- BS month name for display
    start_date_ad                 DATE NOT NULL,
    end_date_ad                    DATE NOT NULL,
    status                          VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN, LOCKED, CLOSED
    UNIQUE (fiscal_year_id, period_number)
);

-- -------------------------------------------------------------------------------------
-- 2.3 MINIMAL USER / ROLE (full field/record-level RBAC engine deferred to
-- dedicated RBAC module per sequencing decision; this is enough to support
-- e-Billing approvals now: who created / approved an invoice).
-- -------------------------------------------------------------------------------------

CREATE TABLE app_user (
    user_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    global_user_id            UUID NOT NULL,   -- FK (logical, cross-db) -> control_plane.global_identity
    org_id                     UUID NOT NULL REFERENCES organization(org_id),
    employee_id                 VARCHAR(30),
    full_name                    VARCHAR(200) NOT NULL,
    designation                   VARCHAR(100),
    department_id                  UUID REFERENCES department(department_id),
    branch_id                       UUID REFERENCES branch(branch_id),
    default_fiscal_year_id            UUID REFERENCES fiscal_year(fiscal_year_id),
    digital_signature_url              TEXT,
    status                              VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, global_user_id)
);

CREATE TABLE role (
    role_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    UUID NOT NULL REFERENCES organization(org_id),
    role_code                  VARCHAR(50) NOT NULL,   -- e.g. BILLING_OFFICER, CFO, ACCOUNTANT
    role_name                    VARCHAR(150) NOT NULL,
    is_system_role                BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (org_id, role_code)
);

CREATE TABLE user_role_assignment (
    assignment_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                    UUID NOT NULL REFERENCES app_user(user_id),
    role_id                     UUID NOT NULL REFERENCES role(role_id),
    branch_id                    UUID REFERENCES branch(branch_id),   -- optional scope narrowing
    department_id                 UUID REFERENCES department(department_id),
    assigned_at                    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, role_id, branch_id, department_id)
);

-- Segregation-of-Duties override log (§176, confirmed: soft-enforced with logging)
CREATE TABLE sod_override_log (
    override_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                    UUID NOT NULL REFERENCES app_user(user_id),
    sod_rule_code               VARCHAR(50) NOT NULL,  -- e.g. CREATE_APPROVE_INVOICE
    entity_type                   VARCHAR(50) NOT NULL,
    entity_id                      UUID NOT NULL,
    justification                   TEXT NOT NULL,
    overridden_at                    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------------------
-- 2.4 SEQUENCE GENERATOR (fiscal-year-wise, branch-wise document numbering, §41, §24)
-- Row-locked via SELECT ... FOR UPDATE at the application layer to avoid race conditions.
-- -------------------------------------------------------------------------------------

CREATE TABLE document_numbering_rule (
    rule_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                    UUID NOT NULL REFERENCES organization(org_id),
    document_type               VARCHAR(30) NOT NULL,   -- SALES_INVOICE, CREDIT_NOTE, RECEIPT, etc.
    branch_id                     UUID REFERENCES branch(branch_id),  -- NULL = org-wide sequence
    fiscal_year_id                 UUID NOT NULL REFERENCES fiscal_year(fiscal_year_id),
    prefix                          VARCHAR(20) NOT NULL,   -- e.g. "INV-2083-"
    next_number                      BIGINT NOT NULL DEFAULT 1,
    padding_length                    SMALLINT NOT NULL DEFAULT 6,
    UNIQUE (org_id, document_type, branch_id, fiscal_year_id)
);

-- =====================================================================================
-- END SECTION 2 — CORE TENANT PLATFORM
-- =====================================================================================
