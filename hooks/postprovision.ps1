<#
.SYNOPSIS
  Post-provision hook:
  1. Adds the deployed EasyAuth callback redirect URI to the web app registration.
  2. Adds the Swagger OAuth redirect URI (SPA) to the Tasks API registration.
  3. Creates a federated identity credential on the MCP server app registration
     so the managed identity can authenticate via OBO without a client secret.
#>
$ErrorActionPreference = "Stop"

$tenantId       = $env:AZURE_TENANT_ID
$mcpClientId    = $env:MCP_SERVER_CLIENT_ID
$tasksApiClientId = $env:TASKS_API_CLIENT_ID
$webAppClientId = $env:WEB_APP_CLIENT_ID
$tasksApiUrl    = $env:TASKS_API_URL
$webAppUrl      = $env:WEB_APP_URL
$envName        = $env:AZURE_ENV_NAME
$rgName         = "rg-$envName"

# ── Add EasyAuth callback as web redirect URI ────────────────────────────────
if ($webAppClientId -and $webAppUrl) {
  Write-Host "==> Adding EasyAuth callback redirect URI to web app registration..."
  $webAppObjId = az ad app show --id $webAppClientId --query id -o tsv
  $callbackUri = "$webAppUrl/.auth/login/aad/callback"

  # Get existing web redirect URIs and add the callback if missing
  $existingUris = az ad app show --id $webAppClientId --query "web.redirectUris" -o json | ConvertFrom-Json
  if (-not $existingUris) { $existingUris = @() }
  if ($existingUris -notcontains $callbackUri) {
    $updatedUris = @($existingUris) + @($callbackUri)
    @{
      web = @{
        redirectUris = $updatedUris
        implicitGrantSettings = @{
          enableIdTokenIssuance = $true
        }
      }
    } | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 webapp-redirect.json
    az rest --method PATCH `
      --uri "https://graph.microsoft.com/v1.0/applications/$webAppObjId" `
      --body "@webapp-redirect.json" `
      --headers "Content-Type=application/json"
    Remove-Item webapp-redirect.json -Force
    Write-Host "    Added web redirect URI: $callbackUri"
  } else {
    Write-Host "    Web redirect URI already exists: $callbackUri"
  }
} else {
  Write-Host "WARNING: WEB_APP_CLIENT_ID or WEB_APP_URL not set. Skipping redirect URI setup."
}

# ── Add Swagger OAuth redirect as SPA redirect URI on Tasks API ──────────────
if ($tasksApiClientId -and $tasksApiUrl) {
  Write-Host "==> Adding Swagger OAuth redirect URI to Tasks API registration..."
  $tasksApiObjId = az ad app show --id $tasksApiClientId --query id -o tsv
  $swaggerRedirect = "$tasksApiUrl/swagger/oauth2-redirect.html"

  $existingSpaUris = az ad app show --id $tasksApiClientId --query "spa.redirectUris" -o json | ConvertFrom-Json
  if (-not $existingSpaUris) { $existingSpaUris = @() }
  if ($existingSpaUris -notcontains $swaggerRedirect) {
    $updatedSpaUris = @($existingSpaUris) + @($swaggerRedirect)
    @{ spa = @{ redirectUris = $updatedSpaUris } } | ConvertTo-Json -Depth 5 | Out-File -Encoding utf8 tasks-api-spa.json
    az rest --method PATCH `
      --uri "https://graph.microsoft.com/v1.0/applications/$tasksApiObjId" `
      --body "@tasks-api-spa.json" `
      --headers "Content-Type=application/json"
    Remove-Item tasks-api-spa.json -Force
    Write-Host "    Added SPA redirect URI: $swaggerRedirect"
  } else {
    Write-Host "    SPA redirect URI already exists: $swaggerRedirect"
  }
} else {
  Write-Host "WARNING: TASKS_API_CLIENT_ID or TASKS_API_URL not set. Skipping Swagger redirect URI setup."
}

# Resolve the managed identity provisioned by Bicep
$miPrincipalId = az identity list -g $rgName --query "[0].principalId" -o tsv 2>$null
if (-not $miPrincipalId) {
  Write-Warning "Could not resolve managed identity in resource group '$rgName'. Skipping federated credential setup."
  exit 0
}

# Check if the federated credential already exists
$existing = az ad app federated-credential list --id $mcpClientId --query "[?name=='managed-identity-obo']" 2>$null | ConvertFrom-Json
if ($existing -and $existing.Count -gt 0) {
  Write-Host "Federated credential 'managed-identity-obo' already exists. Skipping."
  exit 0
}

Write-Host "==> Creating federated identity credential on app '$mcpClientId' trusting managed identity '$miPrincipalId'"

$body = @{
  name        = "managed-identity-obo"
  issuer      = "https://login.microsoftonline.com/$tenantId/v2.0"
  subject     = $miPrincipalId
  audiences   = @("api://AzureADTokenExchange")
  description = "Trust the Container App managed identity for OBO flow"
} | ConvertTo-Json -Compress

$body | Out-File -Encoding utf8 fic-body.json
az ad app federated-credential create --id $mcpClientId --parameters "@fic-body.json"
Remove-Item fic-body.json -Force

Write-Host "==> Federated identity credential created successfully."
