using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Identity.Web;
using McpServer.Services;
using McpServer.Tools;

var builder = WebApplication.CreateBuilder(args);

// Inbound auth: validate the user's Entra ID token (audience = MCP server app).
builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddMicrosoftIdentityWebApi(builder.Configuration.GetSection("AzureAd"))
    .EnableTokenAcquisitionToCallDownstreamApi()   // enables On-Behalf-Of
    .AddInMemoryTokenCaches();

builder.Services.AddAuthorizationBuilder()
    .AddPolicy("McpAccess", policy =>
        policy.RequireAuthenticatedUser()
              .RequireClaim("http://schemas.microsoft.com/identity/claims/scope", "mcp.access"));

// Downstream Tasks API client (uses OBO).
builder.Services.AddHttpClient<TasksApiClient>(client =>
{
    var baseUrl = builder.Configuration["DownstreamApi:BaseUrl"]
        ?? throw new InvalidOperationException("DownstreamApi:BaseUrl not configured");
    client.BaseAddress = new Uri(baseUrl);
});

// MCP server: Streamable HTTP transport + auto-discover [McpServerToolType] classes.
builder.Services
    .AddMcpServer()
    .WithHttpTransport()
    .WithTools<TaskTools>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

// Health endpoint (unauthenticated).
app.MapGet("/healthz", () => Results.Ok(new { status = "ok" }));

// OAuth 2.1 Protected Resource Metadata (MCP June 2025 auth spec).
// Copilot Studio reads this to discover the auth server.
app.MapGet("/.well-known/oauth-protected-resource", (IConfiguration cfg) =>
{
    var tenantId = cfg["AzureAd:TenantId"];
    var clientId = cfg["AzureAd:ClientId"];
    return Results.Json(new
    {
        resource = $"api://{clientId}",
        authorization_servers = new[] { $"https://login.microsoftonline.com/{tenantId}/v2.0" },
        scopes_supported = new[] { "mcp.access" },
        bearer_methods_supported = new[] { "header" }
    });
});

// MCP endpoint — Streamable HTTP at /mcp. This is what Copilot Studio calls.
app.MapMcp("/mcp").RequireAuthorization("McpAccess");

app.Run();
