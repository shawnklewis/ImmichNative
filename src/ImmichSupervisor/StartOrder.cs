namespace ImmichSupervisor;

public static class StartOrder
{
    /// <summary>
    /// Dependencies-first ordering that keeps the configured order for independent components.
    /// With <paramref name="reverse"/> the result is the shutdown order.
    /// </summary>
    public static IReadOnlyList<ComponentConfig> Resolve(IEnumerable<ComponentConfig> components, bool reverse = false)
    {
        var list = components.ToList();
        var byName = new Dictionary<string, ComponentConfig>(StringComparer.OrdinalIgnoreCase);
        foreach (var c in list)
        {
            if (!byName.TryAdd(c.Name, c))
                throw new InvalidOperationException($"Duplicate component name '{c.Name}'.");
        }

        var ordered = new List<ComponentConfig>();
        var state = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase); // 1 = visiting, 2 = done

        void Visit(ComponentConfig c, Stack<string> path)
        {
            if (state.TryGetValue(c.Name, out var s))
            {
                if (s == 1)
                    throw new InvalidOperationException(
                        $"Dependency cycle: {string.Join(" -> ", path.Reverse().Append(c.Name))}.");
                return;
            }

            state[c.Name] = 1;
            path.Push(c.Name);
            foreach (var dep in c.DependsOn)
            {
                if (!byName.TryGetValue(dep, out var d))
                    throw new InvalidOperationException($"Component '{c.Name}' depends on unknown component '{dep}'.");
                Visit(d, path);
            }
            path.Pop();
            state[c.Name] = 2;
            ordered.Add(c);
        }

        foreach (var c in list) Visit(c, new Stack<string>());

        if (reverse) ordered.Reverse();
        return ordered;
    }
}
