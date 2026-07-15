using Npgsql;
using NEFMP.Ebilling.Domain.Enums;
using NEFMP.Ebilling.Domain.Entities;
using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// --------------------------------------------------------------------------
// Database configuration
// --------------------------------------------------------------------------
var connectionString = BuildConnectionString() ?? throw new InvalidOperationException("DATABASE_URL not configured");
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(connectionString));

var app = builder.Build();

// --------------------------------------------------------------------------
// Root endpoint — welcome message
// --------------------------------------------------------------------------
app.MapGet("/", () => "NEFMP eBilling API is running 🚀");

// --------------------------------------------------------------------------
// Basic liveness check — always returns 200 if the process is up.
// Use this as Railway's health-check path.
// --------------------------------------------------------------------------
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    service = "NEFMP e-Billing API",
    timestampUtc = DateTimeOffset.UtcNow
}));

// --------------------------------------------------------------------------
// Database connectivity check — confirms the Postgres connection string
// (Railway's DATABASE_URL, converted below) actually works. Returns 200 with
// db=connected, or 503 with the error, rather than throwing an unhandled 500.
// --------------------------------------------------------------------------
app.MapGet("/health/db", async () =>
{
    var connectionString = BuildConnectionString();
    if (connectionString is null)
        return Results.Ok(new { status = "no_database_configured" });

    try
    {
        await using var conn = new NpgsqlConnection(connectionString);
        await conn.OpenAsync();
        await using var cmd = new NpgsqlCommand("SELECT version();", conn);
        var version = (string?)await cmd.ExecuteScalarAsync();
        return Results.Ok(new { status = "connected", postgresVersion = version });
    }
    catch (Exception ex)
    {
        return Results.Json(new { status = "error", message = ex.Message }, statusCode: 503);
    }
});

// --------------------------------------------------------------------------
// Proof-of-life endpoint: confirms the Domain project reference actually
// compiles and links correctly by exposing a real enum from that layer.
// --------------------------------------------------------------------------
app.MapGet("/api/v1/meta/invoice-statuses", () =>
    Results.Ok(Enum.GetNames<InvoiceStatus>()));

// --------------------------------------------------------------------------
// POST /api/v1/customers — Create a new customer
// --------------------------------------------------------------------------
app.MapPost("/api/v1/customers", async (CreateCustomerRequest request, AppDbContext db) =>
{
    var orgId = Guid.NewGuid(); // TODO: Get from authenticated user context
    
    var customer = Customer.Create(
        orgId: orgId,
        customerCode: request.CustomerCode,
        customerName: request.CustomerName,
        customerType: request.CustomerType ?? "INDIVIDUAL"
    );

    // Set optional fields
    if (!string.IsNullOrWhiteSpace(request.Email))
        customer.Email = request.Email;
    if (!string.IsNullOrWhiteSpace(request.MobileNumber))
        customer.MobileNumber = request.MobileNumber;
    if (!string.IsNullOrWhiteSpace(request.PanNumber))
        customer.PanNumber = request.PanNumber;
    if (!string.IsNullOrWhiteSpace(request.VatNumber))
        customer.VatNumber = request.VatNumber;
    if (request.CreditLimit.HasValue)
        customer.CreditLimit = request.CreditLimit.Value;
    if (request.CreditDays.HasValue)
        customer.CreditDays = request.CreditDays.Value;

    db.Customers.Add(customer);
    await db.SaveChangesAsync();

    return Results.Created($"/api/v1/customers/{customer.CustomerId}", customer);
})
.WithName("CreateCustomer")
.WithOpenApi();

var port = Environment.GetEnvironmentVariable("PORT") ?? "5000";
app.Run($"http://0.0.0.0:{port}");

// Railway/most managed Postgres providers hand out a single DATABASE_URL in
// the form: postgres://user:password@host:port/dbname
// Npgsql needs the ADO.NET keyword format, so this converts one to the other.
static string? BuildConnectionString()
{
    var databaseUrl = Environment.GetEnvironmentVariable("DATABASE_URL");
    if (string.IsNullOrWhiteSpace(databaseUrl))
        return null;

    var uri = new Uri(databaseUrl);
    var userInfo = uri.UserInfo.Split(':', 2);

    var builder = new NpgsqlConnectionStringBuilder
    {
        Host = uri.Host,
        Port = uri.Port > 0 ? uri.Port : 5432,
        Username = userInfo[0],
        Password = userInfo.Length > 1 ? userInfo[1] : "",
        Database = uri.AbsolutePath.TrimStart('/'),
        SslMode = SslMode.Require,
        TrustServerCertificate = true
    };

    return builder.ConnectionString;
}

public class CreateCustomerRequest
{
    public string CustomerCode { get; set; } = default!;
    public string CustomerName { get; set; } = default!;
    public string? CustomerType { get; set; }
    public string? Email { get; set; }
    public string? MobileNumber { get; set; }
    public string? PanNumber { get; set; }
    public string? VatNumber { get; set; }
    public decimal? CreditLimit { get; set; }
    public int? CreditDays { get; set; }
}

public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<Customer> Customers => Set<Customer>();
    public DbSet<ServiceCatalogueItem> ServiceCatalogueItems => Set<ServiceCatalogueItem>();
    public DbSet<TaxCode> TaxCodes => Set<TaxCode>();
    public DbSet<Invoice> Invoices => Set<Invoice>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        // Configure Customer entity
        modelBuilder.Entity<Customer>()
            .HasKey(c => c.CustomerId);
        modelBuilder.Entity<Customer>()
            .Property(c => c.Email)
            .HasColumnType("citext");

        // Configure ServiceCatalogueItem entity
        modelBuilder.Entity<ServiceCatalogueItem>()
            .HasKey(s => s.ServiceId);

        // Configure TaxCode entity
        modelBuilder.Entity<TaxCode>()
            .HasKey(t => t.TaxCodeId);

        // Configure Invoice entity
        modelBuilder.Entity<Invoice>()
            .HasKey(i => i.InvoiceId);
    }
}

