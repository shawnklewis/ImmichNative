using System.Text;

namespace ImmichSupervisor;

/// <summary>Minimal append-only file logger so the supervisor's own decisions are visible when it runs as a service.</summary>
public sealed class FileLoggerProvider : ILoggerProvider
{
    private const long RotateAtBytes = 10 * 1024 * 1024;
    private readonly StreamWriter _writer;
    private readonly object _lock = new();

    public FileLoggerProvider(string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var info = new FileInfo(path);
        if (info.Exists && info.Length > RotateAtBytes) File.Move(path, path + ".1", overwrite: true);
        _writer = new StreamWriter(new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite)) { AutoFlush = true };
    }

    public ILogger CreateLogger(string categoryName) => new FileLogger(categoryName, this);

    public void Dispose()
    {
        lock (_lock) _writer.Dispose();
    }

    private void Write(string line)
    {
        lock (_lock) _writer.WriteLine(line);
    }

    private sealed class FileLogger(string category, FileLoggerProvider owner) : ILogger
    {
        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Information;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;
            var sb = new StringBuilder()
                .Append(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff")).Append(' ')
                .Append(logLevel.ToString().PadRight(12)).Append(category).Append(": ")
                .Append(formatter(state, exception));
            if (exception is not null) sb.AppendLine().Append(exception);
            owner.Write(sb.ToString());
        }
    }
}

