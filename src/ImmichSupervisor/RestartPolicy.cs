namespace ImmichSupervisor;

/// <summary>Exponential backoff between restarts of a crashed component.</summary>
public sealed record RestartPolicy(TimeSpan InitialDelay, TimeSpan MaxDelay)
{
    /// <summary>A run at least this long counts as healthy and clears the failure streak.</summary>
    public TimeSpan ResetAfter { get; init; } = TimeSpan.FromMinutes(2);

    public TimeSpan DelayAfter(int consecutiveFailures)
    {
        var n = Math.Clamp(consecutiveFailures, 0, 30);
        var seconds = Math.Min(MaxDelay.TotalSeconds, InitialDelay.TotalSeconds * Math.Pow(2, n));
        return TimeSpan.FromSeconds(seconds);
    }

    public bool ShouldResetStreak(TimeSpan uptime) => uptime >= ResetAfter;
}
