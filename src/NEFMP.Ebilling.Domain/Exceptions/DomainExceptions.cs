namespace NEFMP.Ebilling.Domain.Exceptions;

/// <summary>
/// Base type for all domain rule violations. The Api layer catches this
/// (never raw framework/db exceptions) and maps ErrorCode to the stable
/// client-facing error contract described in the API specification, §9.
/// </summary>
public abstract class DomainException : Exception
{
    public abstract string ErrorCode { get; }
    public string? Field { get; }

    protected DomainException(string message, string? field = null) : base(message)
    {
        Field = field;
    }
}

public sealed class InvalidStatusTransitionException : DomainException
{
    public override string ErrorCode => "INVALID_STATUS_TRANSITION";
    public InvalidStatusTransitionException(string from, string to)
        : base($"Invalid invoice status transition: {from} -> {to}") { }
}

public sealed class InvoiceImmutableException : DomainException
{
    public override string ErrorCode => "INVOICE_IMMUTABLE";
    public InvoiceImmutableException()
        : base("Posted invoice financial amounts are immutable. Use a Credit/Debit Note.") { }
}

public sealed class CreditNoteExceedsBalanceException : DomainException
{
    public override string ErrorCode => "CREDIT_NOTE_EXCEEDS_BALANCE";
    public CreditNoteExceedsBalanceException(decimal amount, decimal balance)
        : base($"Credit note amount ({amount:F2}) exceeds remaining invoice balance ({balance:F2})", "amount") { }
}

public sealed class InvoiceVoidBlockedException : DomainException
{
    public override string ErrorCode => "INVOICE_VOID_BLOCKED_ACTIVE_RECEIPT";
    public InvoiceVoidBlockedException(decimal allocatedAmount)
        : base($"Cannot void invoice with active receipt allocations (NPR {allocatedAmount:F2}). Reverse the receipt first.") { }
}

public sealed class FiscalPeriodClosedException : DomainException
{
    public override string ErrorCode => "FISCAL_PERIOD_CLOSED";
    public FiscalPeriodClosedException(DateOnly date)
        : base($"Accounting period containing {date:yyyy-MM-dd} is closed or locked.", "invoiceDate") { }
}

public sealed class InactiveEntityException : DomainException
{
    public override string ErrorCode => "INACTIVE_ENTITY";
    public InactiveEntityException(string entityType, Guid id)
        : base($"{entityType} '{id}' is inactive and cannot be used on new transactions.") { }
}

public sealed class DuplicateDocumentNumberException : DomainException
{
    public override string ErrorCode => "DUPLICATE_DOCUMENT_NUMBER";
    public DuplicateDocumentNumberException(string documentNumber)
        : base($"Document number '{documentNumber}' already exists for this organization.", "invoiceNumber") { }
}

public sealed class SegregationOfDutiesViolationException : DomainException
{
    public override string ErrorCode => "SOD_VIOLATION";
    public SegregationOfDutiesViolationException(string rule)
        : base($"Segregation of Duties rule violated: {rule}. An override with justification is required.") { }
}

public sealed class UnbalancedJournalException : DomainException
{
    public override string ErrorCode => "UNBALANCED_JOURNAL";
    public UnbalancedJournalException(decimal debit, decimal credit)
        : base($"Journal entry is not balanced: total debit ({debit:F2}) != total credit ({credit:F2})") { }
}

public sealed class ReceiptAllocationMismatchException : DomainException
{
    public override string ErrorCode => "RECEIPT_ALLOCATION_MISMATCH";
    public ReceiptAllocationMismatchException()
        : base("Sum of receipt allocations must equal the receipt total amount.", "allocations") { }
}

public sealed class AllocationExceedsInvoiceBalanceException : DomainException
{
    public override string ErrorCode => "ALLOCATION_EXCEEDS_BALANCE";
    public AllocationExceedsInvoiceBalanceException(Guid invoiceId, decimal amount, decimal balance)
        : base($"Allocation of {amount:F2} to invoice {invoiceId} exceeds its balance due of {balance:F2}.") { }
}
