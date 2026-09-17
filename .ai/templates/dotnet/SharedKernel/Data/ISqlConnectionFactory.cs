using Microsoft.Data.SqlClient;

namespace __ROOT__.SharedKernel.Data;

public interface ISqlConnectionFactory
{
    ValueTask<SqlConnection> OpenAsync(CancellationToken ct);
}

public sealed class SqlConnectionFactory(string connectionString) : ISqlConnectionFactory
{
    public async ValueTask<SqlConnection> OpenAsync(CancellationToken ct)
    {
        var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}
