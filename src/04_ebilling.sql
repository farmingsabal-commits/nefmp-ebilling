-- =====================================================================================
-- NEFMP — SECTION 4: IRD e-BILLING MODULE (Priority Development Module)
-- Covers SRS §35-54: Customer Management, Service Catalogue, Quotation, Invoice,
-- Credit/Debit Notes, Recurring Billing, Receipts, Aging.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS ebilling;
SET search_path TO ebilling, accounting, core_platform, public;

-- -------------------------------------------------------------------------------------
-- 4.1 CUSTOMER MASTER (§36) — Accounts Receivable Master
-- -------------------------------------------------------------------------------------

CREATE TABLE customer (
    customer_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL,
    customer_code                  VARCHAR(30) NOT NULL,
    customer_name                    VARCHAR(300) NOT NULL,
    legal_name                         VARCHAR(300),
    trade_name                           VARCHAR(300),
    customer_type                          VARCHAR(20) NOT NULL DEFAULT 'INDIVIDUAL',
                                              -- INDIVIDUAL, COMPANY, GOVERNMENT, NGO_INGO, FOREIGN
    is_related_party                          BOOLEAN NOT NULL DEFAULT FALSE,
    pan_number                                  VARCHAR(20),
    vat_number                                    VARCHAR(20),
    company_registration_number                     VARCHAR(50),
    national_id                                       VARCHAR(50),
    passport_number                                     VARCHAR(50),
    primary_contact_name                                  VARCHAR(200),
    email                                                   CITEXT,
    mobile_number                                             VARCHAR(20),
    telephone                                                   VARCHAR(20),
    country                                                      VARCHAR(100) DEFAULT 'Nepal',
    province                                                       VARCHAR(100),
    district                                                        VARCHAR(100),
    municipality                                                     VARCHAR(100),
    ward                                                                VARCHAR(10),
    street_address                                                       TEXT,
    credit_limit                                                          NUMERIC(18,2) DEFAULT 0,
    credit_days                                                            INT DEFAULT 0,
    payment_terms                                                            VARCHAR(100),
    currency                                                                  CHAR(3) NOT NULL DEFAULT 'NPR',
    default_ar_account_id                                                       UUID, -- FK -> chart_of_account
    tax_category                                                                  VARCHAR(30) DEFAULT 'STANDARD',
                                                                                     -- STANDARD, ZERO_RATED, EXEMPT
    withholding_tax_status                                                          BOOLEAN NOT NULL DEFAULT FALSE,
    customer_group                                                                   VARCHAR(100),
    risk_rating                                                                        VARCHAR(20),
    branch_id                                                                            UUID,
    department_id                                                                          UUID,
    salesperson_user_id                                                                      UUID,
    status                                                                                     VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at                                                                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                                                                     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, customer_code)
);
CREATE INDEX idx_customer_org_status ON customer (org_id, status);
CREATE INDEX idx_customer_name_search ON customer USING GIN (customer_name gin_trgm_ops);

