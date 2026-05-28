using System.Net.Http.Headers;
using System.Net.Http.Json;
using Microsoft.Identity.Web;
using McpServer.Models;

namespace McpServer.Services;

/// <summary>
/// Calls the downstream Tasks API using the On-Behalf-Of flow.
/// The inbound user token (audience = MCP server) is exchanged for a token
/// whose audience is the Tasks API.
/// </summary>
public class TasksApiClient(
    HttpClient http,
    ITokenAcquisition tokenAcquisition,
    IConfiguration config)
{
    private readonly string _scope = config["DownstreamApi:Scopes"]
        ?? throw new InvalidOperationException("DownstreamApi:Scopes not configured");

    private async Task SetAuthHeaderAsync()
    {
        var token = await tokenAcquisition.GetAccessTokenForUserAsync(new[] { _scope });
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
    }

    public async Task<List<TodoTask>> ListAsync(CancellationToken ct)
    {
        await SetAuthHeaderAsync();
        return await http.GetFromJsonAsync<List<TodoTask>>("/tasks", ct) ?? new();
    }

    public async Task<TodoTask?> GetAsync(int id, CancellationToken ct)
    {
        await SetAuthHeaderAsync();
        var resp = await http.GetAsync($"/tasks/{id}", ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadFromJsonAsync<TodoTask>(cancellationToken: ct);
    }

    public async Task<TodoTask> CreateAsync(CreateTaskRequest req, CancellationToken ct)
    {
        await SetAuthHeaderAsync();
        var resp = await http.PostAsJsonAsync("/tasks", req, ct);
        resp.EnsureSuccessStatusCode();
        return (await resp.Content.ReadFromJsonAsync<TodoTask>(cancellationToken: ct))!;
    }

    public async Task<TodoTask?> UpdateAsync(int id, UpdateTaskRequest req, CancellationToken ct)
    {
        await SetAuthHeaderAsync();
        var resp = await http.PutAsJsonAsync($"/tasks/{id}", req, ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return null;
        resp.EnsureSuccessStatusCode();
        return await resp.Content.ReadFromJsonAsync<TodoTask>(cancellationToken: ct);
    }

    public async Task<bool> DeleteAsync(int id, CancellationToken ct)
    {
        await SetAuthHeaderAsync();
        var resp = await http.DeleteAsync($"/tasks/{id}", ct);
        if (resp.StatusCode == System.Net.HttpStatusCode.NotFound) return false;
        resp.EnsureSuccessStatusCode();
        return true;
    }
}
