# MCP Tasks Demo — Copilot Studio + Azure Container Apps + Entra ID

A complete, deployable sample that demonstrates an enterprise-grade MCP server:

- **MCP server** (.NET 9, `ModelContextProtocol.AspNetCore`) hosted on Azure Container Apps
- **Streamable HTTP transport** (required by Copilot Studio)
- **Entra ID authentication** with **On-Behalf-Of** flow
- **Separate Tasks REST API** (also on Container Apps) exposing CRUD on a Tasks/To-do resource, backed by **Azure Database for PostgreSQL**
- **Two-app-registration** topology — clean separation between the MCP surface and the downstream API

## Architecture

```
+-----------------+    OAuth 2.1 + PKCE   +-------------+    On-Behalf-Of    +-----------+
| Copilot Studio  | --------------------> | MCP Server  | -----------------> | Tasks API |
|  (agent)        | <-- Streamable HTTP-- |  /mcp       | <-- JSON / JWT --- |  /tasks   |
+-----------------+                       +-------------+                    +-----------+
                                                |                                  |
                                                +-------- Entra ID ----------------+
                                                  2 app registrations
                                                  - mcp-server-app  (scope: mcp.access)
                                                  - tasks-api-app   (scope: Tasks.ReadWrite)
```

## Repository layout

```
mcp-tasks-demo/
  azure.yaml                       # azd template
  infra/
    main.bicep                     # Container Apps env, ACR, PostgreSQL, identity, both apps
    main.parameters.json
  tasks-api/                       # Downstream REST API
    Program.cs                     # Minimal API + EF Core (PostgreSQL) + JWT bearer
    TodoTask.cs                    # Model + DTOs
    TasksDbContext.cs              # EF Core DbContext
    Migrations/                    # EF Core migrations
    appsettings.json
    Dockerfile
  mcp-server/                      # MCP server
    Program.cs                     # MapMcp + OBO + protected-resource metadata
    TaskTools.cs                   # 5 MCP tools (CRUD)
    TasksApiClient.cs              # Uses ITokenAcquisition for OBO
    TodoTask.cs                    # Client-side model + DTOs
    appsettings.json
    Dockerfile
  setup-entra.ps1                  # Creates both app registrations
  register-in-copilot-studio.md    # Copilot Studio configuration walk-through
```

## Prerequisites

