// ============================================================================
// resources.bicep — All resources for Customer 360 Semantic Search
//
// Creates: Cosmos DB (NoSQL, Entra-only auth, vector search),
//          Azure OpenAI (ada-002), ACR, Container Apps Env, Container App
// ============================================================================

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources')
param appName string

@description('Azure region')
param location string

@description('Object ID of the current signed-in user for Cosmos RBAC')
param currentUserObjectId string

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// Variables
// ============================================================================

var uniqueSuffix = uniqueString(resourceGroup().id, appName)
var cosmosAccountName = '${appName}-cosmos-${uniqueSuffix}'
var openAiAccountName = '${appName}-openai-${uniqueSuffix}'
var containerRegistryName = replace('${appName}acr${uniqueSuffix}', '-', '')
var containerAppEnvName = '${appName}-env-${uniqueSuffix}'
var containerAppName = '${appName}-app-${uniqueSuffix}'

var cosmosDatabase = 'Customer360DB'
var cosmosContainer = 'EnrichedCustomers'
var openAiEmbeddingModel = 'text-embedding-ada-002'
var openAiApiVersion = '2024-06-01'
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// ============================================================================
// Cosmos DB Account — NoSQL, Entra-only auth (keys disabled)
// ============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    capabilities: [
      {
        name: 'EnableNoSQLVectorSearch'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
  }
}

// ============================================================================
// Cosmos DB Database
// ============================================================================

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: cosmosDatabase
  properties: {
    resource: {
      id: cosmosDatabase
    }
  }
}

// ============================================================================
// Cosmos DB Container — with vector embedding + indexing policies
// ============================================================================

resource cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: cosmosDb
  name: cosmosContainer
  properties: {
    resource: {
      id: cosmosContainer
      partitionKey: {
        paths: ['/customer_id']
        kind: 'Hash'
        version: 2
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        automatic: true
        includedPaths: [
          { path: '/*' }
        ]
        excludedPaths: [
          { path: '/embedding/*' }
          { path: '/"_etag"/?' }
        ]
        vectorIndexes: [
          {
            path: '/embedding'
            type: 'quantizedFlat'
          }
        ]
      }
      vectorEmbeddingPolicy: {
        vectorEmbeddings: [
          {
            path: '/embedding'
            dataType: 'float32'
            distanceFunction: 'cosine'
            dimensions: 1536
          }
        ]
      }
    }
    options: {
      autoscaleSettings: {
        maxThroughput: 5000
      }
    }
  }
}

// ============================================================================
// Cosmos DB SQL Role Assignment — Data Contributor for current user
// ============================================================================

resource cosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(currentUserObjectId, cosmosAccount.id, cosmosDataContributorRoleId)
  properties: {
    principalId: currentUserObjectId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    scope: cosmosAccount.id
  }
}

// ============================================================================
// Azure OpenAI Account
// ============================================================================

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openAiAccountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: openAiAccountName
    publicNetworkAccess: 'Enabled'
  }
}

// ============================================================================
// Azure OpenAI Embedding Model Deployment (ada-002)
// ============================================================================

resource openAiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAiAccount
  name: 'embeddings'
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: openAiEmbeddingModel
      version: '2'
    }
  }
}

// ============================================================================
// Container Registry
// ============================================================================

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: containerRegistryName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ============================================================================
// Container Apps Environment
// ============================================================================

resource containerAppEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: containerAppEnvName
  location: location
  tags: tags
  properties: {}
}

// ============================================================================
// Container App
// ============================================================================

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  tags: union(tags, {
    'azd-service-name': 'webapp'
  })
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8000
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          username: containerRegistry.listCredentials().username
          passwordSecretRef: 'acr-password'
        }
      ]
      secrets: [
        {
          name: 'acr-password'
          value: containerRegistry.listCredentials().passwords[0].value
        }
        {
          name: 'azure-openai-key'
          value: openAiAccount.listKeys().key1
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'webapp'
          image: 'mcr.microsoft.com/k8se/quickstart:latest'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'COSMOS_ENDPOINT'
              value: cosmosAccount.properties.documentEndpoint
            }
            {
              name: 'COSMOS_DATABASE'
              value: cosmosDatabase
            }
            {
              name: 'COSMOS_CONTAINER'
              value: cosmosContainer
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: openAiAccount.properties.endpoint
            }
            {
              name: 'AZURE_OPENAI_KEY'
              secretRef: 'azure-openai-key'
            }
            {
              name: 'OPENAI_EMBEDDING_MODEL'
              value: 'embeddings'
            }
            {
              name: 'OPENAI_API_VERSION'
              value: openAiApiVersion
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
        rules: [
          {
            name: 'http-rule'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

// ============================================================================
// Cosmos DB SQL Role Assignment — Data Contributor for Container App identity
// ============================================================================

resource cosmosRoleAssignmentApp 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(containerApp.id, cosmosAccount.id, cosmosDataContributorRoleId)
  properties: {
    principalId: containerApp.identity.principalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    scope: cosmosAccount.id
  }
}

// ============================================================================
// Outputs
// ============================================================================

output cosmosEndpoint string = cosmosAccount.properties.documentEndpoint
output cosmosDatabase string = cosmosDatabase
output cosmosContainer string = cosmosContainer
output azureOpenAiEndpoint string = openAiAccount.properties.endpoint
output azureOpenAiKey string = openAiAccount.listKeys().key1
output openAiEmbeddingModel string = 'embeddings'
output openAiApiVersion string = openAiApiVersion
output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output serviceWebappImageName string = '${containerRegistry.properties.loginServer}/${appName}:latest'
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
