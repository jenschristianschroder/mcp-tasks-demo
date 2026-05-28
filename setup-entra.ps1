<#
.SYNOPSIS
  One-time setup for the MCP Tasks demo. Creates:
    1. tasks-api-app          - Entra ID app exposing scope Tasks.ReadWrite
    2. mcp-server-app         - Entra ID app exposing scope mcp.access, with API permission to (1)
    3. github-actions SP      - Service principal with Contributor + RBAC Admin roles and
                                a federated credential for GitHub Actions OIDC login

.DESCRIPTION
  Run after `az login`. Outputs the env vars for azd and the GitHub Actions variables/secrets.
  The MCP server uses federated identity (managed identity) instead of a client secret for OBO.

.PARAMETER EnvName
  Environment name suffix (e.g. dev, staging, prod).

.PARAMETER GitHubRepo
  GitHub repo in "owner/repo" format for the federated credential subject.

.EXAMPLE
  ./setup-entra.ps1 -EnvName dev -GitHubRepo "jenschristianschroder/mcp-tasks-demo"
#>

param(
  [Parameter(Mandatory = $true)] [string] $EnvName,
  [Parameter(Mandatory = $true)] [string] $GitHubRepo,
  [string] $TasksApiAppName = "mcp-tasks-api-$EnvName",
  [string] $McpServerAppName = "mcp-tasks-server-$EnvName",
  [string] $GitHubSpName = "github-mcp-tasks-$EnvName"
)

$ErrorActionPreference = "Stop"

$tenantId = (az account show | ConvertFrom-Json).tenantId
$subscriptionId = (az account show --query id -o tsv)

# ── 1. Tasks API app registration ────────────────────────────────────────────

Write-Host "==> Creating Tasks API app registration: $TasksApiAppName"
$tasksApi = az ad app create --display-name $TasksApiAppName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$tasksApiId = $tasksApi.appId
$tasksApiObjId = $tasksApi.id
Write-Host "    App ID: $tasksApiId"
az ad app update --id $tasksApiId --identifier-uris "api://$tasksApiId" | Out-Null

# Expose Tasks.ReadWrite scope (skip if it already exists)
$existingTasksScope = az ad app show --id $tasksApiId --query "api.oauth2PermissionScopes[?value=='Tasks.ReadWrite'].id" -o tsv
if ($existingTasksScope) {
  Write-Host "    Tasks.ReadWrite scope already exists: $existingTasksScope"
  $tasksScopeId = $existingTasksScope
} else {
  Write-Host "    Exposing Tasks.ReadWrite scope..."
  $tasksScopeId = [guid]::NewGuid().ToString()
  @{
    api = @{
      oauth2PermissionScopes = @(@{
        id                      = $tasksScopeId
        adminConsentDescription = "Allow the application to read and write tasks on behalf of the signed-in user."
        adminConsentDisplayName = "Read/write tasks"
        userConsentDescription  = "Allow the app to manage your tasks."
        userConsentDisplayName  = "Manage your tasks"
        value                   = "Tasks.ReadWrite"
        type                    = "User"
        isEnabled               = $true
      })
    }
  } | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 tasks-api-manifest.json

  az rest --method PATCH `
    --uri "https://graph.microsoft.com/v1.0/applications/$tasksApiObjId" `
    --body "@tasks-api-manifest.json"
  if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set Tasks.ReadWrite scope on Tasks API app." }
  Remove-Item tasks-api-manifest.json -Force

  # Verify scope was created
  $tasksScopeId = az ad app show --id $tasksApiId --query "api.oauth2PermissionScopes[?value=='Tasks.ReadWrite'].id" -o tsv
  if (-not $tasksScopeId) { Write-Error "Tasks.ReadWrite scope was not created. Check Graph API permissions." }
}
Write-Host "    Tasks.ReadWrite scope ID: $tasksScopeId"

# Ensure the Tasks API service principal exists
$existingSp = az ad sp show --id $tasksApiId --query appId -o tsv 2>$null
if (-not $existingSp) {
  Write-Host "    Creating Tasks API service principal..."
  az ad sp create --id $tasksApiId | Out-Null
} else {
  Write-Host "    Tasks API service principal already exists."
}