- An Entra ID tenant where you can create app registrations
- An Azure subscription with permission to create Container Apps and ACR
- [Azure Developer CLI](https://aka.ms/azd) (`azd`) 1.10+
- [Azure CLI](https://aka.ms/azcli) (`az`) 2.60+
- .NET 9 SDK (for local dev only)
- PowerShell 7+ (Linux/macOS/Windows)

## Quick start — 5 commands

```pwsh
# 1. Sign in
az login
azd auth login

# 2. Create the two Entra ID app registrations and print env vars
./setup-entra.ps1 -EnvName dev

# 3. Initialize azd env, paste the values from the script output
azd env new dev
azd env set AZURE_TENANT_ID            <tenant-id>
azd env set TASKS_API_CLIENT_ID        <tasks-api-app-id>
azd env set MCP_SERVER_CLIENT_ID       <mcp-server-app-id>
azd env set POSTGRES_PASSWORD          <strong-password>

# 4. Deploy everything (builds two images, pushes to ACR, provisions Container Apps + PostgreSQL)
#    The post-provision hook automatically creates a federated identity credential
#    on the MCP server app registration, linking it to the managed identity.
azd up

# 5. Grant admin consent for the API permission in the Azure portal:
#    Entra ID -> App registrations -> mcp-tasks-server-dev -> API permissions -> Grant admin consent
```

After `azd up` finishes, the output prints the MCP endpoint, e.g.:

```
MCP_ENDPOINT = https://ca-mcp-server-xxxxx.<region>.azurecontainerapps.io/mcp
```

Use that URL in `scripts/register-in-copilot-studio.md` to wire it into your agent.

## How the auth flow works

1. **Copilot Studio** initiates OAuth 2.1 + PKCE against Entra ID, requesting the scope `api://<mcp-server-app-id>/mcp.access`.
2. The user signs in and consents. Copilot Studio receives a user token whose audience is the **MCP server**.
3. Every Streamable HTTP call to `/mcp` carries that token in the `Authorization` header. `Microsoft.Identity.Web` validates it.
4. When a tool needs to call the Tasks API, the MCP server uses **`ITokenAcquisition.GetAccessTokenForUserAsync`** to perform the **On-Behalf-Of** exchange — the user token is swapped for a new token whose audience is the **Tasks API** and whose scope is `Tasks.ReadWrite`.
5. The Tasks API validates that new token, reads `oid` from the claims, and scopes data access to that user.

This is the canonical Microsoft pattern for delegated access through a middle-tier API and is exactly the shape Microsoft uses for Graph-fronting services.

## OAuth 2.1 Protected Resource Metadata

Per the MCP **June 2025 authorization spec**, the server exposes:

```
GET /.well-known/oauth-protected-resource
```

This tells Copilot Studio (and any spec-compliant client) which Entra ID authority to use without out-of-band configuration. See `mcp-server/Program.cs`.

## Local development

```pwsh
# Terminal 1 — Tasks API on http://localhost:5001
cd tasks-api
dotnet user-secrets set "AzureAd:TenantId"  <tenant-id>
dotnet user-secrets set "AzureAd:ClientId"  <tasks-api-app-id>
dotnet user-secrets set "AzureAd:Audience"  api://<tasks-api-app-id>
dotnet run --urls http://localhost:5001

# Terminal 2 — MCP server on http://localhost:5000
cd mcp-server
dotnet user-secrets set "AzureAd:TenantId"           <tenant-id>
dotnet user-secrets set "AzureAd:ClientId"           <mcp-server-app-id>
dotnet user-secrets set "AzureAd:ClientSecret"       <mcp-server-secret>
dotnet user-secrets set "DownstreamApi:BaseUrl"      http://localhost:5001
dotnet user-secrets set "DownstreamApi:Scopes"       api://<tasks-api-app-id>/Tasks.ReadWrite
dotnet run --urls http://localhost:5000
```

You can then point the MCP Inspector (`npx @modelcontextprotocol/inspector`) at `http://localhost:5000/mcp` to test tools without going through Copilot Studio.

## MCP tools exposed

| Tool name      | Purpose                                  |
| -------------- | ---------------------------------------- |
| `list_tasks`   | Return all tasks owned by the user.      |
| `get_task`     | Fetch a single task by id.               |
| `create_task`  | Create a task (title, description, due). |
| `update_task`  | Partial update of any field + status.    |
| `delete_task`  | Delete a task by id.                     |

## Security notes

- Each user's tasks are isolated by `oid` (Entra object id) in the database. The Tasks API never trusts a user id passed in the request body.
- The MCP server runs as a **confidential client** — the client secret never leaves the Container App. For production, swap to **Federated Identity Credentials** (workload identity) and remove the secret entirely.
- The Tasks API requires the `Tasks.ReadWrite` scope on every endpoint. The MCP server requires the `mcp.access` scope on `/mcp`. `/healthz` and the protected-resource metadata endpoint are intentionally anonymous.
- For production, put the Tasks API behind **internal-only** Container Apps ingress and call it from the MCP server over the private VNet. The current sample uses external ingress on both for ease of testing.

## Costs

With both Container Apps scaled to `minReplicas: 1` at 0.5 vCPU / 1 GiB, expect roughly $40-60/month per app plus ACR Basic ($5/month). Scaling to zero (`minReplicas: 0`) brings idle cost close to zero at the price of a cold-start on the first request.

## Cleanup

```pwsh
azd down --purge --force
```

This deletes the resource group, the ACR registry, and purges the app registrations created via the portal **only if they were created by azd** — the two registrations from `setup-entra.ps1` must be deleted separately (`az ad app delete --id <app-id>`).