CREATE TABLE customer_attachment (
    attachment_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id                   UUID NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    document_type                   VARCHAR(50) NOT NULL, -- CONTRACT, PAN_CERT, REGISTRATION_CERT, AGREEMENT, ID
    file_url                          TEXT NOT NULL,
    uploaded_by_user_id                 UUID NOT NULL,
    uploaded_at                           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -------------------------------------------------------------------------------------
-- 4.2 SERVICE CATALOGUE (§37)
-- -------------------------------------------------------------------------------------

CREATE TABLE service_category (
    category_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                       UUID NOT NULL,
    category_name                  VARCHAR(150) NOT NULL,
    UNIQUE (org_id, category_name)
);

CREATE TABLE service_catalogue (
    service_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                        UUID NOT NULL,
    service_code                   VARCHAR(30) NOT NULL,
    service_name                     VARCHAR(200) NOT NULL,
    nepali_name                        VARCHAR(200),
    description                          TEXT,
    category_id                            UUID REFERENCES service_category(category_id),
    unit_of_measure                          VARCHAR(20) DEFAULT 'Unit',
    standard_rate                              NUMERIC(18,2) NOT NULL DEFAULT 0,
    default_tax_code_id                          UUID REFERENCES accounting.tax_code(tax_code_id),
    revenue_account_id                             UUID NOT NULL, -- FK -> chart_of_account
    default_cost_center_id                           UUID,
    default_department_id                              UUID,
    default_discount_percent                             NUMERIC(5,2) DEFAULT 0,
    revenue_recognition_method                             VARCHAR(30) NOT NULL DEFAULT 'IMMEDIATE',
                                                              -- IMMEDIATE only in v1; MILESTONE / POC /
                                                              -- TIME_BASED / SUBSCRIPTION / DEFERRED = Phase 2
    status                                                     VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    UNIQUE (org_id, service_code)
);

-- -------------------------------------------------------------------------------------
-- 4.3 SALES QUOTATION (§38) — pre-sales; Sales Order (§39) deferred to increment 2
-- -------------------------------------------------------------------------------------

CREATE TABLE quotation (
    quotation_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                        UUID NOT NULL,
    quotation_number               VARCHAR(40) NOT NULL,
    customer_id                      UUID NOT NULL REFERENCES customer(customer_id),
    quotation_date                    DATE NOT NULL,
    validity_date                       DATE,
    currency                              CHAR(3) NOT NULL DEFAULT 'NPR',
    terms_and_conditions                    TEXT,
    version_number                            INT NOT NULL DEFAULT 1,
    status                                      VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
                                                   -- DRAFT, SENT, ACCEPTED, REJECTED, EXPIRED, CONVERTED
    converted_to_invoice_id                        UUID,
    created_by_user_id                               UUID NOT NULL,
    created_at                                         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, quotation_number)
);

CREATE TABLE quotation_line (
    quotation_line_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    quotation_id                   UUID NOT NULL REFERENCES quotation(quotation_id) ON DELETE CASCADE,
    line_number                      SMALLINT NOT NULL,
    service_id                         UUID NOT NULL REFERENCES service_catalogue(service_id),
    description                          TEXT,
    quantity                               NUMERIC(18,4) NOT NULL DEFAULT 1,
    unit_price                               NUMERIC(18,2) NOT NULL,
    discount_percent                           NUMERIC(5,2) DEFAULT 0,
    line_total                                   NUMERIC(18,2) NOT NULL
);

-- -------------------------------------------------------------------------------------
-- 4.4 INVOICE (§40-43) — the core revenue transaction
-- -------------------------------------------------------------------------------------

