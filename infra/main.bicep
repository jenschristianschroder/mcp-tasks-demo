targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Environment name (e.g. dev, prod). Used as a resource name suffix.')
param environmentName string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Entra ID tenant id')
param tenantId string = subscription().tenantId

@description('App registration client id for the Tasks API')
param tasksApiClientId string

@description('App registration client id for the MCP server')
param mcpServerClientId string

@secure()
@description('PostgreSQL admin password')
param postgresPassword string

var resourceToken = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var tags = { 'azd-env-name': environmentName }

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: 'acr${resourceToken}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: 'cae-${resourceToken}'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
  }
}

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-${resourceToken}'
  location: location
  tags: tags
}

// Grant the managed identity AcrPull on the registry.
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, 'AcrPull')
  scope: acr
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'    // AcrPull
    )
  }
}

// Azure Database for PostgreSQL Flexible Server
var pgServerName = 'pg-${resourceToken}'
var pgDatabaseName = 'tasks'
var pgAdminUser = 'tasksadmin'

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgServerName
  location: location
  tags: tags
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: pgAdminUser
    administratorLoginPassword: postgresPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: postgres
  name: pgDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// Allow Azure services (Container Apps) to connect to PostgreSQL.
resource pgFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: postgres
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource tasksApi 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-tasks-api-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'tasks-api' })
  dependsOn: [acrPullRole, pgDatabase, pgFirewall]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [{
        server: acr.properties.loginServer
        identity: identity.id
      }]
      secrets: [
        { name: 'pg-connection-string', value: 'Host=${postgres.properties.fullyQualifiedDomainName};Database=${pgDatabaseName};Username=${pgAdminUser};Password=${postgresPassword};SSL Mode=Require;Trust Server Certificate=true' }
      ]
    }
    template: {
      containers: [{
        name: 'tasks-api'
        image: '${acr.properties.loginServer}/tasks-api:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'AzureAd__TenantId', value: tenantId }
          { name: 'AzureAd__ClientId', value: tasksApiClientId }
          { name: 'AzureAd__Audience', value: 'api://${tasksApiClientId}' }
          { name: 'ConnectionStrings__TasksDb', secretRef: 'pg-connection-string' }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

resource mcpServer 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-mcp-server-${resourceToken}'
  location: location
  tags: union(tags, { 'azd-service-name': 'mcp-server' })
  dependsOn: [acrPullRole]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [{
        server: acr.properties.loginServer
        identity: identity.id
      }]
    }
    template: {
      containers: [{
        name: 'mcp-server'
        image: '${acr.properties.loginServer}/mcp-server:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'AzureAd__TenantId', value: tenantId }
          { name: 'AzureAd__ClientId', value: mcpServerClientId }
          { name: 'AzureAd__Audience', value: 'api://${mcpServerClientId}' }
          { name: 'AzureAd__ClientCredentials__0__ManagedIdentityClientId', value: identity.properties.clientId }
          { name: 'DownstreamApi__BaseUrl', value: 'https://${tasksApi.properties.configuration.ingress.fqdn}' }
          { name: 'DownstreamApi__Scopes', value: 'api://${tasksApiClientId}/Tasks.ReadWrite' }
        ]
      }]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output AZURE_LOCATION string = location
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = acr.properties.loginServer
output AZURE_CONTAINER_REGISTRY_NAME string = acr.name
output TASKS_API_URL string = 'https://${tasksApi.properties.configuration.ingress.fqdn}'
output MCP_SERVER_URL string = 'https://${mcpServer.properties.configuration.ingress.fqdn}'
output MCP_ENDPOINT string = 'https://${mcpServer.properties.configuration.ingress.fqdn}/mcp'
