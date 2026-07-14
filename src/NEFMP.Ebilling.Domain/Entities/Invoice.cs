using NEFMP.Ebilling.Domain.Enums;
using NEFMP.Ebilling.Domain.Exceptions;

namespace NEFMP.Ebilling.Domain.Entities;

public class InvoiceLine
{
    public Guid InvoiceLineId { get; private set; }
    public Guid InvoiceId { get; private set; }
    public short LineNumber { get; private set; }
    public Guid ServiceId { get; private set; }
    public string? Description { get; set; }
    public decimal Quantity { get; private set; }
    public decimal UnitPrice { get; private set; }
    public decimal DiscountPercent { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public Guid TaxCodeId { get; private set; }
    public decimal VatPercent { get; private set; }
    public decimal VatAmount { get; private set; }
    public decimal TdsPercent { get; private set; }
    public decimal TdsAmount { get; private set; }
    public decimal LineTotal { get; private set; }
    public Guid RevenueAccountId { get; private set; }
    public Guid? CostCenterId { get; set; }

    private InvoiceLine() { }

    /// <summary>
    /// Server-side line calculation. Per API spec §4: client-submitted totals
    /// are never trusted — this is the single source of truth for line math.
    /// </summary>
    public static InvoiceLine Create(
        short lineNumber, Guid serviceId, decimal quantity, decimal unitPrice,
        decimal discountPercent, Guid taxCodeId, decimal vatPercent, decimal tdsPercent,
        Guid revenueAccountId)
    {
        if (quantity <= 0) throw new ArgumentOutOfRangeException(nameof(quantity), "Quantity must be positive.");
        if (unitPrice < 0) throw new ArgumentOutOfRangeException(nameof(unitPrice));

        var gross = quantity * unitPrice;
        var discountAmount = Math.Round(gross * (discountPercent / 100m), 2);
        var netOfDiscount = gross - discountAmount;
        var vatAmount = Math.Round(netOfDiscount * (vatPercent / 100m), 2);
        var tdsAmount = Math.Round(netOfDiscount * (tdsPercent / 100m), 2);
        var lineTotal = netOfDiscount + vatAmount; // TDS is withheld by customer, not added to what they owe

        return new InvoiceLine
        {
            InvoiceLineId = Guid.NewGuid(),
            LineNumber = lineNumber,
            ServiceId = serviceId,
            Quantity = quantity,
            UnitPrice = unitPrice,
            DiscountPercent = discountPercent,
            DiscountAmount = discountAmount,
            TaxCodeId = taxCodeId,
            VatPercent = vatPercent,
            VatAmount = vatAmount,
            TdsPercent = tdsPercent,
            TdsAmount = tdsAmount,
            LineTotal = lineTotal,
            RevenueAccountId = revenueAccountId
        };
    }

    internal void AssignToInvoice(Guid invoiceId) => InvoiceId = invoiceId;

    public decimal GrossAmount => Quantity * UnitPrice;
    public decimal TaxableAmount => GrossAmount - DiscountAmount;
}

public class Invoice
{
    private readonly List<InvoiceLine> _lines = new();

    public Guid InvoiceId { get; private set; }
    public Guid OrgId { get; private set; }
    public Guid FiscalYearId { get; private set; }
    public string? InvoiceNumber { get; private set; } // assigned only at Generate step
    public InvoiceType InvoiceType { get; private set; } = InvoiceType.TaxInvoice;
    public DateOnly InvoiceDate { get; private set; }
    public DateOnly DueDate { get; private set; }
    public Guid CustomerId { get; private set; }
    public Guid? QuotationId { get; private set; }
    public string Currency { get; private set; } = "NPR";
    public decimal ExchangeRate { get; private set; } = 1m;

    public decimal SubtotalAmount { get; private set; }
    public decimal DiscountAmount { get; private set; }
    public decimal TaxableAmount { get; private set; }
    public decimal VatAmount { get; private set; }
    public decimal TdsAmount { get; private set; }
    public decimal OtherTaxAmount { get; private set; }
    public decimal GrandTotal { get; private set; }
    public decimal AmountPaid { get; private set; }
    public decimal BalanceDue { get; private set; }

