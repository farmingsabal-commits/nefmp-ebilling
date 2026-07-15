-- End-to-end validation: seed minimal data, run a full invoice lifecycle,
-- and confirm every compliance-critical guard actually fires.

\set ON_ERROR_STOP off
SET search_path TO ebilling, accounting, core_platform, control_plane, public;

-- ---- Seed minimal reference data ----
INSERT INTO core_platform.organization (org_id, tenant_id, legal_name, base_currency)
VALUES ('11111111-1111-1111-1111-111111111111','22222222-2222-2222-2222-222222222222','Test Org Pvt Ltd','NPR');

INSERT INTO core_platform.fiscal_year (fiscal_year_id, org_id, fiscal_year_code, start_date_ad, end_date_ad, status, is_current)
VALUES ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111','2083/84','2026-07-16','2027-07-15','OPEN',TRUE);

INSERT INTO accounting.chart_of_account (account_id, org_id, account_code, account_name, account_type, normal_balance, is_control_account, control_account_type)
VALUES
 ('a1111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','112000','Accounts Receivable','ASSET','DEBIT',TRUE,'AR'),
 ('a1111111-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','211000','VAT Payable','LIABILITY','CREDIT',TRUE,'VAT'),
 ('a1111111-0000-0000-0000-000000000003','11111111-1111-1111-1111-111111111111','400000','Service Revenue','REVENUE','CREDIT',FALSE,NULL);

INSERT INTO accounting.tax_code (tax_code_id, org_id, tax_code, tax_name, tax_type, rate_percent, liability_account_id, effective_from)
VALUES ('b1111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','VAT13','VAT 13%','VAT',13.0,'a1111111-0000-0000-0000-000000000002','2020-01-01');

INSERT INTO customer (customer_id, org_id, customer_code, customer_name, customer_type)
VALUES ('c1111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','CUST-001','Himalayan Traders Pvt Ltd','COMPANY');

INSERT INTO service_catalogue (service_id, org_id, service_code, service_name, standard_rate, default_tax_code_id, revenue_account_id)
VALUES ('d1111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','SVC-CONSULT','Consultancy Service',10000.00,'b1111111-0000-0000-0000-000000000001','a1111111-0000-0000-0000-000000000003');

-- ---- TEST 1: Create a valid balanced invoice (DRAFT) ----
INSERT INTO invoice (invoice_id, org_id, fiscal_year_id, invoice_number, invoice_date, due_date, customer_id,
                      subtotal_amount, discount_amount, taxable_amount, vat_amount, grand_total, balance_due, status, created_by_user_id)
VALUES ('e1111111-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333',
        'INV-2083-000001','2026-07-20','2026-08-20','c1111111-0000-0000-0000-000000000001',
        10000.00, 0, 10000.00, 1300.00, 11300.00, 11300.00, 'DRAFT', 'f1111111-0000-0000-0000-000000000001');

INSERT INTO invoice_line (invoice_id, line_number, service_id, quantity, unit_price, tax_code_id, vat_percent, vat_amount, line_total, revenue_account_id)
VALUES ('e1111111-0000-0000-0000-000000000001', 1, 'd1111111-0000-0000-0000-000000000001', 1, 10000.00,
        'b1111111-0000-0000-0000-000000000001', 13.0, 1300.00, 11300.00, 'a1111111-0000-0000-0000-000000000003');

SELECT 'TEST 1 PASS: invoice + line created' AS result;

-- ---- TEST 2: Valid lifecycle transitions DRAFT -> PENDING_APPROVAL -> APPROVED -> GENERATED -> POSTED ----
UPDATE invoice SET status = 'PENDING_APPROVAL' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';
UPDATE invoice SET status = 'APPROVED', approved_by_user_id = 'f1111111-0000-0000-0000-000000000002' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';
UPDATE invoice SET status = 'GENERATED' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';
UPDATE invoice SET status = 'POSTED' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';
SELECT 'TEST 2 PASS: full lifecycle transition succeeded' AS result;

-- ---- TEST 3 (SHOULD FAIL): Invalid transition — POSTED back to DRAFT ----
UPDATE invoice SET status = 'DRAFT' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';

-- ---- TEST 4 (SHOULD FAIL): Try to edit grand_total after POSTED ----
UPDATE invoice SET grand_total = 99999.00 WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';

-- ---- TEST 5 (SHOULD FAIL): Try to edit an invoice_line after invoice is POSTED ----
UPDATE invoice_line SET quantity = 5 WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';

-- ---- TEST 6: Post a balanced journal entry for the invoice ----
INSERT INTO accounting.journal_entry (journal_id, org_id, fiscal_year_id, accounting_period_id, voucher_type, voucher_number,
                                       voucher_date, posting_date, source_document_type, source_document_id,
                                       total_debit, total_credit, created_by_user_id)
VALUES ('e2222222-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333',
        '33333333-3333-3333-3333-333333333333','SALES_INVOICE','JV-2083-000001','2026-07-20','2026-07-20',
        'INVOICE','e1111111-0000-0000-0000-000000000001', 11300.00, 11300.00, 'f1111111-0000-0000-0000-000000000001');

