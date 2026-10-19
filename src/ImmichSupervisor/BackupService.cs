using System.Diagnostics;

namespace ImmichSupervisor;

/// <summary>Nightly verified pg_dump of the Immich database, with retention.</summary>
public sealed class BackupService : BackgroundService
{
    private readonly ResolvedConfig _config;
    private readonly ILogger<BackupService> _log;

    public BackupService(ResolvedConfig config, ILogger<BackupService> log)
    {
        _config = config;
        _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_config.Backup.Enabled)
        {
            _log.LogInformation("Backups disabled");
            return;
        }

        var timeOfDay = TimeOnly.Parse(_config.Backup.TimeOfDay);
        while (!stoppingToken.IsCancellationRequested)
        {
            var next = BackupPlan.NextRun(DateTime.Now, timeOfDay);
            _log.LogInformation("Next database backup at {When:g}", next);
            try
            {
                await Task.Delay(next - DateTime.Now, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            try
            {
                var file = await RunOnceAsync(_config, _log, stoppingToken);
                _log.LogInformation("Backup ok: {File}", file);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _log.LogError(ex, "Database backup failed");
            }
        }
    }

    /// <summary>Takes one backup, verifies it is readable, prunes old ones. Returns the new file's path.</summary>
    public static async Task<string> RunOnceAsync(ResolvedConfig config, ILogger log, CancellationToken ct)
    {
        var b = config.Backup;
        Directory.CreateDirectory(b.Directory);
        var file = Path.Combine(b.Directory, BackupPlan.FileName(DateTime.Now));

        var dump = await RunToolAsync(b.PgDump, config.BackupPassword,
            $"-h {b.Host} -p {b.Port} -U {b.User} -d {b.Database} -Fc -f \"{file}\"", ct);
        if (dump.ExitCode != 0)
        {
            TryDelete(file);
            throw new InvalidOperationException($"pg_dump failed ({dump.ExitCode}): {dump.Error.Trim()}");
        }

        var verify = await RunToolAsync(b.PgRestore, config.BackupPassword, $"--list \"{file}\"", ct);
        if (verify.ExitCode != 0)
        {
            TryDelete(file);
            throw new InvalidOperationException($"Backup verification failed ({verify.ExitCode}): {verify.Error.Trim()}");
        }

        var existing = new DirectoryInfo(b.Directory).GetFiles("immich-*.dump").Select(f => (f.FullName, f.LastWriteTime));
        foreach (var old in BackupPlan.FilesToDelete(existing, b.Keep))
        {
            log.LogInformation("Pruning old backup {File}", old);
            TryDelete(old);
        }
        return file;
    }

    private static async Task<(int ExitCode, string Error)> RunToolAsync(string exe, string password, string args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo(exe, args)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        psi.Environment["PGPASSWORD"] = password;
        using var process = Process.Start(psi) ?? throw new InvalidOperationException($"Could not start {exe}");
        var stdout = process.StandardOutput.ReadToEndAsync(ct); // drained so pg_restore --list can't block on a full pipe
        var stderr = process.StandardError.ReadToEndAsync(ct);
        await process.WaitForExitAsync(ct);
        await stdout;
        return (process.ExitCode, await stderr);
    }

    private static void TryDelete(string path)
    {
        try { File.Delete(path); } catch (IOException) { /* best effort */ }
    }
}
