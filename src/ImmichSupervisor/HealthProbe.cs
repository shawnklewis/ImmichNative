using System.Net.Sockets;

namespace ImmichSupervisor;

public static class HealthProbe
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(3) };

    public static async Task<bool> IsHealthyAsync(HealthCheckConfig health, CancellationToken ct)
    {
        try
        {
            if (health.Type.Equals("http", StringComparison.OrdinalIgnoreCase))
            {
                using var response = await Http.GetAsync($"http://{health.Host}:{health.Port}{health.Path}", ct);
                return response.IsSuccessStatusCode;
            }

            using var client = new TcpClient();
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(2));
            await client.ConnectAsync(health.Host, health.Port, timeout.Token);
            return true;
        }
        catch (Exception) when (!ct.IsCancellationRequested)
        {
            return false;
        }
    }
}
