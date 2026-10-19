using System.Text.RegularExpressions;

namespace ImmichSupervisor;

/// <summary>Expands ${root} and ${secret:NAME} in config strings. Never logs secret values.</summary>
public sealed partial class SecretExpander
{
    private readonly IReadOnlyDictionary<string, string> _secrets;
    private readonly string _root;

    public SecretExpander(IReadOnlyDictionary<string, string> secrets, string root)
    {
        _secrets = secrets;
        _root = root;
    }

    public string Expand(string text) => TokenPattern().Replace(text, m =>
    {
        if (m.Groups["root"].Success) return _root;
        var name = m.Groups["name"].Value;
        return _secrets.TryGetValue(name, out var value)
            ? value
            : throw new InvalidOperationException($"Secret '{name}' is not defined in the secrets file.");
    });

    public static Dictionary<string, string> ParseEnvFile(IEnumerable<string> lines)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var eq = line.IndexOf('=');
            if (eq <= 0) continue;
            result[line[..eq].Trim()] = line[(eq + 1)..].Trim();
        }
        return result;
    }

    [GeneratedRegex(@"\$\{(?:(?<root>root)|secret:(?<name>[A-Za-z0-9_]+))\}")]
    private static partial Regex TokenPattern();
}
