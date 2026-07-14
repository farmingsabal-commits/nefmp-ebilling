using NEFMP.Ebilling.Domain.Enums;
using NEFMP.Ebilling.Domain.Exceptions;

namespace NEFMP.Ebilling.Domain.Entities;

public class CreditDebitNote
{
    public Guid NoteId { get; private set; }
    public Guid OrgId { get; private set; }
    public NoteType NoteType { get; private set; }
    public string? NoteNumber { get; private set; }
    public DateOnly NoteDate { get; private set; }
    public Guid OriginalInvoiceId { get; private set; }
    public string Reason { get; private set; } = default!;
    public decimal Amount { get; private set; }
    public decimal VatAmount { get; private set; }
    public string Status { get; private set; } = "DRAFT"; // DRAFT, APPROVED, POSTED, VOID
    public Guid? JournalId { get; private set; }
    public Guid CreatedByUserId { get; private set; }

    private CreditDebitNote() { }

    /// <summary>
    /// Mirrors fn_validate_credit_note_amount() DB trigger: a credit note can never
    /// exceed the invoice's current remaining balance. Debit notes have no such cap.
    /// </summary>
    public static CreditDebitNote Create(
        Guid orgId, NoteType noteType, DateOnly noteDate, Guid originalInvoiceId,
        string reason, decimal amount, decimal vatAmount, decimal invoiceBalanceDue, Guid createdByUserId)
    {
        if (amount <= 0) throw new ArgumentOutOfRangeException(nameof(amount));
        if (noteType == NoteType.Credit && amount > invoiceBalanceDue)
            throw new CreditNoteExceedsBalanceException(amount, invoiceBalanceDue);

        return new CreditDebitNote
        {
            NoteId = Guid.NewGuid(),
            OrgId = orgId,
            NoteType = noteType,
            NoteDate = noteDate,
            OriginalInvoiceId = originalInvoiceId,
            Reason = reason,
            Amount = amount,
            VatAmount = vatAmount,
            CreatedByUserId = createdByUserId,
            Status = "DRAFT"
        };
    }

    public void AssignNumber(string noteNumber) => NoteNumber = noteNumber;

    public void Post(Guid journalId)
    {
        if (Status != "APPROVED")
            throw new InvalidStatusTransitionException(Status, "POSTED");
        JournalId = journalId;
        Status = "POSTED";
    }

    public void Approve()
    {
        if (Status != "DRAFT")
            throw new InvalidStatusTransitionException(Status, "APPROVED");
        Status = "APPROVED";
    }
}

public class Receipt
{
    private readonly List<ReceiptAllocation> _allocations = new();

    public Guid ReceiptId { get; private set; }
    public Guid OrgId { get; private set; }
    public string? ReceiptNumber { get; private set; }
    public DateOnly ReceiptDate { get; private set; }
    public Guid CustomerId { get; private set; }
    public PaymentMethod PaymentMethod { get; private set; }
    public string? ReferenceNumber { get; set; }
    public string Currency { get; private set; } = "NPR";
    public decimal ExchangeRate { get; private set; } = 1m;
    public decimal TotalAmount { get; private set; }
    public bool IsAdvance { get; private set; }
    public string Status { get; private set; } = "DRAFT"; // DRAFT, POSTED, VOID
    public Guid? JournalId { get; private set; }
    public Guid CreatedByUserId { get; private set; }

    public IReadOnlyList<ReceiptAllocation> Allocations => _allocations.AsReadOnly();

    private Receipt() { }

    public static Receipt Create(
        Guid orgId, Guid customerId, DateOnly receiptDate, PaymentMethod method,
        decimal totalAmount, Guid createdByUserId, string currency = "NPR", decimal exchangeRate = 1m)
    {
        if (totalAmount <= 0) throw new ArgumentOutOfRangeException(nameof(totalAmount));

        return new Receipt
        {
            ReceiptId = Guid.NewGuid(),
            OrgId = orgId,
            CustomerId = customerId,
            ReceiptDate = receiptDate,
            PaymentMethod = method,
            TotalAmount = totalAmount,
            Currency = currency,
            ExchangeRate = exchangeRate,
            CreatedByUserId = createdByUserId
        };
    }

    /// <summary>
    /// Allocates part of this receipt to an invoice. The caller (application service)
    /// is responsible for validating allocatedAmount against the invoice's live balance
    /// due (requires a DB round-trip) — this method only enforces that the SUM of all
    /// allocations on this receipt never exceeds the receipt's own total.
    /// </summary>
    public void AllocateToInvoice(Guid invoiceId, decimal allocatedAmount)
    {
        if (allocatedAmount <= 0) throw new ArgumentOutOfRangeException(nameof(allocatedAmount));

        var newTotal = _allocations.Sum(a => a.AllocatedAmount) + allocatedAmount;
        if (newTotal > TotalAmount)
            throw new ReceiptAllocationMismatchException();

        _allocations.Add(new ReceiptAllocation(Guid.NewGuid(), ReceiptId, invoiceId, allocatedAmount));
    }

    public void ValidateFullyAllocated()
    {
        if (_allocations.Sum(a => a.AllocatedAmount) != TotalAmount)
            throw new ReceiptAllocationMismatchException();
    }

    public void AssignNumber(string receiptNumber) => ReceiptNumber = receiptNumber;

    public void Post(Guid journalId)
    {
        JournalId = journalId;
        Status = "POSTED";
    }

    public void Void()
    {
        Status = "VOID";
    }
}

public sealed record ReceiptAllocation(Guid AllocationId, Guid ReceiptId, Guid InvoiceId, decimal AllocatedAmount);
