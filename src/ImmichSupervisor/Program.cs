using ImmichSupervisor;

// Usage:
//   ImmichSupervisor.exe                run (console, or as the "ImmichNative" Windows service)
//   ImmichSupervisor.exe --check-config validate config and print the start order
//   ImmichSupervisor.exe --backup-now   take one verified database backup and exit
// Content root is the exe folder, not the working directory: a Windows service starts in System32.
var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
{
    Args = args,
    ContentRootPath = AppContext.BaseDirectory,
});
builder.Services.AddWindowsService(o => o.ServiceName = "ImmichNative");
builder.Services.Configure<HostOptions>(o => o.ShutdownTimeout = TimeSpan.FromMinutes(3));

var options = builder.Configuration.GetSection("Supervisor").Get<SupervisorOptions>()
    ?? throw new InvalidOperationException("Missing 'Supervisor' section in appsettings.json");
var resolved = ConfigLoader.Resolve(options);
builder.Services.AddSingleton(resolved);
try
{
    builder.Logging.AddProvider(new FileLoggerProvider(Path.Combine(resolved.LogDirectory, "supervisor.log")));
}
catch (IOException) { /* log folder unavailable; console/event log still work */ }
catch (UnauthorizedAccessException) { }

if (args.Contains("--check-config"))
{
    Console.WriteLine("Config OK. Start order:");
    foreach (var c in StartOrder.Resolve(resolved.Components.Where(c => c.AutoStart)))
        Console.WriteLine($"  {c.Name} -> {c.Executable}"); // arguments/env omitted: they may contain secrets
    return;
}

if (args.Contains("--backup-now"))
{
    using var loggerFactory = LoggerFactory.Create(l => l.AddSimpleConsole());
    var file = await BackupService.RunOnceAsync(resolved, loggerFactory.CreateLogger("backup"), CancellationToken.None);
    Console.WriteLine($"backup ok: {file}");
    return;
}

builder.Services.AddHostedService<Worker>();
builder.Services.AddHostedService<BackupService>();
var app = builder.Build();

// --run-for <seconds>: stop through the normal graceful-shutdown path after a delay (used for testing).
var runForIndex = Array.IndexOf(args, "--run-for");
if (runForIndex >= 0 && runForIndex + 1 < args.Length && int.TryParse(args[runForIndex + 1], out var runFor))
{
    var lifetime = app.Services.GetRequiredService<IHostApplicationLifetime>();
    _ = Task.Delay(TimeSpan.FromSeconds(runFor)).ContinueWith(_ => lifetime.StopApplication());
}

await app.RunAsync();
