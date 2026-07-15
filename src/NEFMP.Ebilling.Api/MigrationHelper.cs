using Npgsql;

namespace NEFMP.Ebilling.Api;

/// <summary>
/// Runs SQL migrations from the Migrations folder on startup.
/// </summary>
public static class MigrationHelper
{
    public static async Task RunMigrationsAsync(string connectionString)
    {
        var migrationsPath = Path.Combine(AppContext.BaseDirectory, "Migrations");
        
        if (!Directory.Exists(migrationsPath))
        {
            Console.WriteLine("No Migrations folder found.");
            return;
        }

        var migrationFiles = Directory.GetFiles(migrationsPath, "*.sql")
            .OrderBy(f => f)
            .ToList();

        if (migrationFiles.Count == 0)
        {
            Console.WriteLine("No migration files found.");
            return;
        }

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync();

        foreach (var file in migrationFiles)
        {
            var fileName = Path.GetFileName(file);
            Console.WriteLine($"Running migration: {fileName}");

            var sql = await File.ReadAllTextAsync(file);
            await using var cmd = new NpgsqlCommand(sql, connection);
            await cmd.ExecuteNonQueryAsync();

            Console.WriteLine($"✓ Completed: {fileName}");
        }

        await connection.CloseAsync();
        Console.WriteLine("All migrations completed successfully.");
    }
}