CREATE TABLE invoice (
    invoice_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                         UUID NOT NULL,
    fiscal_year_id                   UUID NOT NULL,
    invoice_number                     VARCHAR(40) NOT NULL,
    invoice_type                         VARCHAR(30) NOT NULL DEFAULT 'TAX_INVOICE',
                                            -- TAX_INVOICE, ABBREVIATED_TAX_INVOICE, EXPORT_INVOICE,
                                            -- PROFORMA_INVOICE, RECURRING_INVOICE, ADVANCE_INVOICE,
                                            -- MILESTONE_INVOICE, ZERO_RATED_INVOICE, TAX_EXEMPT_INVOICE
    invoice_date                          DATE NOT NULL,
    due_date                                DATE NOT NULL,
    customer_id                              UUID NOT NULL REFERENCES customer(customer_id),
    quotation_id                               UUID REFERENCES quotation(quotation_id),
    branch_id                                    UUID,
    department_id                                  UUID,
    cost_center_id                                   UUID,
    project_id                                         UUID,
    salesperson_user_id                                  UUID,
    currency                                               CHAR(3) NOT NULL DEFAULT 'NPR',
    exchange_rate                                            NUMERIC(12,6) NOT NULL DEFAULT 1,  -- historical, at invoice date
    payment_terms                                              VARCHAR(100),
    contract_reference                                           VARCHAR(100),
    purchase_order_reference                                       VARCHAR(100),
    billing_period_start                                             DATE,
    billing_period_end                                                 DATE,

    subtotal_amount                                                     NUMERIC(18,2) NOT NULL DEFAULT 0,
    discount_amount                                                       NUMERIC(18,2) NOT NULL DEFAULT 0,
    taxable_amount                                                         NUMERIC(18,2) NOT NULL DEFAULT 0,
    vat_amount                                                               NUMERIC(18,2) NOT NULL DEFAULT 0,
    tds_amount                                                                 NUMERIC(18,2) NOT NULL DEFAULT 0,
    other_tax_amount                                                             NUMERIC(18,2) NOT NULL DEFAULT 0,
    grand_total                                                                    NUMERIC(18,2) NOT NULL DEFAULT 0,
    amount_paid                                                                     NUMERIC(18,2) NOT NULL DEFAULT 0,
    balance_due                                                                       NUMERIC(18,2) NOT NULL DEFAULT 0,

    -- IRD compliance fields
    vat_amount_npr_equivalent                                                          NUMERIC(18,2) NOT NULL DEFAULT 0,
    qr_code_payload                                                                      TEXT,
    digital_signature                                                                      TEXT,

    status                                                                                  VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
        -- DRAFT, PENDING_APPROVAL, APPROVED, GENERATED, POSTED, DELIVERED,
        -- PARTIALLY_PAID, PAID, CLOSED, VOID
    revenue_recognition_method                                                                VARCHAR(30) NOT NULL DEFAULT 'IMMEDIATE',
    is_recurring_generated                                                                      BOOLEAN NOT NULL DEFAULT FALSE,
    recurring_schedule_id                                                                         UUID,

    journal_id                                                                                     UUID REFERENCES accounting.journal_entry(journal_id),

    void_reason                                                                                      TEXT,
    voided_by_user_id                                                                                  UUID,
    voided_at                                                                                            TIMESTAMPTZ,

    created_by_user_id                                                                                    UUID NOT NULL,
    approved_by_user_id                                                                                     UUID,
    approved_at                                                                                              TIMESTAMPTZ,
    created_at                                                                                                 TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                                                                                                   TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (org_id, invoice_number),
    CHECK (exchange_rate > 0),
    CHECK (grand_total = subtotal_amount - discount_amount + vat_amount + tds_amount + other_tax_amount
           OR status = 'DRAFT'),   -- only enforce reconciliation once posted; draft may be mid-edit
    CHECK (balance_due = grand_total - amount_paid)
);
CREATE INDEX idx_invoice_lookup ON invoice (org_id, fiscal_year_id, customer_id, status, invoice_date);
CREATE INDEX idx_invoice_customer_balance ON invoice (customer_id) WHERE balance_due > 0;

CREATE TABLE invoice_line (
    invoice_line_id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id                      UUID NOT NULL REFERENCES invoice(invoice_id) ON DELETE CASCADE,
    line_number                       SMALLINT NOT NULL,
    service_id                          UUID NOT NULL REFERENCES service_catalogue(service_id),
    description                           TEXT,
    quantity                                NUMERIC(18,4) NOT NULL DEFAULT 1,
    unit_of_measure                           VARCHAR(20),
    unit_price                                  NUMERIC(18,2) NOT NULL,
    discount_percent                              NUMERIC(5,2) DEFAULT 0,
    discount_amount                                 NUMERIC(18,2) NOT NULL DEFAULT 0,
    tax_code_id                                       UUID NOT NULL REFERENCES accounting.tax_code(tax_code_id),
    vat_percent                                         NUMERIC(6,3) NOT NULL DEFAULT 0,
    vat_amount                                            NUMERIC(18,2) NOT NULL DEFAULT 0,
    tds_percent                                              NUMERIC(6,3) NOT NULL DEFAULT 0,
    tds_amount                                                 NUMERIC(18,2) NOT NULL DEFAULT 0,
    line_total                                                   NUMERIC(18,2) NOT NULL,
    revenue_account_id                                             UUID NOT NULL,
    cost_center_id                                                   UUID,
    department_id                                                      UUID,
    project_id                                                           UUID,
    UNIQUE (invoice_id, line_number)
);
CREATE INDEX idx_invoice_line_invoice ON invoice_line (invoice_id);

