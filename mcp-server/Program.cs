using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Identity.Web;
using McpServer.Services;
using McpServer.Tools;
using System.Text.Json;

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

// ---------------------------------------------------------------------------
// OAuth / MCP auth discovery endpoints (unauthenticated)
// ---------------------------------------------------------------------------

// Protected Resource Metadata (RFC 9728).
// Points authorization_servers to this server so clients discover the DCR endpoint.
app.MapGet("/.well-known/oauth-protected-resource", (HttpContext ctx, IConfiguration cfg) =>
{
    var clientId = cfg["AzureAd:ClientId"];
    var baseUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}";
    return Results.Json(new
    {
        resource = $"api://{clientId}",
        authorization_servers = new[] { baseUrl },
        scopes_supported = new[] { $"api://{clientId}/mcp.access", "offline_access" },
        bearer_methods_supported = new[] { "header" }
    });
});

// Authorization Server Metadata (RFC 8414).
// Proxies Entra ID's real auth/token endpoints and adds our registration_endpoint
// so that DCR-aware clients (e.g. Copilot Studio) can register automatically.
app.MapGet("/.well-known/oauth-authorization-server", (HttpContext ctx, IConfiguration cfg) =>
    AuthServerMetadata(ctx, cfg));

// OpenID Connect Discovery — identical metadata for broader client compatibility.
app.MapGet("/.well-known/openid-configuration", (HttpContext ctx, IConfiguration cfg) =>
    AuthServerMetadata(ctx, cfg));

// OAuth 2.0 Dynamic Client Registration (RFC 7591).
// Returns the pre-registered Entra ID app so the caller can proceed with OAuth
// without manual configuration. The app is registered as a public client (no secret).
app.MapPost("/register", async (HttpContext ctx, IConfiguration cfg) =>
{
    var clientId = cfg["AzureAd:ClientId"];

    string[]? redirectUris = null;
    string? clientName = null;

    try
    {
        using var doc = await JsonDocument.ParseAsync(ctx.Request.Body);
        var root = doc.RootElement;
        if (root.TryGetProperty("redirect_uris", out var uris))
            redirectUris = uris.EnumerateArray().Select(u => u.GetString()!).ToArray();
        if (root.TryGetProperty("client_name", out var name))
            clientName = name.GetString();
    }
    catch { /* tolerate missing or malformed body */ }

    return Results.Json(new
    {
        client_id = clientId,
        client_name = clientName ?? "MCP Client",
        redirect_uris = redirectUris ?? Array.Empty<string>(),
        token_endpoint_auth_method = "none",
        grant_types = new[] { "authorization_code", "refresh_token" },
        response_types = new[] { "code" }
    }, statusCode: 201);
});

// ---------------------------------------------------------------------------

// MCP endpoint — Streamable HTTP at /mcp. This is what Copilot Studio calls.
app.MapMcp("/mcp").RequireAuthorization("McpAccess");

app.Run();

// Shared auth-server metadata used by both /.well-known/ endpoints.
static IResult AuthServerMetadata(HttpContext ctx, IConfiguration cfg)
{
    var tenantId = cfg["AzureAd:TenantId"];
    var baseUrl = $"{ctx.Request.Scheme}://{ctx.Request.Host}";
    return Results.Json(new
    {
        issuer = $"https://login.microsoftonline.com/{tenantId}/v2.0",
        authorization_endpoint = $"https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/authorize",
        token_endpoint = $"https://login.microsoftonline.com/{tenantId}/oauth2/v2.0/token",
        registration_endpoint = $"{baseUrl}/register",
        jwks_uri = $"https://login.microsoftonline.com/{tenantId}/discovery/v2.0/keys",
        response_types_supported = new[] { "code" },
        grant_types_supported = new[] { "authorization_code", "refresh_token" },
        token_endpoint_auth_methods_supported = new[] { "none", "client_secret_post" },
        code_challenge_methods_supported = new[] { "S256" }
    });
}
