# Registering the MCP server in Copilot Studio

After `azd up` succeeds, you have:

- **MCP endpoint**: `https://ca-mcp-server-<token>.<region>.azurecontainerapps.io/mcp`
- **MCP server app id**: `<MCP_SERVER_CLIENT_ID>`
- **MCP scope**: `api://<MCP_SERVER_CLIENT_ID>/mcp.access`

## 1. Open Copilot Studio

Go to <https://copilotstudio.microsoft.com> and open your agent (or create a new one).

## 2. Add the MCP server as a tool

1. In the agent, open **Tools** -> **+ Add a tool** -> **Model Context Protocol**.
2. Choose **Custom MCP server**.
3. Fill in:
   - **Server name**: `Tasks MCP`
   - **Server description**: `Manage tasks via CRUD operations`
   - **Server URL**: paste the MCP endpoint URL from `azd` output, e.g.
     `https://ca-mcp-server-<token>.<region>.azurecontainerapps.io/mcp`
4. Under **Authentication**, choose **OAuth 2.0**.
5. Under **Type**, choose **Dynamic discovery**.
   - The server exposes `/.well-known/oauth-protected-resource` and
     `/.well-known/oauth-authorization-server` with a `registration_endpoint`
     that handles Dynamic Client Registration (RFC 7591) automatically.
   - Copilot Studio will discover the Entra ID auth/token endpoints and
     register itself as a public client — no manual configuration needed.
6. Save. Copilot Studio will probe the server, list the 5 tools, and you can toggle them on.

> **Fallback — Manual configuration**
>
> If Dynamic discovery does not work, select **Manual** and fill in:
>
> | Field | Value |
> |---|---|
> | **Client ID** | `<MCP_SERVER_CLIENT_ID>` |
> | **Client secret** | create one with `az ad app credential reset --id <MCP_SERVER_CLIENT_ID> --append --display-name "Copilot Studio"` |
> | **Authorization URL** | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/authorize` |
> | **Token URL** | `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token` |
> | **Scope** | `api://<MCP_SERVER_CLIENT_ID>/mcp.access offline_access` |

## 3. Test it

In the **Test your agent** pane:

> "Create a task called 'Prep for review' due Friday"
> "What's on my task list?"
> "Mark task 3 as done"

The first call triggers an OAuth consent prompt. After consent, the MCP server receives your user token, exchanges it via OBO for a Tasks API token, and writes the data scoped to your `oid`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `401` from MCP server | The token audience does not match `api://<MCP_SERVER_CLIENT_ID>`. Re-check the scope in Copilot Studio. |
| `403` `insufficient_scope` | The user did not consent to `mcp.access`. Grant admin consent in Azure Portal. |
| `401` from Tasks API | OBO failed. Verify `MCP_SERVER_CLIENT_SECRET` is set on the MCP Container App and the MCP app has API permission `Tasks.ReadWrite` (admin-consented). |
| Tools list is empty | Check `/healthz` is reachable, then check `https://<mcp-fqdn>/.well-known/oauth-protected-resource` returns JSON. |