-- Invoice status transition guard — enforces BR-9 sequential lifecycle at DB level
CREATE OR REPLACE FUNCTION fn_validate_invoice_status_transition() RETURNS TRIGGER AS $$
DECLARE
    allowed BOOLEAN := FALSE;
BEGIN
    -- Immutability check runs UNCONDITIONALLY whenever OLD.status is beyond
    -- DRAFT/PENDING_APPROVAL/APPROVED — regardless of whether status itself
    -- is also changing in this same UPDATE. (A same-status update must not
    -- be able to sneak financial-field changes through.)
    IF OLD.status NOT IN ('DRAFT','PENDING_APPROVAL','APPROVED') THEN
        IF NEW.grand_total <> OLD.grand_total OR NEW.subtotal_amount <> OLD.subtotal_amount
           OR NEW.vat_amount <> OLD.vat_amount OR NEW.tds_amount <> OLD.tds_amount
           OR NEW.taxable_amount <> OLD.taxable_amount OR NEW.discount_amount <> OLD.discount_amount THEN
            RAISE EXCEPTION 'Posted invoice financial amounts are immutable. Use a Credit/Debit Note.';
        END IF;
    END IF;

    IF OLD.status = NEW.status THEN
        RETURN NEW; -- non-status, non-financial field update (e.g. delivery notes) — allowed
    END IF;

    allowed := CASE OLD.status
        WHEN 'DRAFT' THEN NEW.status IN ('PENDING_APPROVAL','VOID')
        WHEN 'PENDING_APPROVAL' THEN NEW.status IN ('APPROVED','DRAFT','VOID')
        WHEN 'APPROVED' THEN NEW.status IN ('GENERATED','VOID')
        WHEN 'GENERATED' THEN NEW.status IN ('POSTED')
        WHEN 'POSTED' THEN NEW.status IN ('DELIVERED','PARTIALLY_PAID','PAID','VOID')
        WHEN 'DELIVERED' THEN NEW.status IN ('PARTIALLY_PAID','PAID','VOID')
        WHEN 'PARTIALLY_PAID' THEN NEW.status IN ('PAID','VOID')
        WHEN 'PAID' THEN NEW.status IN ('CLOSED')
        ELSE FALSE
    END;

    IF NOT allowed THEN
        RAISE EXCEPTION 'Invalid invoice status transition: % -> %', OLD.status, NEW.status;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invoice_status_transition
    BEFORE UPDATE ON invoice
    FOR EACH ROW EXECUTE FUNCTION fn_validate_invoice_status_transition();

-- Block invoice line edits once invoice is beyond APPROVED (immutability, BR-3)
CREATE OR REPLACE FUNCTION fn_block_posted_invoice_line_edit() RETURNS TRIGGER AS $$
DECLARE
    inv_status VARCHAR(20);
BEGIN
    SELECT status INTO inv_status FROM invoice WHERE invoice_id = COALESCE(NEW.invoice_id, OLD.invoice_id);
    IF inv_status NOT IN ('DRAFT','PENDING_APPROVAL','APPROVED') THEN
        RAISE EXCEPTION 'Cannot modify lines of an invoice that has been generated/posted. Use a Credit/Debit Note.';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invoice_line_immutable
    BEFORE UPDATE OR DELETE ON invoice_line
    FOR EACH ROW EXECUTE FUNCTION fn_block_posted_invoice_line_edit();

-- -------------------------------------------------------------------------------------
-- 4.5 CREDIT NOTE / DEBIT NOTE (§45)
-- -------------------------------------------------------------------------------------

