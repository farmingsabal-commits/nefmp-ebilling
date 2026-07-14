namespace NEFMP.Ebilling.Domain.Enums;

public enum InvoiceStatus
{
    Draft,
    PendingApproval,
    Approved,
    Generated,
    Posted,
    Delivered,
    PartiallyPaid,
    Paid,
    Closed,
    Void
}

public enum InvoiceType
{
    TaxInvoice,
    AbbreviatedTaxInvoice,
    ExportInvoice,
    ProformaInvoice,
    RecurringInvoice,
    AdvanceInvoice,
    MilestoneInvoice,
    ZeroRatedInvoice,
    TaxExemptInvoice
}

public enum RevenueRecognitionMethod
{
    Immediate
    // Milestone, PercentageOfCompletion, TimeBased, Subscription, Deferred — Phase 2
}

public enum NoteType
{
    Credit,
    Debit
}

public enum PaymentMethod
{
    Cash,
    BankTransfer,
    Cheque,
    Qr,
    MobileWallet,
    CreditCard,
    PaymentGateway
}

public enum TaxType
{
    Vat,
    Tds
}