# ── 2. MCP server app registration ──────────────────────────────────────────

Write-Host "==> Creating MCP server app registration: $McpServerAppName"
$mcpApp = az ad app create --display-name $McpServerAppName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$mcpId = $mcpApp.appId
$mcpObjId = $mcpApp.id
Write-Host "    App ID: $mcpId"
az ad app update --id $mcpId --identifier-uris "api://$mcpId" | Out-Null

# Step 2a: Expose mcp.access scope and set redirect URIs (skip scope if exists)
$existingMcpScope = az ad app show --id $mcpId --query "api.oauth2PermissionScopes[?value=='mcp.access'].id" -o tsv
if ($existingMcpScope) {
  Write-Host "    mcp.access scope already exists: $existingMcpScope"
  $mcpScopeId = $existingMcpScope
} else {
  Write-Host "    Exposing mcp.access scope..."
  $mcpScopeId = [guid]::NewGuid().ToString()
}

# Always PATCH to ensure redirect URIs are set (idempotent)
@{
  api = @{
    oauth2PermissionScopes = @(@{
      id                      = $mcpScopeId
      adminConsentDescription = "Allow the application to call the MCP server on behalf of the signed-in user."
      adminConsentDisplayName = "Access the MCP server"
      userConsentDescription  = "Allow the app to call the MCP server on your behalf."
      userConsentDisplayName  = "Access the MCP server"
      value                   = "mcp.access"
      type                    = "User"
      isEnabled               = $true
    })
  }
  web = @{
    redirectUris = @(
      "https://copilotstudio.microsoft.com/connectors/oauth/redirect",
      "https://global.consent.azure-apim.net/redirect"
    )
  }
} | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 mcp-scope.json

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$mcpObjId" `
  --body "@mcp-scope.json"
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to set mcp.access scope on MCP server app." }
Remove-Item mcp-scope.json -Force

# Verify scope
$mcpScopeId = az ad app show --id $mcpId --query "api.oauth2PermissionScopes[?value=='mcp.access'].id" -o tsv
if (-not $mcpScopeId) { Write-Error "mcp.access scope was not created. Check Graph API permissions." }
Write-Host "    mcp.access scope ID: $mcpScopeId"

# Step 2b: Create service principal (must exist before adding permissions)
$existingMcpSp = az ad sp show --id $mcpId --query appId -o tsv 2>$null
if (-not $existingMcpSp) {
  Write-Host "    Creating MCP server service principal..."
  az ad sp create --id $mcpId | Out-Null
} else {
  Write-Host "    MCP server service principal already exists."
}

# Step 2c: Add Tasks.ReadWrite API permission via CLI (more reliable than PATCH requiredResourceAccess)
Write-Host "    Adding Tasks.ReadWrite permission to MCP server app..."
az ad app permission add --id $mcpId --api $tasksApiId --api-permissions "${tasksScopeId}=Scope" | Out-Null

# Step 2d: Grant admin consent
Write-Host "    Granting admin consent..."
az ad app permission admin-consent --id $mcpId 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Host "    WARNING: Admin consent could not be granted automatically."
  Write-Host "             Grant it manually: Entra ID -> App registrations -> $McpServerAppName -> API permissions -> Grant admin consent"
}

# Step 2e: Enable public client flows (required for DCR with token_endpoint_auth_method=none)
Write-Host "    Enabling public client flows..."
az ad app update --id $mcpId --is-fallback-public-client true | Out-Null

# Step 2f: Pre-authorize Copilot Studio as a known client (skip consent)
Write-Host "    Pre-authorizing Copilot Studio..."
$copilotStudioClientId = "96ff4394-9197-43aa-b393-6a41652e21f8"
@{
  api = @{
    preAuthorizedApplications = @(@{
      appId                  = $copilotStudioClientId
      delegatedPermissionIds = @($mcpScopeId)
    })
  }
} | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 mcp-preauth.json

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications/$mcpObjId" `
  --body "@mcp-preauth.json"
