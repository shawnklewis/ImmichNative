namespace ImmichSupervisor;

public sealed class HealthCheckConfig
{
    /// <summary>"tcp" (port accepts connections) or "http" (GET returns 2xx).</summary>
    public string Type { get; init; } = "tcp";
    public string Host { get; init; } = "127.0.0.1";
    public int Port { get; init; }
    public string Path { get; init; } = "/";
    /// <summary>How long a freshly started process may take to become healthy.</summary>
    public int StartupTimeoutSeconds { get; init; } = 60;
}

public sealed class StopConfig
{
    /// <summary>"kill" ends the process tree; "command" runs Executable/Arguments for a graceful stop first.</summary>
    public string Mode { get; init; } = "kill";
    public string? Executable { get; init; }
    public string? Arguments { get; init; }
    /// <summary>After this long the process tree is killed regardless.</summary>
    public int TimeoutSeconds { get; init; } = 30;
}

public sealed class ComponentConfig
{
    public string Name { get; init; } = "";
    public string Executable { get; init; } = "";
    public string Arguments { get; init; } = "";
    public string? WorkingDirectory { get; init; }
    public Dictionary<string, string> Environment { get; init; } = new();
    public List<string> DependsOn { get; init; } = new();
    public bool AutoStart { get; init; } = true;
    public HealthCheckConfig? Health { get; init; }
    public StopConfig Stop { get; init; } = new();
}

public sealed class BackupConfig
{
    public bool Enabled { get; init; } = true;
    public string TimeOfDay { get; init; } = "03:00";
    public int Keep { get; init; } = 14;
    public string Directory { get; init; } = "";
    public string PgDump { get; init; } = "";
    public string PgRestore { get; init; } = "";
    public string Host { get; init; } = "127.0.0.1";
    public int Port { get; init; } = 5433;
    public string User { get; init; } = "postgres";
    public string Database { get; init; } = "immich";
    /// <summary>Secret key (from the secrets file) holding the database password.</summary>
    public string PasswordSecret { get; init; } = "PGPASSWORD";
}

public sealed class SupervisorOptions
{
    /// <summary>Repository root; substituted for ${root} in config strings.</summary>
    public string Root { get; init; } = "";
    public string SecretsFile { get; init; } = "";
    public string LogDirectory { get; init; } = "";
    public int RestartInitialDelaySeconds { get; init; } = 2;
    public int RestartMaxDelaySeconds { get; init; } = 120;
    public int RestartResetAfterSeconds { get; init; } = 120;
    public BackupConfig Backup { get; init; } = new();
    public List<ComponentConfig> Components { get; init; } = new();
}
