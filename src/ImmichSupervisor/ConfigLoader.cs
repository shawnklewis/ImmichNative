namespace ImmichSupervisor;

/// <summary>Options with every ${root} / ${secret:X} token expanded. Built once at startup.</summary>
public sealed class ResolvedConfig
{
    public required SupervisorOptions Options { get; init; }
    public required IReadOnlyList<ComponentConfig> Components { get; init; }
    public required BackupConfig Backup { get; init; }
    public required string BackupPassword { get; init; }
    public required string LogDirectory { get; init; }
}

public static class ConfigLoader
{
    public static ResolvedConfig Resolve(SupervisorOptions options, IReadOnlyDictionary<string, string>? secretsOverride = null)
    {
        var rootOnly = new SecretExpander(new Dictionary<string, string>(), options.Root);
        var secrets = secretsOverride ?? LoadSecrets(rootOnly.Expand(options.SecretsFile));
        var x = new SecretExpander(secrets, options.Root);

        var components = options.Components.Select(c => new ComponentConfig
        {
            Name = c.Name,
            Executable = x.Expand(c.Executable),
            Arguments = x.Expand(c.Arguments),
            WorkingDirectory = c.WorkingDirectory is null ? null : x.Expand(c.WorkingDirectory),
            Environment = c.Environment.ToDictionary(kv => kv.Key, kv => x.Expand(kv.Value)),
            DependsOn = c.DependsOn.ToList(),
            AutoStart = c.AutoStart,
            Health = c.Health,
            Stop = new StopConfig
            {
                Mode = c.Stop.Mode,
                Executable = c.Stop.Executable is null ? null : x.Expand(c.Stop.Executable),
                Arguments = c.Stop.Arguments is null ? null : x.Expand(c.Stop.Arguments),
                TimeoutSeconds = c.Stop.TimeoutSeconds,
            },
        }).ToList();

        // Validate ordering/dependencies up front so a bad config fails at startup, not at 3am.
        StartOrder.Resolve(components);

        var b = options.Backup;
        var backup = new BackupConfig
        {
            Enabled = b.Enabled, TimeOfDay = b.TimeOfDay, Keep = b.Keep,
            Directory = x.Expand(b.Directory), PgDump = x.Expand(b.PgDump), PgRestore = x.Expand(b.PgRestore),
            Host = b.Host, Port = b.Port, User = b.User, Database = b.Database, PasswordSecret = b.PasswordSecret,
        };
        secrets.TryGetValue(b.PasswordSecret, out var pw);

        return new ResolvedConfig
        {
            Options = options,
            Components = components,
            Backup = backup,
            BackupPassword = pw ?? "",
            LogDirectory = x.Expand(options.LogDirectory),
        };
    }

    private static Dictionary<string, string> LoadSecrets(string path) =>
        File.Exists(path)
            ? SecretExpander.ParseEnvFile(File.ReadAllLines(path))
            : throw new FileNotFoundException($"Secrets file not found: {path}");
}