CREATE TABLE credit_debit_note (
    note_id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          UUID NOT NULL,
    note_type                        VARCHAR(10) NOT NULL CHECK (note_type IN ('CREDIT','DEBIT')),
    note_number                        VARCHAR(40) NOT NULL,
    note_date                            DATE NOT NULL,
    original_invoice_id                    UUID NOT NULL REFERENCES invoice(invoice_id),
    reason                                    VARCHAR(50) NOT NULL,
        -- RETURNED_SERVICE, BILLING_ERROR, DISCOUNT, PRICE_ADJUSTMENT, TAX_CORRECTION,
        -- ADDITIONAL_BILLING, UNDERCHARGE, CONTRACT_VARIATION
    amount                                      NUMERIC(18,2) NOT NULL,
    vat_amount                                    NUMERIC(18,2) NOT NULL DEFAULT 0,
    narration                                       TEXT,
    status                                            VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
                                                        -- DRAFT, APPROVED, POSTED, VOID
    journal_id                                          UUID REFERENCES accounting.journal_entry(journal_id),
    created_by_user_id                                    UUID NOT NULL,
    approved_by_user_id                                     UUID,
    created_at                                                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, note_number),
    CHECK (amount > 0)
);

-- Enforce BR: credit note cannot exceed remaining invoice balance (checked at
-- application layer before insert, plus DB-level defense via trigger)
CREATE OR REPLACE FUNCTION fn_validate_credit_note_amount() RETURNS TRIGGER AS $$
DECLARE
    inv_balance NUMERIC(18,2);
BEGIN
    IF NEW.note_type = 'CREDIT' THEN
        SELECT balance_due INTO inv_balance FROM invoice WHERE invoice_id = NEW.original_invoice_id;
        IF NEW.amount > inv_balance THEN
            RAISE EXCEPTION 'Credit note amount (%) exceeds remaining invoice balance (%)', NEW.amount, inv_balance;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_credit_note_amount_check
    BEFORE INSERT ON credit_debit_note
    FOR EACH ROW EXECUTE FUNCTION fn_validate_credit_note_amount();

-- -------------------------------------------------------------------------------------
-- 4.6 RECURRING INVOICE SCHEDULE (§46)
-- -------------------------------------------------------------------------------------