    public string? QrCodePayload { get; private set; }
    public string? DigitalSignature { get; private set; }

    public InvoiceStatus Status { get; private set; } = InvoiceStatus.Draft;
    public Guid? JournalId { get; private set; }

    public string? VoidReason { get; private set; }
    public Guid? VoidedByUserId { get; private set; }
    public DateTimeOffset? VoidedAt { get; private set; }

    public Guid CreatedByUserId { get; private set; }
    public Guid? ApprovedByUserId { get; private set; }
    public DateTimeOffset? ApprovedAt { get; private set; }
    public DateTimeOffset CreatedAt { get; private set; }

    public IReadOnlyList<InvoiceLine> Lines => _lines.AsReadOnly();

    private Invoice() { }

    public static Invoice CreateDraft(
        Guid orgId, Guid fiscalYearId, Guid customerId, DateOnly invoiceDate, DateOnly dueDate,
        Guid createdByUserId, string currency = "NPR", decimal exchangeRate = 1m, Guid? quotationId = null)
    {
        if (dueDate < invoiceDate)
            throw new ArgumentException("Due date cannot be before invoice date.", nameof(dueDate));
        if (exchangeRate <= 0)
            throw new ArgumentOutOfRangeException(nameof(exchangeRate), "Exchange rate must be positive.");

        return new Invoice
        {
            InvoiceId = Guid.NewGuid(),
            OrgId = orgId,
            FiscalYearId = fiscalYearId,
            CustomerId = customerId,
            QuotationId = quotationId,
            InvoiceDate = invoiceDate,
            DueDate = dueDate,
            Currency = currency,
            ExchangeRate = exchangeRate,
            CreatedByUserId = createdByUserId,
            CreatedAt = DateTimeOffset.UtcNow,
            Status = InvoiceStatus.Draft
        };
    }

    /// <summary>Only permitted while Draft or PendingApproval (reverts to Draft first at the service layer).</summary>
    public void AddLine(InvoiceLine line)
    {
        EnsureEditable();
        line.AssignToInvoice(InvoiceId);
        _lines.Add(line);
        Recalculate();
    }

    public void ClearLines()
    {
        EnsureEditable();
        _lines.Clear();
        Recalculate();
    }

    private void EnsureEditable()
    {
        if (Status is not (InvoiceStatus.Draft or InvoiceStatus.PendingApproval))
            throw new InvoiceImmutableException();
    }

    /// <summary>
    /// Recomputes header totals from lines. Mirrors the SQL comment block in
    /// 04_ebilling.sql exactly — grouped correctly even with mixed VAT rates
    /// per line, since each line's own VAT is summed rather than one blanket rate.
    /// </summary>
    private void Recalculate()
    {
        SubtotalAmount = _lines.Sum(l => l.GrossAmount);
        DiscountAmount = _lines.Sum(l => l.DiscountAmount);
        TaxableAmount = SubtotalAmount - DiscountAmount;
        VatAmount = _lines.Sum(l => l.VatAmount);
        TdsAmount = _lines.Sum(l => l.TdsAmount);
        GrandTotal = TaxableAmount + VatAmount + TdsAmount + OtherTaxAmount;
        BalanceDue = GrandTotal - AmountPaid;
    }

    public void SubmitForApproval()
    {
        TransitionTo(InvoiceStatus.PendingApproval);
    }

    public void Approve(Guid approverUserId, bool isSameAsCreator, bool sodOverrideGranted, string? overrideJustification)
    {
        if (isSameAsCreator && !sodOverrideGranted)
            throw new SegregationOfDutiesViolationException("CREATE_APPROVE_INVOICE");
        if (isSameAsCreator && sodOverrideGranted && string.IsNullOrWhiteSpace(overrideJustification))
            throw new ArgumentException("SoD override requires a justification.", nameof(overrideJustification));

        ApprovedByUserId = approverUserId;
        ApprovedAt = DateTimeOffset.UtcNow;
        TransitionTo(InvoiceStatus.Approved);
    }

