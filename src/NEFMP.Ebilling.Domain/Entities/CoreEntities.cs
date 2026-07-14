using NEFMP.Ebilling.Domain.Enums;

namespace NEFMP.Ebilling.Domain.Entities;

public class Customer
{
    public Guid CustomerId { get; private set; }
    public Guid OrgId { get; private set; }
    public string CustomerCode { get; private set; } = default!;
    public string CustomerName { get; set; } = default!;
    public string? LegalName { get; set; }
    public string CustomerType { get; set; } = "INDIVIDUAL"; // INDIVIDUAL, COMPANY, GOVERNMENT, NGO_INGO, FOREIGN
    public bool IsRelatedParty { get; set; }
    public string? PanNumber { get; set; }
    public string? VatNumber { get; set; }
    public string? Email { get; set; }
    public string? MobileNumber { get; set; }
    public decimal CreditLimit { get; set; }
    public int CreditDays { get; set; }
    public string Currency { get; set; } = "NPR";
    public Guid? DefaultArAccountId { get; set; }
    public string TaxCategory { get; set; } = "STANDARD"; // STANDARD, ZERO_RATED, EXEMPT
    public string Status { get; private set; } = "ACTIVE";
    public DateTimeOffset CreatedAt { get; private set; }

    private Customer() { }

    public static Customer Create(Guid orgId, string customerCode, string customerName, string customerType)
    {
        if (string.IsNullOrWhiteSpace(customerCode))
            throw new ArgumentException("Customer code is required.", nameof(customerCode));
        if (string.IsNullOrWhiteSpace(customerName))
            throw new ArgumentException("Customer name is required.", nameof(customerName));

        return new Customer
        {
            CustomerId = Guid.NewGuid(),
            OrgId = orgId,
            CustomerCode = customerCode,
            CustomerName = customerName,
            CustomerType = customerType,
            CreatedAt = DateTimeOffset.UtcNow
        };
    }

    public bool IsActive => Status == "ACTIVE";
}

public class ServiceCatalogueItem
{
    public Guid ServiceId { get; private set; }
    public Guid OrgId { get; private set; }
    public string ServiceCode { get; private set; } = default!;
    public string ServiceName { get; set; } = default!;
    public string? Description { get; set; }
    public Guid? CategoryId { get; set; }
    public string UnitOfMeasure { get; set; } = "Unit";
    public decimal StandardRate { get; set; }
    public Guid DefaultTaxCodeId { get; set; }
    public Guid RevenueAccountId { get; set; }
    public decimal DefaultDiscountPercent { get; set; }
    public RevenueRecognitionMethod RevenueRecognitionMethod { get; set; } = RevenueRecognitionMethod.Immediate;
    public string Status { get; private set; } = "ACTIVE";

    private ServiceCatalogueItem() { }

    public static ServiceCatalogueItem Create(Guid orgId, string serviceCode, string serviceName,
        decimal standardRate, Guid defaultTaxCodeId, Guid revenueAccountId)
    {
        if (standardRate < 0) throw new ArgumentOutOfRangeException(nameof(standardRate));

        return new ServiceCatalogueItem
        {
            ServiceId = Guid.NewGuid(),
            OrgId = orgId,
            ServiceCode = serviceCode,
            ServiceName = serviceName,
            StandardRate = standardRate,
            DefaultTaxCodeId = defaultTaxCodeId,
            RevenueAccountId = revenueAccountId
        };
    }

    public bool IsActive => Status == "ACTIVE";
}

public class TaxCode
{
    public Guid TaxCodeId { get; private set; }
    public Guid OrgId { get; private set; }
    public string Code { get; private set; } = default!;
    public TaxType TaxType { get; private set; }
    public decimal RatePercent { get; private set; }
    public Guid LiabilityAccountId { get; private set; }
    public DateOnly EffectiveFrom { get; private set; }
    public DateOnly? EffectiveTo { get; private set; }
    public bool IsActive { get; private set; } = true;

    private TaxCode() { }

    public bool IsValidOn(DateOnly date) =>
        IsActive && date >= EffectiveFrom && (EffectiveTo is null || date <= EffectiveTo);
}