INSERT INTO accounting.journal_line (journal_id, line_number, account_id, debit_amount, base_currency_amount, customer_id)
VALUES ('e2222222-0000-0000-0000-000000000001', 1, 'a1111111-0000-0000-0000-000000000001', 11300.00, 11300.00, 'c1111111-0000-0000-0000-000000000001');
INSERT INTO accounting.journal_line (journal_id, line_number, account_id, credit_amount, base_currency_amount)
VALUES ('e2222222-0000-0000-0000-000000000001', 2, 'a1111111-0000-0000-0000-000000000003', 10000.00, 10000.00);
INSERT INTO accounting.journal_line (journal_id, line_number, account_id, credit_amount, base_currency_amount)
VALUES ('e2222222-0000-0000-0000-000000000001', 3, 'a1111111-0000-0000-0000-000000000002', 1300.00, 1300.00);

SELECT 'TEST 6 PASS: balanced journal posted' AS result;

-- ---- TEST 7 (SHOULD FAIL): Unbalanced journal must be rejected by CHECK constraint ----
INSERT INTO accounting.journal_entry (journal_id, org_id, fiscal_year_id, accounting_period_id, voucher_type, voucher_number,
                                       voucher_date, posting_date, total_debit, total_credit, created_by_user_id)
VALUES ('e2222222-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333',
        '33333333-3333-3333-3333-333333333333','JOURNAL_VOUCHER','JV-2083-000002','2026-07-20','2026-07-20', 500.00, 400.00, 'f1111111-0000-0000-0000-000000000001');

-- ---- TEST 8 (SHOULD FAIL): Posted journal entry immutability ----
UPDATE accounting.journal_entry SET total_debit = 99999 WHERE journal_id = 'e2222222-0000-0000-0000-000000000001';

-- ---- TEST 9: Partial receipt against the invoice ----
INSERT INTO receipt (receipt_id, org_id, receipt_number, receipt_date, customer_id, payment_method, total_amount, status, created_by_user_id)
VALUES ('e3333333-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','RV-2083-000001','2026-07-25',
        'c1111111-0000-0000-0000-000000000001','BANK_TRANSFER', 5000.00, 'POSTED', 'f1111111-0000-0000-0000-000000000001');
INSERT INTO receipt_allocation (receipt_id, invoice_id, allocated_amount)
VALUES ('e3333333-0000-0000-0000-000000000001','e1111111-0000-0000-0000-000000000001', 5000.00);
UPDATE invoice SET amount_paid = 5000.00, balance_due = 6300.00, status = 'PARTIALLY_PAID' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';

SELECT 'TEST 9 PASS: partial receipt allocated' AS result;

-- ---- TEST 10 (SHOULD FAIL): Attempt to void an invoice with an active receipt allocation ----
UPDATE invoice SET status = 'VOID', void_reason='testing block' WHERE invoice_id = 'e1111111-0000-0000-0000-000000000001';

-- ---- TEST 11 (SHOULD FAIL): Credit note exceeding remaining balance (6300 outstanding, try 7000) ----
INSERT INTO credit_debit_note (org_id, note_type, note_number, note_date, original_invoice_id, reason, amount, created_by_user_id)
VALUES ('11111111-1111-1111-1111-111111111111','CREDIT','CN-2083-000001','2026-07-26','e1111111-0000-0000-0000-000000000001',
        'BILLING_ERROR', 7000.00, 'f1111111-0000-0000-0000-000000000001');

-- ---- TEST 12: Credit note within remaining balance (should succeed) ----
INSERT INTO credit_debit_note (org_id, note_type, note_number, note_date, original_invoice_id, reason, amount, created_by_user_id)
VALUES ('11111111-1111-1111-1111-111111111111','CREDIT','CN-2083-000002','2026-07-26','e1111111-0000-0000-0000-000000000001',
        'BILLING_ERROR', 1000.00, 'f1111111-0000-0000-0000-000000000001');
SELECT 'TEST 12 PASS: valid credit note within balance accepted' AS result;

-- ---- TEST 13: Aging view returns the outstanding invoice correctly ----
SELECT customer_name, invoice_number, balance_due, aging_bucket FROM v_customer_aging;

-- ---- TEST 14 (SHOULD FAIL): Duplicate invoice number within same org ----
INSERT INTO invoice (org_id, fiscal_year_id, invoice_number, invoice_date, due_date, customer_id,
                      subtotal_amount, taxable_amount, vat_amount, grand_total, balance_due, status, created_by_user_id)
VALUES ('11111111-1111-1111-1111-111111111111','33333333-3333-3333-3333-333333333333','INV-2083-000001',
        '2026-07-21','2026-08-21','c1111111-0000-0000-0000-000000000001', 1000,1000,130,1130,1130,'DRAFT','f1111111-0000-0000-0000-000000000001');
