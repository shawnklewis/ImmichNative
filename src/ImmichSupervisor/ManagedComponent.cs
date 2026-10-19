using System.Diagnostics;

namespace ImmichSupervisor;

/// <summary>
/// Runs one component: adopt it if it is already healthy, otherwise start it, wait for health,
/// and restart it with backoff when it dies. Stopping is explicit (<see cref="StopAsync"/>).
/// </summary>
public sealed class ManagedComponent : IDisposable
{
    private static readonly TimeSpan AdoptedPollInterval = TimeSpan.FromSeconds(10);

    private readonly ComponentConfig _config;
    private readonly RestartPolicy _policy;
    private readonly ILogger _log;
    private readonly string _logFile;
    private readonly TaskCompletionSource _healthy = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly object _logLock = new();
    private StreamWriter? _writer;
    private Process? _process;
    private volatile bool _adopted;

    public ManagedComponent(ComponentConfig config, RestartPolicy policy, string logDirectory, ILogger log)
    {
        _config = config;
        _policy = policy;
        _log = log;
        Directory.CreateDirectory(logDirectory);
        _logFile = Path.Combine(logDirectory, $"{config.Name}.log");
    }

    public string Name => _config.Name;
    public string State { get; private set; } = "pending";
    public Task WaitHealthyAsync(CancellationToken ct) => _healthy.Task.WaitAsync(ct);

    public async Task RunAsync(CancellationToken ct)
    {
        var failures = 0;
        try
        {
            while (!ct.IsCancellationRequested)
            {
                if (_config.Health is not null && await HealthProbe.IsHealthyAsync(_config.Health, ct))
                {
                    await WatchAdoptedAsync(ct);
                    continue;
                }

                var startedAt = DateTime.UtcNow;
                Process process;
                try
                {
                    process = Spawn();
                }
                catch (Exception ex)
                {
                    _log.LogError(ex, "{Component}: failed to start", Name);
                    failures++;
                    await DelayAsync(failures, ct);
                    continue;
                }

                State = "starting";
                var exited = process.WaitForExitAsync(CancellationToken.None);
                if (await WaitForHealthyAsync(exited, ct))
                {
                    State = "running";
                    _healthy.TrySetResult();
                    _log.LogInformation("{Component}: healthy (pid {Pid})", Name, process.Id);
                }

                await exited.WaitAsync(ct);

                var uptime = DateTime.UtcNow - startedAt;
                failures = _policy.ShouldResetStreak(uptime) ? 1 : failures + 1;
                State = "crashed";
                _log.LogWarning("{Component}: exited with code {Code} after {Uptime:N0}s", Name, process.ExitCode, uptime.TotalSeconds);
                await DelayAsync(failures, ct);
            }
        }
        catch (OperationCanceledException)
        {
            // shutting down; StopAsync handles the process
        }
    }

    public async Task StopAsync(CancellationToken ct)
    {
        if (_adopted)
        {
            _log.LogInformation("{Component}: was already running before the supervisor; leaving it running", Name);
            return;
        }

        var process = _process;
        if (process is null || process.HasExited) return;

        State = "stopping";
        var timeout = TimeSpan.FromSeconds(_config.Stop.TimeoutSeconds);

        if (_config.Stop.Mode.Equals("command", StringComparison.OrdinalIgnoreCase) && _config.Stop.Executable is not null)
        {
            try
            {
                using var stopper = Process.Start(new ProcessStartInfo(_config.Stop.Executable, _config.Stop.Arguments ?? "")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                });
                if (stopper is not null)
                {
                    using var stopCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                    stopCts.CancelAfter(timeout);
                    await stopper.WaitForExitAsync(stopCts.Token);
                }
            }
            catch (Exception ex)
            {
                _log.LogWarning(ex, "{Component}: graceful stop command failed", Name);
            }
        }

        if (_config.Stop.Mode.Equals("kill", StringComparison.OrdinalIgnoreCase))
        {
            // No graceful signal exists for console apps on Windows; end the tree now instead of waiting out the timeout.
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { /* already gone */ }
        }

        try
        {
            using var waitCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            waitCts.CancelAfter(timeout);
            await process.WaitForExitAsync(waitCts.Token);
        }
        catch (OperationCanceledException)
        {
            _log.LogWarning("{Component}: did not exit within {Seconds}s, killing process tree", Name, timeout.TotalSeconds);
            try { process.Kill(entireProcessTree: true); } catch (InvalidOperationException) { /* already gone */ }
        }

        State = "stopped";
        _log.LogInformation("{Component}: stopped", Name);
    }

    private async Task WatchAdoptedAsync(CancellationToken ct)
    {
        _adopted = true;
        State = "adopted";
        _healthy.TrySetResult();
        _log.LogInformation("{Component}: already running and healthy; adopting instead of starting a second copy", Name);

        var misses = 0;
        while (!ct.IsCancellationRequested && misses < 3)
        {
            await Task.Delay(AdoptedPollInterval, ct);
            misses = await HealthProbe.IsHealthyAsync(_config.Health!, ct) ? 0 : misses + 1;
        }

        _adopted = false;
        if (!ct.IsCancellationRequested)
            _log.LogWarning("{Component}: adopted instance stopped answering; taking over", Name);
    }

    private async Task<bool> WaitForHealthyAsync(Task exited, CancellationToken ct)
    {
        if (_config.Health is null)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), ct);
            return !exited.IsCompleted;
        }

        var deadline = DateTime.UtcNow.AddSeconds(_config.Health.StartupTimeoutSeconds);
        while (DateTime.UtcNow < deadline && !exited.IsCompleted)
        {
            if (await HealthProbe.IsHealthyAsync(_config.Health, ct)) return true;
            await Task.Delay(TimeSpan.FromSeconds(1), ct);
        }

        if (!exited.IsCompleted)
            _log.LogError("{Component}: not healthy after {Seconds}s", Name, _config.Health.StartupTimeoutSeconds);
        return false;
    }

    private Process Spawn()
    {
        var psi = new ProcessStartInfo(_config.Executable, _config.Arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = _config.WorkingDirectory ?? Path.GetDirectoryName(_config.Executable) ?? "",
        };
        foreach (var (key, value) in _config.Environment) psi.Environment[key] = value;

        OpenLog();
        var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) => WriteLog(e.Data);
        process.ErrorDataReceived += (_, e) => WriteLog(e.Data);
        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        _process = process;
        _log.LogInformation("{Component}: started (pid {Pid})", Name, process.Id);
        return process;
    }

    private void OpenLog()
    {
        lock (_logLock)
        {
            _writer?.Dispose();
            var info = new FileInfo(_logFile);
            if (info.Exists && info.Length > 20 * 1024 * 1024)
                File.Move(_logFile, _logFile + ".1", overwrite: true);
            _writer = new StreamWriter(new FileStream(_logFile, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) { AutoFlush = true };
        }
    }

    private void WriteLog(string? line)
    {
        if (line is null) return;
        lock (_logLock) _writer?.WriteLine(line);
    }

    private Task DelayAsync(int failures, CancellationToken ct)
    {
        var delay = _policy.DelayAfter(failures - 1);
        _log.LogInformation("{Component}: restarting in {Seconds:N0}s", Name, delay.TotalSeconds);
        return Task.Delay(delay, ct);
    }

    public void Dispose()
    {
        lock (_logLock) _writer?.Dispose();
        _process?.Dispose();
    }
}
