-- =====================================================================================
-- NEFMP — SECTION 5: AUDIT TRAIL (cross-cutting, §136)
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS audit;
SET search_path TO audit, public;

CREATE TABLE audit_trail (
    audit_id                  BIGSERIAL PRIMARY KEY,
    org_id                     UUID NOT NULL,
    entity_type                  VARCHAR(50) NOT NULL,     -- INVOICE, CUSTOMER, CREDIT_NOTE, JOURNAL_ENTRY, etc.
    entity_id                      UUID NOT NULL,
    action                            VARCHAR(30) NOT NULL,   -- CREATE, UPDATE, APPROVE, VOID, DELETE_ATTEMPT
    field_name                          VARCHAR(100),
    old_value                             TEXT,
    new_value                               TEXT,
    performed_by_user_id                      UUID NOT NULL,
    ip_address                                  INET,
    device_info                                   TEXT,
    reason                                          TEXT,
    performed_at                                      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_trail (entity_type, entity_id, performed_at DESC);
CREATE INDEX idx_audit_org_date ON audit_trail (org_id, performed_at DESC);

-- Audit trail is append-only: block UPDATE and DELETE at the database level.
CREATE OR REPLACE FUNCTION fn_block_audit_mutation() RETURNS TRIGGER AS $$
BEGIN
    RAISE EXCEPTION 'Audit trail records are immutable and cannot be updated or deleted.';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_no_update
    BEFORE UPDATE ON audit_trail FOR EACH ROW EXECUTE FUNCTION fn_block_audit_mutation();
CREATE TRIGGER trg_audit_no_delete
    BEFORE DELETE ON audit_trail FOR EACH ROW EXECUTE FUNCTION fn_block_audit_mutation();

-- =====================================================================================
-- SECTION 6: FORWARD-COMPATIBLE MODULE PLACEHOLDERS
-- These are intentionally minimal "shell" tables — just enough so that Fixed Assets,
-- Procurement, Banking, and Budget can be referenced (e.g. by future FKs, or by
-- reports that already expect these entities to exist) WITHOUT being built out yet.
-- Each will be replaced by its full schema in its own dedicated development step,
-- per the "one module at a time" workflow. Building these now as full modules would
-- violate that sequencing — they exist here only as non-breaking placeholders.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS future_modules;
SET search_path TO future_modules, public;

-- Procurement / AP (§55-75) — placeholder referenced by vendor-side of Fixed Assets later
CREATE TABLE vendor_stub (
    vendor_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                      UUID NOT NULL,
    vendor_code                  VARCHAR(30) NOT NULL,
    vendor_name                    VARCHAR(300) NOT NULL,
    status                           VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, vendor_code)
);
-- NOTE: full Vendor Master (§56-57), PR/RFQ/PO/GRN/Three-Way-Match (§58-75) — NOT built yet.

-- Banking & Treasury (§76-94) — placeholder for bank account referenced by Receipts
CREATE TABLE bank_account_stub (
    bank_account_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL,
    account_name                   VARCHAR(200) NOT NULL,
    account_number                   VARCHAR(50) NOT NULL,
    currency                           CHAR(3) NOT NULL DEFAULT 'NPR',
    status                               VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
);
-- NOTE: full Bank Master, Reconciliation, Treasury, Loans, Investments (§77-94) — NOT built yet.

-- Budget / EPM (§95-115) — placeholder so e-Billing can (optionally, later) check
-- "Revenue Budget vs Actual" without the full budgeting engine existing yet.
CREATE TABLE budget_line_stub (
    budget_line_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                        UUID NOT NULL,
    fiscal_year_id                  UUID NOT NULL,
    account_id                        UUID,
    cost_center_id                      UUID,
    period_number                        SMALLINT,
    budget_amount                          NUMERIC(18,2) NOT NULL DEFAULT 0,
    actual_amount                            NUMERIC(18,2) NOT NULL DEFAULT 0  -- refreshed by triggers later
);
-- NOTE: full Budget Architecture, Commitment Accounting, Rolling Forecasts (§95-115) — NOT built yet.

-- Fixed Assets (§141-160) — placeholder only
CREATE TABLE fixed_asset_stub (
    asset_id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                        UUID NOT NULL,
    asset_code                     VARCHAR(30) NOT NULL,
    asset_name                       VARCHAR(200) NOT NULL,
    status                              VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, asset_code)
);
-- NOTE: full Fixed Asset Register, Depreciation, CWIP, Revaluation (§141-160) — NOT built yet.

-- =====================================================================================
-- END OF COMPREHENSIVE SCHEMA (PHASE 1 SLICE)
-- Build order executed: Control Plane -> Core Tenant Platform -> Chart of Accounts /
-- Accounting Stub -> e-Billing (fully detailed) -> Audit Trail -> Forward placeholders.
-- Next dedicated modules (each to repeat full Requirement Analysis -> DB -> API ->
-- Backend -> Frontend -> Test -> Docs cycle): Procurement & AP, Banking & Treasury,
-- Full Accounting Engine (Posting Rules, Recurring/Reversing Journals), Budget & EPM,
-- Fixed Assets, Workflow Engine, Full RBAC/ABAC, BI & Dashboards.
-- =====================================================================================
