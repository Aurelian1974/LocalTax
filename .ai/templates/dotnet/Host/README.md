# Host wiring for Dapper + DbUp

Program.cs:
```csharp
var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("ConnectionStrings:Default is missing.");
builder.Services.AddSingleton<ISqlConnectionFactory>(new SqlConnectionFactory(connectionString));
builder.Services.AddScoped<IDbSession, DbSession>();
// ...
var app = builder.Build();
app.MigrateDatabaseIfEnabled();
```

Host csproj (packages: `dbup-sqlserver`; SharedKernel: `Microsoft.Data.SqlClient`, `Dapper` in modules):
```xml
<ItemGroup>
  <None Include="..\..\db\migrations\*.sql" LinkBase="db\migrations" CopyToOutputDirectory="PreserveNewest" />
</ItemGroup>
```

appsettings.Development.json (you decide; agents never enable it):
```json
{ "Database": { "MigrateOnStartup": true } }
```
Other environments: run the same scripts through CI/CD or apply them manually; do not enable startup migration in production.
