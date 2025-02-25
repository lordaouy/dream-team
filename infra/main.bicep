targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed([
  'northcentralusstage'
  'westus2'
  'northeurope'
  'eastus'
  'eastasia'
  'northcentralus'
  'germanywestcentral'
  'polandcentral'
  'italynorth'
  'switzerlandnorth'
  'swedencentral'
  'norwayeast'
  'japaneast'
  'australiaeast'
  'westcentralus'
  'westeurope'
]) // limit to regions where Dynamic sessions are available as of 2024-11-29
param location string

param srcExists bool
@secure()
param srcDefinition object

@description('Id of the user or app to assign application roles')
param principalId string

// Tags that should be applied to all resources.
// 
// Note that 'azd-service-name' tags should be applied separately to service host resources.
// Example usage:
//   tags: union(tags, { 'azd-service-name': <service name in azure.yaml> })
var tags = {
  'azd-env-name': environmentName
}

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
// New variable for prefix used in customSubDomainName
var prefix = 'dreamv2'

resource rg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

module monitoring './shared/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
  }
  scope: rg
}

module dashboard './shared/dashboard-web.bicep' = {
  name: 'dashboard'
  params: {
    name: '${abbrs.portalDashboards}${resourceToken}'
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    location: location
    tags: tags
  }
  scope: rg
}

module registry './shared/registry.bicep' = {
  name: 'registry'
  params: {
    location: location
    tags: tags
    name: '${abbrs.containerRegistryRegistries}${resourceToken}'
  }
  scope: rg
}

module keyVault './shared/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: '${abbrs.keyVaultVaults}${resourceToken}'
    principalId: principalId
  }
  scope: rg
}

module appsEnv './shared/apps-env.bicep' = {
  name: 'apps-env'
  params: {
    name: '${abbrs.appManagedEnvironments}${resourceToken}'
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    logAnalyticsWorkspaceName: monitoring.outputs.logAnalyticsWorkspaceName
  }
  scope: rg
}

module backend './app/backend.bicep' = {
  name: 'backend'
  params: {
    name: 'backend'
    location: location
    tags: tags
    identityName: '${abbrs.managedIdentityUserAssignedIdentities}backend-${resourceToken}'
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    containerAppsEnvironmentName: appsEnv.outputs.name
    containerRegistryName: registry.outputs.name
    exists: srcExists
    appDefinition: srcDefinition
    userPrincipalId: principalId
    customSubDomainName: '${prefix}-${resourceToken}'
    cosmosdbName: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    aiSearchName: '${abbrs.searchSearchServices}${resourceToken}'
  }
  scope: rg
}

// Add frontend deployment module
module frontend './app/frontend.bicep' = {
  name: 'frontend'
  params: {
    name: '${abbrs.webStaticSites}${resourceToken}'
    location: 'westeurope'
    tags: tags
    repositoryUrl: srcDefinition.repositoryUrl
    branch: srcDefinition.branch
    appArtifactLocation: srcDefinition.frontendArtifactLocation
  }
  scope: rg
}

output AZURE_CONTAINER_REGISTRY_ENDPOINT string = registry.outputs.loginServer
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.name
output AZURE_KEY_VAULT_ENDPOINT string = keyVault.outputs.endpoint
output AZURE_OPENAI_ENDPOINT string = backend.outputs.azure_endpoint
output POOL_MANAGEMENT_ENDPOINT string = backend.outputs.pool_endpoint
output SERVICE_BACKEND_URI string = backend.outputs.uri
output STATIC_SITE_ENDPOINT string = frontend.outputs.staticSiteEndpoint
output COSMOS_DB_URI string = backend.outputs.cosmosdb_uri
output COSMOS_DB_DATABASE string = backend.outputs.cosmosdb_database
output CONTAINER_NAME string = backend.outputs.container_name
output AZURE_SEARCH_SERVICE_ENDPOINT string = backend.outputs.ai_search_endpoint
// output AZURE_SEARCH_ADMIN_KEY string = backend.outputs.ai_search_admin_key


