<#
.SYNOPSIS
  Post-provision hook: creates a federated identity credential on the MCP server
  app registration so the managed identity can authenticate via OBO without a client secret.
#>
$ErrorActionPreference = "Stop"

$tenantId      = $env:AZURE_TENANT_ID
$mcpClientId   = $env:MCP_SERVER_CLIENT_ID
$envName       = $env:AZURE_ENV_NAME
$rgName        = "rg-$envName"

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
