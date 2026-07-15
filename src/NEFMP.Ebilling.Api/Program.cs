using Npgsql;
using NEFMP.Ebilling.Domain.Enums;

var builder = WebApplication.CreateBuilder(args);

// Railway injects the port to bind via the PORT env var — the app must listen on it.
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

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

app.Run();

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