if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to pre-authorize Copilot Studio. You may need to do this manually." }
Remove-Item mcp-preauth.json -Force

# ── 3. GitHub Actions service principal (OIDC, no secret) ────────────────────

Write-Host "==> Creating GitHub Actions service principal: $GitHubSpName"
$ghApp = az ad app create --display-name $GitHubSpName | ConvertFrom-Json
$ghAppId = $ghApp.appId
Write-Host "    App ID: $ghAppId"

$existingGhSp = az ad sp show --id $ghAppId --query id -o tsv 2>$null
if (-not $existingGhSp) {
  Write-Host "    Creating service principal..."
  az ad sp create --id $ghAppId | Out-Null
  $ghSpId = (az ad sp show --id $ghAppId --query id -o tsv)
} else {
  Write-Host "    Service principal already exists."
  $ghSpId = $existingGhSp
}

# Assign Contributor + Role Based Access Control Administrator
Write-Host "    Assigning Contributor role..."
az role assignment create `
  --assignee-object-id $ghSpId `
  --assignee-principal-type ServicePrincipal `
  --role Contributor `
  --scope "/subscriptions/$subscriptionId" | Out-Null

Write-Host "    Assigning Role Based Access Control Administrator role..."
az role assignment create `
  --assignee-object-id $ghSpId `
  --assignee-principal-type ServicePrincipal `
  --role "Role Based Access Control Administrator" `
  --scope "/subscriptions/$subscriptionId" | Out-Null

# Federated credential for GitHub Actions OIDC
Write-Host "    Creating federated credential for repo $GitHubRepo..."
@{
  name      = "github-actions-main"
  issuer    = "https://token.actions.githubusercontent.com"
  subject   = "repo:${GitHubRepo}:ref:refs/heads/main"
  audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json | Out-File -Encoding utf8 gh-fic.json

az ad app federated-credential create --id $ghAppId --parameters "@gh-fic.json" | Out-Null
Remove-Item gh-fic.json -Force

# ── Output ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "============================================================"
Write-Host " azd env vars (for local deployment):"
Write-Host "============================================================"
Write-Host ""
Write-Host "  azd env set AZURE_TENANT_ID          $tenantId"
Write-Host "  azd env set TASKS_API_CLIENT_ID      $tasksApiId"
Write-Host "  azd env set MCP_SERVER_CLIENT_ID     $mcpId"
Write-Host "  azd env set POSTGRES_PASSWORD        <strong-password>"
Write-Host ""
Write-Host "============================================================"
Write-Host " GitHub Actions variables (Settings > Variables > Actions):"
Write-Host "============================================================"
Write-Host ""
Write-Host "  AZURE_CLIENT_ID         $ghAppId"
Write-Host "  AZURE_TENANT_ID         $tenantId"
Write-Host "  AZURE_SUBSCRIPTION_ID   $subscriptionId"
Write-Host "  AZURE_ENV_NAME          $EnvName"
Write-Host "  AZURE_LOCATION          <your-region>"
Write-Host "  TASKS_API_CLIENT_ID     $tasksApiId"
Write-Host "  MCP_SERVER_CLIENT_ID    $mcpId"
Write-Host ""
Write-Host "============================================================"
Write-Host " GitHub Actions secrets (Settings > Secrets > Actions):"
Write-Host "============================================================"
Write-Host ""
Write-Host "  POSTGRES_PASSWORD       <strong-password>"
Write-Host ""
Write-Host "============================================================"
Write-Host " Scopes:"
Write-Host "============================================================"
Write-Host ""
Write-Host "  Tasks API:    api://$tasksApiId/Tasks.ReadWrite"
Write-Host "  MCP server:   api://$mcpId/mcp.access"
Write-Host ""
Write-Host "NOTE: The post-provision hook (hooks/postprovision.ps1) will"
Write-Host "      automatically create the federated identity credential"
Write-Host "      on the MCP server app registration after deployment."