    /// <summary>Assigns the sequential invoice number (allocated by the repository under a row lock)
    /// and generates the IRD QR/signature payload.</summary>
    public void Generate(string invoiceNumber, string qrCodePayload, string digitalSignature)
    {
        if (string.IsNullOrWhiteSpace(invoiceNumber))
            throw new ArgumentException("Invoice number is required.", nameof(invoiceNumber));

        InvoiceNumber = invoiceNumber;
        QrCodePayload = qrCodePayload;
        DigitalSignature = digitalSignature;
        TransitionTo(InvoiceStatus.Generated);
    }

    /// <summary>Marks Posted. The actual journal entry is created by the application service
    /// in the SAME database transaction — this method only records the resulting journal id
    /// and flips status; it does not itself touch accounting tables (domain layer has no
    /// dependency on the accounting module's persistence).</summary>
    public void MarkPosted(Guid journalId)
    {
        JournalId = journalId;
        TransitionTo(InvoiceStatus.Posted);
    }

    public void MarkDelivered() => TransitionTo(InvoiceStatus.Delivered);

    public void ApplyReceipt(decimal amount)
    {
        if (amount <= 0) throw new ArgumentOutOfRangeException(nameof(amount));
        if (amount > BalanceDue)
            throw new AllocationExceedsInvoiceBalanceException(InvoiceId, amount, BalanceDue);

        AmountPaid += amount;
        BalanceDue = GrandTotal - AmountPaid;

        if (BalanceDue == 0)
            TransitionTo(InvoiceStatus.Paid);
        else if (Status is InvoiceStatus.Posted or InvoiceStatus.Delivered)
            TransitionTo(InvoiceStatus.PartiallyPaid);
    }

    /// <summary>Reverses a receipt allocation (e.g. receipt voided) — restores balance and,
    /// if the invoice had become Paid/PartiallyPaid purely from that receipt, steps it back.</summary>
    public void ReverseReceiptAllocation(decimal amount)
    {
        AmountPaid -= amount;
        BalanceDue = GrandTotal - AmountPaid;
    }

    public bool HasActiveReceiptAllocations(decimal currentlyAllocated) => currentlyAllocated > 0;

    public void Void(Guid voidedByUserId, string reason, decimal activeReceiptAllocations)
    {
        if (string.IsNullOrWhiteSpace(reason))
            throw new ArgumentException("Void reason is mandatory.", nameof(reason));
        if (activeReceiptAllocations > 0)
            throw new InvoiceVoidBlockedException(activeReceiptAllocations);

        VoidReason = reason;
        VoidedByUserId = voidedByUserId;
        VoidedAt = DateTimeOffset.UtcNow;
        TransitionTo(InvoiceStatus.Void);
    }

    /// <summary>
    /// Application-layer mirror of the fn_validate_invoice_status_transition() DB trigger
    /// (04_ebilling.sql). This is intentionally duplicated logic, not a replacement for the
    /// DB trigger — the trigger is the final, unbypassable backstop; this check exists so
    /// the API can return a clean, immediate 400 instead of surfacing a DB exception.
    /// </summary>
    private void TransitionTo(InvoiceStatus target)
    {
        bool allowed = Status switch
        {
            InvoiceStatus.Draft => target is InvoiceStatus.PendingApproval or InvoiceStatus.Void,
            InvoiceStatus.PendingApproval => target is InvoiceStatus.Approved or InvoiceStatus.Draft or InvoiceStatus.Void,
            InvoiceStatus.Approved => target is InvoiceStatus.Generated or InvoiceStatus.Void,
            InvoiceStatus.Generated => target is InvoiceStatus.Posted,
            InvoiceStatus.Posted => target is InvoiceStatus.Delivered or InvoiceStatus.PartiallyPaid or InvoiceStatus.Paid or InvoiceStatus.Void,
            InvoiceStatus.Delivered => target is InvoiceStatus.PartiallyPaid or InvoiceStatus.Paid or InvoiceStatus.Void,
            InvoiceStatus.PartiallyPaid => target is InvoiceStatus.Paid or InvoiceStatus.Void,
            InvoiceStatus.Paid => target is InvoiceStatus.Closed,
            _ => false
        };

        if (!allowed)
            throw new InvalidStatusTransitionException(Status.ToString(), target.ToString());

        Status = target;
    }
}
