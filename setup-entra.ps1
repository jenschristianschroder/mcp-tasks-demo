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
az ad app update --id $tasksApiId --identifier-uris "api://$tasksApiId" | Out-Null

# Expose Tasks.ReadWrite scope
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
  --uri "https://graph.microsoft.com/v1.0/applications(appId='$tasksApiId')" `
  --body "@tasks-api-manifest.json" | Out-Null
Remove-Item tasks-api-manifest.json -Force

az ad sp create --id $tasksApiId 2>$null | Out-Null

# ── 2. MCP server app registration ──────────────────────────────────────────

Write-Host "==> Creating MCP server app registration: $McpServerAppName"
$mcpApp = az ad app create --display-name $McpServerAppName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$mcpId = $mcpApp.appId
az ad app update --id $mcpId --identifier-uris "api://$mcpId" | Out-Null

# Expose mcp.access scope, set redirect URIs, require Tasks API permission
$mcpScopeId = [guid]::NewGuid().ToString()
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
  requiredResourceAccess = @(@{
    resourceAppId  = $tasksApiId
    resourceAccess = @(@{ id = $tasksScopeId; type = "Scope" })
  })
} | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 mcp-manifest.json

az rest --method PATCH `
  --uri "https://graph.microsoft.com/v1.0/applications(appId='$mcpId')" `
  --body "@mcp-manifest.json" | Out-Null
Remove-Item mcp-manifest.json -Force

az ad sp create --id $mcpId 2>$null | Out-Null

# Pre-authorize Copilot Studio as a known client (skip consent)
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
  --uri "https://graph.microsoft.com/v1.0/applications(appId='$mcpId')" `
  --body "@mcp-preauth.json" | Out-Null
Remove-Item mcp-preauth.json -Force

# ── 3. GitHub Actions service principal (OIDC, no secret) ────────────────────

Write-Host "==> Creating GitHub Actions service principal: $GitHubSpName"
$ghApp = az ad app create --display-name $GitHubSpName | ConvertFrom-Json
$ghAppId = $ghApp.appId
az ad sp create --id $ghAppId 2>$null | Out-Null
$ghSpId = (az ad sp show --id $ghAppId --query id -o tsv)

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
Write-Host ""
Write-Host "NOTE: You still need to grant admin consent in the Azure Portal:"
Write-Host "      Entra ID -> App registrations -> $McpServerAppName ->"
Write-Host "      API permissions -> Grant admin consent."
