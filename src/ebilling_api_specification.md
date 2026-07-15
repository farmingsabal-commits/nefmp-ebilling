# NEFMP e-Billing Module — API Specification (Phase 1, Increment 1)

Base path: `/api/v1/org/{orgId}/ebilling`
Auth: Bearer token (Control Plane issued) — every request resolves `global_user_id` → tenant DB connection → `app_user` row for that org.
All list endpoints support `?page=&pageSize=&sortBy=&filter[...]=`.

Scope confirmed for this increment: Immediate Revenue Recognition only; no Sales Order (Quotation → Invoice direct path); IRD live API stubbed (data model + QR/signature fields populated, no outbound government call yet).

---

## 1. Customer Master

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/customers` | Create customer |
| GET | `/customers/{id}` | Get customer detail |
| GET | `/customers` | List/search customers |
| PUT | `/customers/{id}` | Update customer (blocked fields: customer_code once invoices exist) |
| POST | `/customers/{id}/attachments` | Upload KYC/contract documents |
| GET | `/customers/{id}/aging` | Customer-specific aging summary |
| GET | `/customers/{id}/statement` | Statement of account (date range) |

**CreateCustomerRequest**
```json
{
  "customerCode": "CUST-001",
  "customerName": "Himalayan Traders Pvt Ltd",
  "customerType": "COMPANY",
  "panNumber": "300123456",
  "vatNumber": "300123456",
  "email": "accounts@himalayan.com",
  "creditLimit": 500000.00,
  "creditDays": 30,
  "currency": "NPR",
  "taxCategory": "STANDARD"
}
```
Validation: `customerCode` unique per org; `panNumber`/`vatNumber` format-checked (9-digit Nepal PAN); `creditLimit >= 0`.

---

## 2. Service Catalogue

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/services` | Create service |
| GET | `/services` | List services (filter by category, status) |
| PUT | `/services/{id}` | Update service (rate changes don't retroactively affect existing invoice lines) |

---

## 3. Quotation

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/quotations` | Create draft quotation |
| POST | `/quotations/{id}/send` | Mark SENT (triggers email, future) |
| POST | `/quotations/{id}/accept` | Customer acceptance recorded |
| POST | `/quotations/{id}/convert-to-invoice` | Converts to a DRAFT invoice, copying lines |
| GET | `/quotations/{id}` | Get detail incl. version history |

---

## 4. Invoice — the core module

| Method | Endpoint | Purpose | Business Logic |
|---|---|---|---|
| POST | `/invoices` | Create DRAFT invoice | Validates fiscal period open, customer active, service active/posting-allowed. Server computes line VAT/TDS and footer totals — client-submitted totals are **recalculated, never trusted** |
| PUT | `/invoices/{id}` | Update DRAFT/PENDING_APPROVAL invoice | Rejected if invoice status ≥ APPROVED (enforced by DB trigger as final backstop) |
| POST | `/invoices/{id}/submit-for-approval` | DRAFT → PENDING_APPROVAL | |
| POST | `/invoices/{id}/approve` | PENDING_APPROVAL → APPROVED | Checks SoD: approver ≠ creator unless override permission held + justification supplied |
| POST | `/invoices/{id}/generate` | APPROVED → GENERATED | Allocates invoice number from `document_numbering_rule` (row-locked), generates QR payload + digital signature |
| POST | `/invoices/{id}/post` | GENERATED → POSTED | **Atomically**: creates `journal_entry` + 3 `journal_line` rows (Dr AR, Cr Revenue, Cr VAT Payable) in the same DB transaction as the status update. If journal posting fails, invoice status change rolls back too. |
| POST | `/invoices/{id}/void` | → VOID | Requires reason (mandatory field) + authorization; blocked by DB trigger if active receipt allocations exist |
| GET | `/invoices/{id}` | Get full invoice incl. lines, linked journal, receipt allocations | |
| GET | `/invoices` | List/search (filter: status, customer, date range, branch) | |
| GET | `/invoices/{id}/pdf` | Rendered IRD-format invoice PDF | |

**Invoice Line Server-Side Calculation (never trust client math):**
```
line_total = (quantity * unit_price) - discount_amount
vat_amount = line_total * (tax_code.rate_percent / 100)   [if tax_type = VAT]
tds_amount = line_total * (tax_code.rate_percent / 100)   [if tds applicable]

invoice.subtotal_amount = SUM(line quantity * unit_price)
invoice.discount_amount = SUM(line discount_amount)
invoice.taxable_amount  = subtotal - discount
invoice.vat_amount      = SUM(line vat_amount)   -- grouped correctly even with mixed tax rates per line
invoice.grand_total     = taxable_amount + vat_amount + tds_amount + other_tax_amount
invoice.balance_due     = grand_total - amount_paid
```

**Posting rule executed atomically on `/post` (§26 Example 1):**
```
Dr  Accounts Receivable    grand_total
Cr  Service Revenue        taxable_amount   (per revenue_account_id, may split by line)
Cr  VAT Payable            vat_amount
```

---

## 5. Credit / Debit Note

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/credit-notes` | Create against an original invoice; server checks `amount <= invoice.balance_due` (DB trigger is the backstop) |
| POST | `/debit-notes` | Create for additional billing |
| POST | `/credit-notes/{id}/approve` | Approve + post reversing journal |

---

## 6. Recurring Billing

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/recurring-schedules` | Define schedule from a template invoice |
| PUT | `/recurring-schedules/{id}/pause` \| `/resume` | Control automation |
| GET | `/recurring-schedules/{id}/run-log` | Audit of past generations (idempotency log) |

Batch job (`recurring_invoice_run_log`) design: runs daily, selects schedules where `next_run_date <= today AND is_active`, and for each schedule performs a single DB transaction: insert run-log row (unique on `schedule_id + run_date` — prevents double-billing on retry) → generate invoice → advance `next_run_date`.

---

## 7. Receipts / Collections

| Method | Endpoint | Purpose |
|---|---|---|
| POST | `/receipts` | Record a receipt with one or more `allocations[]` against open invoices |
| POST | `/receipts/{id}/void` | Reverse a receipt (required before the related invoice can itself be voided) |
| GET | `/receipts` | List |

**CreateReceiptRequest**
```json
{
  "customerId": "c1111111-...",
  "receiptDate": "2026-07-25",
  "paymentMethod": "BANK_TRANSFER",
  "totalAmount": 5000.00,
  "allocations": [
    { "invoiceId": "e1111111-...", "allocatedAmount": 5000.00 }
  ]
}
```
Validation: `SUM(allocations.allocatedAmount) == totalAmount`; each `allocatedAmount <= invoice.balance_due` at time of allocation.

---

## 8. Reporting

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/reports/aging` | Backed by `v_customer_aging` view |
| GET | `/reports/sales-register` | |
| GET | `/reports/vat-sales-register` | |
| GET | `/reports/revenue-by-service` | |

All report endpoints support `?format=pdf|excel|csv` and support drill-down via `?drillFrom=invoiceId`.

---

## 9. Error Response Convention

```json
{
  "error": {
    "code": "INVOICE_IMMUTABLE",
    "message": "Posted invoice financial amounts are immutable. Use a Credit/Debit Note.",
    "field": null
  }
}
```
Database-trigger exceptions (e.g. `INVOICE_IMMUTABLE`, `CREDIT_NOTE_EXCEEDS_BALANCE`, `INVALID_STATUS_TRANSITION`) are caught at the repository layer and mapped to stable error codes — the API never leaks raw PostgreSQL exception text to the client.

---

## 10. Non-Functional Requirements Carried From SRS

- Invoice creation: < 2 seconds (§221)
- Every `/post`, `/void`, `/approve` action writes to `audit.audit_trail` (actor, IP, device, reason) in the same transaction
- All list/search endpoints must use the composite index `(org_id, fiscal_year_id, customer_id, status, invoice_date)` — query plans should be checked in review to confirm index usage before merging

---

## Deferred to Later Increments (explicitly out of scope now)

- Sales Order module (§39) — Quotation converts directly to Invoice for now
- Deferred/Milestone/Percentage-of-Completion revenue recognition (§44) — Immediate only
- Live IRD government API submission — data model + QR/signature ready, outbound call is a stub
- Full Workflow Engine-driven approval routing (§161-168) — approval today is a single-step role check; multi-level configurable workflow arrives with the dedicated Workflow Engine module
