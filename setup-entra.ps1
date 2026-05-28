<#
.SYNOPSIS
  Creates two Entra ID app registrations for the MCP Tasks demo:
    1. tasks-api-app     - exposes scope Tasks.ReadWrite
    2. mcp-server-app    - confidential client, has API permission to (1),
                           exposes scope mcp.access for Copilot Studio.

.DESCRIPTION
  Run after `az login`. Outputs the env vars you need to feed to `azd env set`.
  Requires: Az CLI, Microsoft Graph CLI (mg) OR Az CLI 2.50+ with `az ad` commands.

.EXAMPLE
  ./setup-entra.ps1 -EnvName dev
#>

param(
  [Parameter(Mandatory = $true)] [string] $EnvName,
  [string] $TasksApiAppName = "mcp-tasks-api-$EnvName",
  [string] $McpServerAppName = "mcp-tasks-server-$EnvName"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Creating Tasks API app registration: $TasksApiAppName"
$tasksApi = az ad app create --display-name $TasksApiAppName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$tasksApiId = $tasksApi.appId
az ad app update --id $tasksApiId --identifier-uris "api://$tasksApiId" | Out-Null

# Expose Tasks.ReadWrite scope
$tasksScopeId = [guid]::NewGuid().ToString()
$tasksApiManifest = @{
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
} | ConvertTo-Json -Depth 10 -Compress
$tasksApiManifest | Out-File -Encoding utf8 tasks-api-manifest.json
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications(appId='$tasksApiId')" `
  --headers "Content-Type=application/json" --body "@tasks-api-manifest.json" | Out-Null
Remove-Item tasks-api-manifest.json -Force

# Service principal (needed for tenant consent)
az ad sp create --id $tasksApiId | Out-Null

Write-Host "==> Creating MCP server app registration: $McpServerAppName"
$mcpApp = az ad app create --display-name $McpServerAppName --sign-in-audience AzureADMyOrg | ConvertFrom-Json
$mcpId = $mcpApp.appId
az ad app update --id $mcpId --identifier-uris "api://$mcpId" | Out-Null

# Expose mcp.access scope (consumed by Copilot Studio)
$mcpScopeId = [guid]::NewGuid().ToString()
$mcpManifest = @{
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
} | ConvertTo-Json -Depth 10 -Compress
$mcpManifest | Out-File -Encoding utf8 mcp-manifest.json
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications(appId='$mcpId')" `
  --headers "Content-Type=application/json" --body "@mcp-manifest.json" | Out-Null
Remove-Item mcp-manifest.json -Force

# Service principal
az ad sp create --id $mcpId | Out-Null

# Add federated identity credential to trust the user-assigned managed identity.
# The managed identity principal ID will be the subject; set it after `azd up` provisions the identity.
# For now, create a placeholder that will be updated by the post-provision hook.
Write-Host "==> Federated identity credential must be added after infrastructure is provisioned."
Write-Host "    Run the following after 'azd up' to link the managed identity:"
Write-Host ""
Write-Host "    `$miObjectId = az identity show -g <resource-group> -n <identity-name> --query principalId -o tsv"
Write-Host "    az ad app federated-credential create --id $mcpId --parameters @{"
Write-Host "      name        = 'managed-identity-obo'"
Write-Host "      issuer      = 'https://login.microsoftonline.com/$tenantId/v2.0'"
Write-Host "      subject     = `$miObjectId"
Write-Host "      audiences   = @('api://AzureADTokenExchange')"
Write-Host "      description = 'Trust the Container App managed identity for OBO'"
Write-Host "    }"

# Pre-authorize Copilot Studio / Power Platform as a known client (skip consent)
$copilotStudioClientId = "96ff4394-9197-43aa-b393-6a41652e21f8"  # Copilot Studio first-party client id
$preAuth = @{
  api = @{
    preAuthorizedApplications = @(@{
      appId               = $copilotStudioClientId
      delegatedPermissionIds = @($mcpScopeId)
    })
  }
} | ConvertTo-Json -Depth 10 -Compress
$preAuth | Out-File -Encoding utf8 mcp-preauth.json
az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications(appId='$mcpId')" `
  --headers "Content-Type=application/json" --body "@mcp-preauth.json" | Out-Null
Remove-Item mcp-preauth.json -Force

$tenantId = (az account show | ConvertFrom-Json).tenantId

Write-Host ""
Write-Host "============================================================"
Write-Host " Run the following commands to wire the values into azd:"
Write-Host "============================================================"
Write-Host ""
Write-Host "  azd env set AZURE_TENANT_ID            $tenantId"
Write-Host "  azd env set TASKS_API_CLIENT_ID        $tasksApiId"
Write-Host "  azd env set MCP_SERVER_CLIENT_ID       $mcpId"
Write-Host ""
Write-Host "Tasks API scope:    api://$tasksApiId/Tasks.ReadWrite"
Write-Host "MCP server scope:   api://$mcpId/mcp.access"
Write-Host ""
Write-Host "NOTE: You still need to grant admin consent in the Azure Portal"
Write-Host "      (Entra ID -> App registrations -> $McpServerAppName ->"
Write-Host "       API permissions -> Grant admin consent)."