CREATE TABLE recurring_invoice_schedule (
    schedule_id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          UUID NOT NULL,
    customer_id                       UUID NOT NULL REFERENCES customer(customer_id),
    template_invoice_id                 UUID,  -- reference invoice to clone line structure from
    frequency                             VARCHAR(20) NOT NULL,
                                             -- WEEKLY, MONTHLY, QUARTERLY, SEMI_ANNUAL, ANNUAL, CUSTOM
    interval_count                          INT NOT NULL DEFAULT 1,
    start_date                                DATE NOT NULL,
    end_date                                    DATE,           -- NULL = indefinite
    next_run_date                                 DATE NOT NULL,
    last_run_date                                   DATE,
    last_run_status                                   VARCHAR(20),  -- SUCCESS, FAILED, SKIPPED
    is_active                                           BOOLEAN NOT NULL DEFAULT TRUE,
    created_by_user_id                                    UUID NOT NULL,
    created_at                                              TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Idempotency guard for the batch job: one generated invoice per schedule per run-date
CREATE TABLE recurring_invoice_run_log (
    run_id                        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    schedule_id                     UUID NOT NULL REFERENCES recurring_invoice_schedule(schedule_id),
    run_date                          DATE NOT NULL,
    generated_invoice_id                 UUID REFERENCES invoice(invoice_id),
    status                                 VARCHAR(20) NOT NULL,  -- SUCCESS, FAILED
    error_message                            TEXT,
    executed_at                                TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (schedule_id, run_date)   -- prevents double-billing on retry
);

-- -------------------------------------------------------------------------------------
-- 4.7 RECEIPTS / COLLECTIONS (§47)
-- -------------------------------------------------------------------------------------

CREATE TABLE receipt (
    receipt_id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id                          UUID NOT NULL,
    receipt_number                    VARCHAR(40) NOT NULL,
    receipt_date                        DATE NOT NULL,
    customer_id                           UUID NOT NULL REFERENCES customer(customer_id),
    payment_method                          VARCHAR(20) NOT NULL,
        -- CASH, BANK_TRANSFER, CHEQUE, QR, MOBILE_WALLET, CREDIT_CARD, PAYMENT_GATEWAY
    bank_account_id                            UUID,   -- FK -> banking module (future)
    reference_number                             VARCHAR(100),
    currency                                       CHAR(3) NOT NULL DEFAULT 'NPR',
    exchange_rate                                    NUMERIC(12,6) NOT NULL DEFAULT 1,
    total_amount                                       NUMERIC(18,2) NOT NULL,
    is_advance                                           BOOLEAN NOT NULL DEFAULT FALSE,
    status                                                 VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
                                                              -- DRAFT, POSTED, VOID
    journal_id                                               UUID REFERENCES accounting.journal_entry(journal_id),
    created_by_user_id                                         UUID NOT NULL,
    created_at                                                   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (org_id, receipt_number),
    CHECK (total_amount > 0)
);

-- A receipt can be allocated across multiple invoices (partial/advance payments)
CREATE TABLE receipt_allocation (
    allocation_id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id                     UUID NOT NULL REFERENCES receipt(receipt_id) ON DELETE CASCADE,
    invoice_id                       UUID NOT NULL REFERENCES invoice(invoice_id),
    allocated_amount                   NUMERIC(18,2) NOT NULL,
    CHECK (allocated_amount > 0)
);
CREATE INDEX idx_receipt_alloc_invoice ON receipt_allocation (invoice_id);

-- Void guard: cannot void an invoice with active (non-reversed) receipt allocations
CREATE OR REPLACE FUNCTION fn_block_void_with_active_receipt() RETURNS TRIGGER AS $$
DECLARE
    allocated_total NUMERIC(18,2);
BEGIN
    IF NEW.status = 'VOID' AND OLD.status <> 'VOID' THEN
        SELECT COALESCE(SUM(ra.allocated_amount), 0) INTO allocated_total
        FROM receipt_allocation ra
        JOIN receipt r ON r.receipt_id = ra.receipt_id
        WHERE ra.invoice_id = NEW.invoice_id AND r.status = 'POSTED';

        IF allocated_total > 0 THEN
            RAISE EXCEPTION 'Cannot void invoice with active receipt allocations (NPR %). Reverse the receipt first.', allocated_total;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_invoice_void_guard
    BEFORE UPDATE ON invoice
    FOR EACH ROW EXECUTE FUNCTION fn_block_void_with_active_receipt();

-- -------------------------------------------------------------------------------------
-- 4.8 CUSTOMER AGING (§48) — implemented as a view for real-time computation
-- -------------------------------------------------------------------------------------

CREATE VIEW v_customer_aging AS
SELECT
    i.org_id,
    i.customer_id,
    c.customer_name,
    i.invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.due_date,
    i.balance_due,
    (CURRENT_DATE - i.due_date) AS days_overdue,
    CASE
        WHEN CURRENT_DATE <= i.due_date THEN 'CURRENT'
        WHEN (CURRENT_DATE - i.due_date) BETWEEN 1 AND 30 THEN '1-30_DAYS'
        WHEN (CURRENT_DATE - i.due_date) BETWEEN 31 AND 60 THEN '31-60_DAYS'
        WHEN (CURRENT_DATE - i.due_date) BETWEEN 61 AND 90 THEN '61-90_DAYS'
        WHEN (CURRENT_DATE - i.due_date) BETWEEN 91 AND 180 THEN '91-180_DAYS'
        WHEN (CURRENT_DATE - i.due_date) BETWEEN 181 AND 365 THEN '181-365_DAYS'
        ELSE 'OVER_365_DAYS'
    END AS aging_bucket
FROM invoice i
JOIN customer c ON c.customer_id = i.customer_id
WHERE i.balance_due > 0 AND i.status NOT IN ('VOID','DRAFT');

-- =====================================================================================
-- END SECTION 4 — e-BILLING MODULE
-- =====================================================================================
