namespace ImmichSupervisor;

public sealed class Worker : BackgroundService
{
    private readonly ResolvedConfig _config;
    private readonly ILogger<Worker> _log;
    private readonly ILoggerFactory _loggers;
    private List<ManagedComponent> _components = [];

    public Worker(ResolvedConfig config, ILogger<Worker> log, ILoggerFactory loggers)
    {
        _config = config;
        _log = log;
        _loggers = loggers;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var o = _config.Options;
        var policy = new RestartPolicy(
            TimeSpan.FromSeconds(o.RestartInitialDelaySeconds),
            TimeSpan.FromSeconds(o.RestartMaxDelaySeconds))
        { ResetAfter = TimeSpan.FromSeconds(o.RestartResetAfterSeconds) };

        var ordered = StartOrder.Resolve(_config.Components.Where(c => c.AutoStart)).ToList();
        var byName = new Dictionary<string, ManagedComponent>(StringComparer.OrdinalIgnoreCase);
        foreach (var cfg in ordered)
        {
            foreach (var dep in cfg.DependsOn.Where(d => !ordered.Any(c => c.Name.Equals(d, StringComparison.OrdinalIgnoreCase))))
                throw new InvalidOperationException($"'{cfg.Name}' depends on '{dep}', which is not set to AutoStart.");
            byName[cfg.Name] = new ManagedComponent(cfg, policy, _config.LogDirectory, _loggers.CreateLogger($"Component.{cfg.Name}"));
        }
        _components = ordered.Select(c => byName[c.Name]).ToList();

        _log.LogInformation("Starting {Count} components: {Names}", _components.Count, string.Join(", ", ordered.Select(c => c.Name)));

        var runners = ordered.Select(cfg => Task.Run(async () =>
        {
            try
            {
                await Task.WhenAll(cfg.DependsOn.Select(d => byName[d].WaitHealthyAsync(stoppingToken)));
                await byName[cfg.Name].RunAsync(stoppingToken);
            }
            catch (OperationCanceledException) { }
        }, CancellationToken.None)).ToList();

        await Task.WhenAll(runners);
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        await base.StopAsync(cancellationToken); // cancels the run loops and waits for them

        _log.LogInformation("Stopping components in reverse order");
        foreach (var component in _components.AsEnumerable().Reverse())
        {
            await component.StopAsync(cancellationToken);
            component.Dispose();
        }
        _log.LogInformation("All components stopped");
    }
}
