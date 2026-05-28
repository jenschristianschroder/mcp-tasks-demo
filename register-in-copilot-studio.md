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
   - **Server URL**: paste the `MCP_ENDPOINT` from `azd` output
   - **Transport**: `Streamable HTTP`
4. Under **Authentication**, choose **OAuth 2.0**:
   - **Identity provider**: `Microsoft Entra ID`
   - **Client id**: `<MCP_SERVER_CLIENT_ID>`
   - **Client secret**: `<MCP_SERVER_CLIENT_SECRET>` (the one printed by `setup-entra.ps1`)
   - **Authorization URL**: `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/authorize`
   - **Token URL**: `https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token`
   - **Scope**: `api://<MCP_SERVER_CLIENT_ID>/mcp.access offline_access`
5. Save. Copilot Studio will probe the server, list the 5 tools, and you can toggle them on.

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
