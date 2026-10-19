using ImmichSupervisor;

namespace ImmichSupervisor.Tests;

public class RestartPolicyTests
{
    private static readonly RestartPolicy Policy =
        new(InitialDelay: TimeSpan.FromSeconds(2), MaxDelay: TimeSpan.FromSeconds(60));

    [Theory]
    [InlineData(0, 2)]
    [InlineData(1, 4)]
    [InlineData(2, 8)]
    [InlineData(4, 32)]
    [InlineData(5, 60)]
    [InlineData(40, 60)]
    public void Delay_doubles_per_failure_and_is_capped(int failures, int expectedSeconds) =>
        Assert.Equal(TimeSpan.FromSeconds(expectedSeconds), Policy.DelayAfter(failures));

    [Fact]
    public void Negative_failures_are_treated_as_zero() =>
        Assert.Equal(TimeSpan.FromSeconds(2), Policy.DelayAfter(-3));

    [Fact]
    public void Failure_streak_resets_only_after_a_healthy_run()
    {
        var policy = Policy with { ResetAfter = TimeSpan.FromMinutes(2) };
        Assert.True(policy.ShouldResetStreak(TimeSpan.FromMinutes(3)));
        Assert.False(policy.ShouldResetStreak(TimeSpan.FromSeconds(30)));
    }
}

public class StartOrderTests
{
    private static ComponentConfig C(string name, params string[] dependsOn) =>
        new() { Name = name, Executable = "x", DependsOn = dependsOn.ToList() };

    [Fact]
    public void Dependencies_start_before_dependents()
    {
        var order = StartOrder.Resolve([C("server", "postgres", "redis"), C("postgres"), C("redis")])
            .Select(c => c.Name).ToList();

        Assert.True(order.IndexOf("postgres") < order.IndexOf("server"));
        Assert.True(order.IndexOf("redis") < order.IndexOf("server"));
    }

    [Fact]
    public void Order_is_stable_for_independent_components()
    {
        var order = StartOrder.Resolve([C("b"), C("a"), C("c")]).Select(c => c.Name);
        Assert.Equal(["b", "a", "c"], order);
    }

    [Fact]
    public void Unknown_dependency_is_rejected()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => StartOrder.Resolve([C("server", "ghost")]));
        Assert.Contains("ghost", ex.Message);
    }

    [Fact]
    public void Cycles_are_rejected()
    {
        var ex = Assert.Throws<InvalidOperationException>(() => StartOrder.Resolve([C("a", "b"), C("b", "a")]));
        Assert.Contains("cycle", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Duplicate_names_are_rejected() =>
        Assert.Throws<InvalidOperationException>(() => StartOrder.Resolve([C("a"), C("a")]));

    [Fact]
    public void Shutdown_order_is_the_reverse_of_start_order()
    {
        var start = StartOrder.Resolve([C("server", "postgres"), C("postgres")]).Select(c => c.Name).ToList();
        var stop = StartOrder.Resolve([C("server", "postgres"), C("postgres")], reverse: true).Select(c => c.Name).ToList();
        Assert.Equal(start.AsEnumerable().Reverse(), stop);
    }
}

public class SecretExpanderTests
{
    private static readonly Dictionary<string, string> Secrets = new() { ["PGPASSWORD"] = "s3cret" };

    [Fact]
    public void Expands_secret_and_root_tokens()
    {
        var expander = new SecretExpander(Secrets, root: @"C:\repo");
        Assert.Equal(@"C:\repo\tools\x --pw=s3cret", expander.Expand(@"${root}\tools\x --pw=${secret:PGPASSWORD}"));
    }

    [Fact]
    public void Text_without_tokens_is_unchanged() =>
        Assert.Equal("plain", new SecretExpander(Secrets, "r").Expand("plain"));

    [Fact]
    public void Missing_secret_fails_loudly_without_echoing_other_secrets()
    {
        var ex = Assert.Throws<InvalidOperationException>(() =>
            new SecretExpander(Secrets, "r").Expand("${secret:NOPE}"));
        Assert.Contains("NOPE", ex.Message);
        Assert.DoesNotContain("s3cret", ex.Message);
    }

    [Fact]
    public void Parses_env_file_lines_ignoring_blanks_and_comments()
    {
        var parsed = SecretExpander.ParseEnvFile(["# comment", "", "A=1", "B=two=2", "  C = 3 "]);
        Assert.Equal("1", parsed["A"]);
        Assert.Equal("two=2", parsed["B"]);
        Assert.Equal("3", parsed["C"]);
    }
}

public class BackupPlanTests
{
    [Fact]
    public void Keeps_newest_n_and_returns_the_rest_for_deletion()
    {
        var t = new DateTime(2026, 10, 1);
        var files = Enumerable.Range(0, 5).Select(i => ($"f{i}.dump", t.AddDays(i))).ToList();
        var toDelete = BackupPlan.FilesToDelete(files, keep: 2);
        Assert.Equal(["f0.dump", "f1.dump", "f2.dump"], toDelete.OrderBy(x => x));
    }

    [Fact]
    public void Nothing_is_deleted_when_within_the_limit() =>
        Assert.Empty(BackupPlan.FilesToDelete([("a.dump", DateTime.Now)], keep: 14));

    [Fact]
    public void Next_run_is_today_if_the_time_has_not_passed() =>
        Assert.Equal(new DateTime(2026, 10, 19, 3, 0, 0),
            BackupPlan.NextRun(new DateTime(2026, 10, 19, 1, 0, 0), new TimeOnly(3, 0)));

    [Fact]
    public void Next_run_is_tomorrow_if_the_time_has_passed() =>
        Assert.Equal(new DateTime(2026, 10, 20, 3, 0, 0),
            BackupPlan.NextRun(new DateTime(2026, 10, 19, 4, 0, 0), new TimeOnly(3, 0)));

    [Fact]
    public void File_name_is_sortable_and_timestamped() =>
        Assert.Equal("immich-20261019-030000.dump", BackupPlan.FileName(new DateTime(2026, 10, 19, 3, 0, 0)));
}
