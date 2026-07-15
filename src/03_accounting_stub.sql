-- =====================================================================================
-- NEFMP — SECTION 3: CHART OF ACCOUNTS + ACCOUNTING ENGINE STUB
-- Full Journal/GL/Posting-Rules-Engine module (§22-34) is a LATER increment.
-- This section builds only what e-Billing needs to post real, balanced,
-- auditable accounting entries against: Chart of Accounts + Journal/Journal Line +
-- General Ledger balance view. Deeper accounting features (recurring/reversing
-- journals, multi-currency revaluation, budget commitments) are deferred.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS accounting;
SET search_path TO accounting, public;

-- -------------------------------------------------------------------------------------
-- 3.1 CHART OF ACCOUNTS (§23)
-- -------------------------------------------------------------------------------------

CREATE TABLE chart_of_account (
    account_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                     UUID NOT NULL,   -- REFERENCES core_platform.organization
    account_code                 VARCHAR(20) NOT NULL,     -- e.g. "111200"
    account_name                   VARCHAR(200) NOT NULL,
    nepali_name                      VARCHAR(200),
    parent_account_id                 UUID REFERENCES chart_of_account(account_id),
    account_type                       VARCHAR(40) NOT NULL,
        -- ASSET, LIABILITY, EQUITY, REVENUE, COST_OF_SALES, OPERATING_EXPENSE, OTHER_INCOME, OTHER_EXPENSE
    normal_balance                      VARCHAR(6) NOT NULL CHECK (normal_balance IN ('DEBIT','CREDIT')),
    financial_statement_classification    VARCHAR(60),
    cash_flow_classification                VARCHAR(30),
    nfrs_mapping                              VARCHAR(60),
    is_control_account                         BOOLEAN NOT NULL DEFAULT FALSE,
    control_account_type                        VARCHAR(30),  -- AR, AP, FIXED_ASSET, INVENTORY, VAT, TDS, BANK
    cost_center_required                          BOOLEAN NOT NULL DEFAULT FALSE,
    project_required                                BOOLEAN NOT NULL DEFAULT FALSE,
    department_required                               BOOLEAN NOT NULL DEFAULT FALSE,
    branch_required                                     BOOLEAN NOT NULL DEFAULT FALSE,
    currency                                              CHAR(3) DEFAULT 'NPR',
    posting_allowed                                        BOOLEAN NOT NULL DEFAULT TRUE,
    is_active                                                BOOLEAN NOT NULL DEFAULT TRUE,
    opening_balance_allowed                                    BOOLEAN NOT NULL DEFAULT TRUE,
    reconciliation_required                                      BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (org_id, account_code)
);
CREATE INDEX idx_coa_org_type ON chart_of_account (org_id, account_type);

-- Minimum seed accounts required for e-Billing to function (actual seed script
-- run per-tenant at provisioning time, not hardcoded here):
--   112000 Accounts Receivable (control account, AR)
--   211000 VAT Payable
--   400000 Service Revenue (parent; child per service category as needed)

-- -------------------------------------------------------------------------------------
-- 3.2 TAX CODES (VAT / TDS) — referenced by Service Catalogue & Invoice Lines
-- -------------------------------------------------------------------------------------

CREATE TABLE tax_code (
    tax_code_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                     UUID NOT NULL,
    tax_code                    VARCHAR(20) NOT NULL,   -- e.g. "VAT13", "ZERO", "EXEMPT", "TDS15"
    tax_name                      VARCHAR(100) NOT NULL,
    tax_type                        VARCHAR(10) NOT NULL CHECK (tax_type IN ('VAT','TDS')),
    rate_percent                     NUMERIC(6,3) NOT NULL,
    liability_account_id               UUID NOT NULL REFERENCES chart_of_account(account_id),
    effective_from                       DATE NOT NULL,
    effective_to                          DATE,
    is_active                              BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (org_id, tax_code)
);

-- -------------------------------------------------------------------------------------
-- 3.3 JOURNAL / GENERAL LEDGER (minimal — full Posting Rules Engine is later increment)
-- Every invoice, receipt, credit/debit note posts here via the automatic
-- posting rules defined in the e-Billing module (never manual journal entry
-- for these routine transactions, per §26 core principle).
-- -------------------------------------------------------------------------------------

CREATE TABLE journal_entry (
    journal_id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL,
    fiscal_year_id                UUID NOT NULL,
    accounting_period_id            UUID NOT NULL,
    voucher_type                      VARCHAR(30) NOT NULL,  -- SALES_INVOICE, CREDIT_NOTE, RECEIPT, DEBIT_NOTE
    voucher_number                     VARCHAR(40) NOT NULL,
    voucher_date                        DATE NOT NULL,
    posting_date                          DATE NOT NULL,
    source_document_type                    VARCHAR(30),    -- e.g. 'INVOICE'
    source_document_id                        UUID,          -- e.g. invoice_id — polymorphic reference
    narration                                   TEXT,
    total_debit                                   NUMERIC(18,2) NOT NULL,
    total_credit                                    NUMERIC(18,2) NOT NULL,
    status                                            VARCHAR(20) NOT NULL DEFAULT 'POSTED',
                                                        -- DRAFT, POSTED, REVERSED
    created_by_user_id                                  UUID NOT NULL,
    created_at                                            TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, voucher_type, voucher_number),
    CHECK (total_debit = total_credit)     -- hard DB-level balance enforcement
);
CREATE INDEX idx_journal_source ON journal_entry (source_document_type, source_document_id);
CREATE INDEX idx_journal_period ON journal_entry (accounting_period_id);

CREATE TABLE journal_line (
    journal_line_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    journal_id                    UUID NOT NULL REFERENCES journal_entry(journal_id) ON DELETE CASCADE,
    line_number                     SMALLINT NOT NULL,
    account_id                        UUID NOT NULL REFERENCES chart_of_account(account_id),
    debit_amount                        NUMERIC(18,2) NOT NULL DEFAULT 0,
    credit_amount                        NUMERIC(18,2) NOT NULL DEFAULT 0,
    currency                               CHAR(3) NOT NULL DEFAULT 'NPR',
    exchange_rate                            NUMERIC(12,6) NOT NULL DEFAULT 1,
    base_currency_amount                       NUMERIC(18,2) NOT NULL, -- amount * exchange_rate
    branch_id                                    UUID,
    department_id                                  UUID,
    cost_center_id                                    UUID,
    project_id                                          UUID,
    customer_id                                           UUID,   -- for AR sub-ledger reconciliation
    description                                             TEXT,
    CHECK (debit_amount >= 0 AND credit_amount >= 0),
    CHECK (NOT (debit_amount > 0 AND credit_amount > 0))  -- a line is either debit or credit, not both
);
CREATE INDEX idx_journal_line_account ON journal_line (account_id);
CREATE INDEX idx_journal_line_customer ON journal_line (customer_id) WHERE customer_id IS NOT NULL;

-- Immutability enforcement: once a journal is POSTED, block UPDATE at DB level
-- (compliance-critical control identified in e-Billing risk analysis).
CREATE OR REPLACE FUNCTION fn_block_posted_journal_update() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'POSTED' AND NEW.status = 'POSTED' THEN
        RAISE EXCEPTION 'Posted journal entries are immutable. Use a reversing/adjustment entry.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_journal_entry_immutable
    BEFORE UPDATE ON journal_entry
    FOR EACH ROW EXECUTE FUNCTION fn_block_posted_journal_update();

-- =====================================================================================
-- END SECTION 3 — CHART OF ACCOUNTS + ACCOUNTING STUB
-- =====================================================================================
