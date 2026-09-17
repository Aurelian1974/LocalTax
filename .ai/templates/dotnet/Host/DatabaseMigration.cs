using DbUp;

namespace __ROOT__.Host;

/// <summary>Applies DbUp scripts from db/migrations at startup, only when Database:MigrateOnStartup is true
/// (set it in appsettings.Development.json yourself). Never creates the database.</summary>
internal static class DatabaseMigration
{
    public static void MigrateDatabaseIfEnabled(this WebApplication app)
    {
        if (!app.Configuration.GetValue<bool>("Database:MigrateOnStartup"))
        {
            return;
        }

        var connectionString = app.Configuration.GetConnectionString("Default")
            ?? throw new InvalidOperationException("ConnectionStrings:Default is missing.");
        var scripts = Path.Combine(AppContext.BaseDirectory, "db", "migrations");

        var result = DeployChanges.To
            .SqlDatabase(connectionString)
            .WithScriptsFromFileSystem(scripts)
            .WithTransactionPerScript()
            .LogToConsole()
            .Build()
            .PerformUpgrade();

        if (!result.Successful)
        {
            throw new InvalidOperationException("Database migration failed.", result.Error);
        }
    }
}
