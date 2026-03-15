targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources')
param appName string = 'customer360'

@description('Azure region for all resources')
param location string

@description('Resource group name')
param resourceGroupName string = 'rg-${appName}'

@description('Name of the azd environment')
param environmentName string

@description('Object ID of the current signed-in user (set by pre-provision hook)')
param currentUserObjectId string

@description('Fabric Lakehouse SQL Analytics Endpoint (optional, for benchmark page)')
param fabricSqlEndpoint string = ''

@description('Fabric Lakehouse name (optional, for benchmark page)')
param fabricLakehouse string = ''

var tags = {
  'azd-env-name': environmentName
}

// ============================================================================
// Resource Group
// ============================================================================

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: tags
}

// ============================================================================
// Module — all resources deployed into the new resource group
// ============================================================================

module resources './resources.bicep' = {
  name: 'resources'
  scope: rg
  params: {
    appName: appName
    location: location
    currentUserObjectId: currentUserObjectId
    fabricSqlEndpoint: fabricSqlEndpoint
    fabricLakehouse: fabricLakehouse
    tags: tags
  }
}

// ============================================================================
// Outputs (forwarded from module)
// ============================================================================

output COSMOS_ENDPOINT string = resources.outputs.cosmosEndpoint
output COSMOS_DATABASE string = resources.outputs.cosmosDatabase
output COSMOS_CONTAINER string = resources.outputs.cosmosContainer
output AZURE_OPENAI_ENDPOINT string = resources.outputs.azureOpenAiEndpoint
output AZURE_OPENAI_KEY string = resources.outputs.azureOpenAiKey
output OPENAI_EMBEDDING_MODEL string = resources.outputs.openAiEmbeddingModel
output OPENAI_API_VERSION string = resources.outputs.openAiApiVersion
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = resources.outputs.containerRegistryLoginServer
output SERVICE_WEBAPP_IMAGE_NAME string = resources.outputs.serviceWebappImageName
output containerAppUrl string = resources.outputs.containerAppUrl
