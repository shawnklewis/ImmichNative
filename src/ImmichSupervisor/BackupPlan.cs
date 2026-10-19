namespace ImmichSupervisor;

public static class BackupPlan
{
    public static string FileName(DateTime when) => $"immich-{when:yyyyMMdd-HHmmss}.dump";

    /// <summary>Names of the oldest dumps to delete so that only the newest <paramref name="keep"/> remain.</summary>
    public static IReadOnlyList<string> FilesToDelete(IEnumerable<(string Name, DateTime Modified)> files, int keep) =>
        files.OrderByDescending(f => f.Modified).Skip(Math.Max(keep, 0)).Select(f => f.Name).ToList();

    public static DateTime NextRun(DateTime now, TimeOnly timeOfDay)
    {
        var today = now.Date + timeOfDay.ToTimeSpan();
        return now < today ? today : today.AddDays(1);
    }
}
