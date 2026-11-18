using Microsoft.Data.Sqlite;
using Park.Core.Configuration;

namespace Park.Library;

/// <summary>
/// SQLite WAL database 100% schema-aligned with Android lib/data/database.dart (v7),
/// lib/subscriptions/schema.dart, and lib/tavern/schema.dart.
/// </summary>
public sealed class ParkDatabase : IAsyncDisposable, IDisposable
{
    public const int CurrentSchemaVersion = 7;

    private readonly string _connectionString;
    private SqliteConnection? _connection;
    private readonly SemaphoreSlim _writeGate = new(1, 1);

    public ParkDatabase(string? dbFilePath = null)
    {
        var path = dbFilePath ?? AppPaths.DatabaseFile;
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        _connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = path,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Cache = SqliteCacheMode.Shared,
            Pooling = true,
        }.ToString();
    }

    public async Task InitializeAsync(CancellationToken ct = default)
    {
        _connection = new SqliteConnection(_connectionString);
        await _connection.OpenAsync(ct).ConfigureAwait(false);

        await ExecuteNonQueryAsync(_connection, "PRAGMA journal_mode = WAL;", ct).ConfigureAwait(false);
        await ExecuteNonQueryAsync(_connection, "PRAGMA synchronous = NORMAL;", ct).ConfigureAwait(false);
        await ExecuteNonQueryAsync(_connection, "PRAGMA foreign_keys = ON;", ct).ConfigureAwait(false);
        await ExecuteNonQueryAsync(_connection, "PRAGMA busy_timeout = 5000;", ct).ConfigureAwait(false);

        var version = Convert.ToInt32(await ExecuteScalarAsync(_connection, "PRAGMA user_version;", ct).ConfigureAwait(false) ?? 0);
        if (version > CurrentSchemaVersion)
        {
            await _connection.CloseAsync().ConfigureAwait(false);
            throw new InvalidOperationException($"Database schema v{version} is newer than supported v{CurrentSchemaVersion}.");
        }

        if (version < CurrentSchemaVersion)
        {
            await using var tx = (SqliteTransaction)await _connection.BeginTransactionAsync(ct).ConfigureAwait(false);
            await CreateOrMigrateTablesAsync(_connection, tx, ct).ConfigureAwait(false);
            await ExecuteNonQueryAsync(_connection, $"PRAGMA user_version = {CurrentSchemaVersion};", ct, tx).ConfigureAwait(false);
            await tx.CommitAsync(ct).ConfigureAwait(false);
        }
        else
        {
            // Ensure idempotent table presence even on existing v7 DBs created by Drift
            await using var tx = (SqliteTransaction)await _connection.BeginTransactionAsync(ct).ConfigureAwait(false);
            await CreateOrMigrateTablesAsync(_connection, tx, ct).ConfigureAwait(false);
            await tx.CommitAsync(ct).ConfigureAwait(false);
        }
    }

    public async Task<T> ReadAsync<T>(Func<SqliteConnection, Task<T>> reader, CancellationToken ct = default)
    {
        await using var conn = new SqliteConnection(_connectionString);
        await conn.OpenAsync(ct).ConfigureAwait(false);
        await ExecuteNonQueryAsync(conn, "PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;", ct).ConfigureAwait(false);
        return await reader(conn).ConfigureAwait(false);
    }

    public async Task<T> WriteTransactionAsync<T>(Func<SqliteConnection, SqliteTransaction, Task<T>> writer, CancellationToken ct = default)
    {
        await _writeGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            var conn = _connection ?? throw new ObjectDisposedException(nameof(ParkDatabase));
            await using var tx = (SqliteTransaction)await conn.BeginTransactionAsync(ct).ConfigureAwait(false);
            var result = await writer(conn, tx).ConfigureAwait(false);
            await tx.CommitAsync(ct).ConfigureAwait(false);
            return result;
        }
        finally
        {
            _writeGate.Release();
        }
    }

    public Task WriteTransactionAsync(Func<SqliteConnection, SqliteTransaction, Task> writer, CancellationToken ct = default) =>
        WriteTransactionAsync(async (conn, tx) =>
        {
            await writer(conn, tx).ConfigureAwait(false);
            return true;
        }, ct);

    private static async Task CreateOrMigrateTablesAsync(SqliteConnection conn, SqliteTransaction tx, CancellationToken ct)
    {
        string[] statements =
        [
            """
            CREATE TABLE IF NOT EXISTS works (
                source TEXT NOT NULL,
                id TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                cover TEXT NOT NULL DEFAULT '',
                json TEXT NOT NULL DEFAULT '{}',
                favorite INTEGER NOT NULL DEFAULT 0,
                favorited_at INTEGER NULL,
                last_update_check INTEGER NULL,
                reader_mode INTEGER NULL,
                one_shot INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (source, id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                sort INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS work_categories (
                source TEXT NOT NULL,
                work_id TEXT NOT NULL,
                category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
                PRIMARY KEY (source, work_id, category_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS chapters (
                source TEXT NOT NULL,
                work_id TEXT NOT NULL,
                chapter_id TEXT NOT NULL,
                title TEXT NOT NULL DEFAULT '',
                sort INTEGER NOT NULL DEFAULT 0,
                "read" INTEGER NOT NULL DEFAULT 0,
                last_page INTEGER NOT NULL DEFAULT 0,
                page_count INTEGER NOT NULL DEFAULT 0,
                date_fetch INTEGER NOT NULL DEFAULT 0,
                date_read INTEGER NULL,
                progress_updated_at INTEGER NULL,
                position INTEGER NOT NULL DEFAULT 0,
                duration INTEGER NOT NULL DEFAULT 0,
                position_updated_at INTEGER NULL,
                PRIMARY KEY (source, work_id, chapter_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS history (
                source TEXT NOT NULL,
                work_id TEXT NOT NULL,
                time INTEGER NOT NULL,
                chapter_id TEXT NULL,
                chapter_title TEXT NULL,
                page INTEGER NOT NULL DEFAULT 0,
                page_count INTEGER NOT NULL DEFAULT 0,
                position INTEGER NULL,
                PRIMARY KEY (source, work_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS download_tasks (
                uid TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                json TEXT NOT NULL,
                dir TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS restore_checkpoints (
                id INTEGER PRIMARY KEY,
                token TEXT NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS subscriptions (
                identity TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                dimension TEXT NOT NULL,
                target TEXT NOT NULL,
                label TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                notify INTEGER NOT NULL DEFAULT 1,
                created_at INTEGER NOT NULL,
                UNIQUE(source, dimension, target)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS subscription_checks (
                identity TEXT PRIMARY KEY REFERENCES subscriptions(identity) ON DELETE CASCADE,
                baseline INTEGER NOT NULL DEFAULT 0,
                last_success INTEGER NOT NULL DEFAULT 0,
                next_due INTEGER NOT NULL DEFAULT 0,
                failures INTEGER NOT NULL DEFAULT 0,
                error_code TEXT NOT NULL DEFAULT '',
                progress TEXT NOT NULL DEFAULT '{}',
                context_hash TEXT NOT NULL DEFAULT '',
                seen_count INTEGER NOT NULL DEFAULT 0,
                lease_owner TEXT NOT NULL DEFAULT '',
                lease_until INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS subscription_seen (
                identity TEXT NOT NULL REFERENCES subscriptions(identity) ON DELETE CASCADE,
                content_id TEXT NOT NULL,
                PRIMARY KEY(identity, content_id)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS subscription_events (
                event_key TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                content_id TEXT NOT NULL,
                identity TEXT NOT NULL,
                title TEXT NOT NULL,
                route TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                unread INTEGER NOT NULL DEFAULT 1,
                notify INTEGER NOT NULL DEFAULT 1,
                notification_id INTEGER NOT NULL,
                delivered INTEGER NOT NULL DEFAULT 0,
                attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt INTEGER NOT NULL DEFAULT 0
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_subscription_events_pending ON subscription_events(delivered, next_attempt);",
            """
            CREATE TABLE IF NOT EXISTS subscription_event_targets (
                event_key TEXT NOT NULL REFERENCES subscription_events(event_key) ON DELETE CASCADE,
                identity TEXT NOT NULL REFERENCES subscriptions(identity) ON DELETE CASCADE,
                PRIMARY KEY(event_key, identity)
            );
            """,
            "CREATE TABLE IF NOT EXISTS subscription_meta (name TEXT PRIMARY KEY, value TEXT NOT NULL);",
            """
            CREATE TABLE IF NOT EXISTS tavern_resources (
                uid TEXT PRIMARY KEY,
                item_json TEXT NOT NULL,
                kind TEXT NOT NULL,
                format TEXT NOT NULL,
                card_json TEXT NOT NULL,
                original BLOB NOT NULL,
                saved_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS tavern_sessions (
                id TEXT PRIMARY KEY,
                resource_uid TEXT NOT NULL REFERENCES tavern_resources(uid) ON DELETE RESTRICT,
                data_json TEXT NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_tavern_sessions_updated ON tavern_sessions(updated_at);",
            "CREATE INDEX IF NOT EXISTS idx_works_favorite ON works (favorite);",
            "CREATE INDEX IF NOT EXISTS idx_chapters_fetch ON chapters (date_fetch);",
        ];

        foreach (var sql in statements)
        {
            await ExecuteNonQueryAsync(conn, sql, ct, tx).ConfigureAwait(false);
        }
    }

    internal static async Task<int> ExecuteNonQueryAsync(SqliteConnection conn, string sql, CancellationToken ct, SqliteTransaction? tx = null)
    {
        await using var cmd = conn.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = sql;
        return await cmd.ExecuteNonQueryAsync(ct).ConfigureAwait(false);
    }

    internal static async Task<object?> ExecuteScalarAsync(SqliteConnection conn, string sql, CancellationToken ct, SqliteTransaction? tx = null)
    {
        await using var cmd = conn.CreateCommand();
        cmd.Transaction = tx;
        cmd.CommandText = sql;
        return await cmd.ExecuteScalarAsync(ct).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        await _writeGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (_connection is not null)
            {
                await _connection.CloseAsync().ConfigureAwait(false);
                await _connection.DisposeAsync().ConfigureAwait(false);
                _connection = null;
            }
            SqliteConnection.ClearAllPools();
        }
        finally
        {
            _writeGate.Release();
            _writeGate.Dispose();
        }
    }

    public void Dispose() => DisposeAsync().AsTask().GetAwaiter().GetResult();
}
