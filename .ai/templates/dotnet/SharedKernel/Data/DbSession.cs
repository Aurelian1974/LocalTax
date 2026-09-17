using Microsoft.Data.SqlClient;

namespace __ROOT__.SharedKernel.Data;

/// <summary>One connection and at most one transaction per use case. Register as scoped.
/// Uncommitted work is rolled back on dispose, so an early return or exception never persists partial changes.</summary>
public interface IDbSession : IAsyncDisposable
{
    SqlConnection Connection { get; }
    SqlTransaction? Transaction { get; }
    Task OpenAsync(CancellationToken ct);
    Task BeginAsync(CancellationToken ct);
    Task CommitAsync(CancellationToken ct);
}

public sealed class DbSession(ISqlConnectionFactory factory) : IDbSession
{
    private SqlConnection? _connection;

    public SqlConnection Connection => _connection ?? throw new InvalidOperationException("Call OpenAsync or BeginAsync first.");

    public SqlTransaction? Transaction { get; private set; }

    public async Task OpenAsync(CancellationToken ct) => _connection ??= await factory.OpenAsync(ct);

    public async Task BeginAsync(CancellationToken ct)
    {
        if (Transaction is not null)
        {
            throw new InvalidOperationException("A transaction is already active for this use case.");
        }

        await OpenAsync(ct);
        Transaction = (SqlTransaction)await Connection.BeginTransactionAsync(ct);
    }

    public async Task CommitAsync(CancellationToken ct)
    {
        var transaction = Transaction ?? throw new InvalidOperationException("No active transaction.");
        await transaction.CommitAsync(ct);
        await transaction.DisposeAsync();
        Transaction = null;
    }

    public async ValueTask DisposeAsync()
    {
        if (Transaction is not null)
        {
            await Transaction.RollbackAsync();
            await Transaction.DisposeAsync();
            Transaction = null;
        }

        if (_connection is not null)
        {
            await _connection.DisposeAsync();
        }
    }
}
