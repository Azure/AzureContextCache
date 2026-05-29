@description('Short prefix used to name the cache resources. 3-12 lowercase letters/digits, or leave empty to auto-generate.')
@maxLength(12)
param namePrefix string = ''

@description('OPTIONAL. Name of an existing Azure OpenAI account in this resource group to attach the cache-linked deployment to. Leave empty to create a new AOAI account (requires S0 account quota).')
param existingAoaiAccountName string = ''

@description('OPTIONAL. AAD object ID to grant "Cognitive Services OpenAI User" role on the AOAI account. Leave empty to auto-detect the deploying user.')
param principalId string = ''

@description('Principal type for the role assignment. Use ServicePrincipal for a managed identity or service principal.')
@allowed([ 'User', 'ServicePrincipal', 'Group' ])
param principalType string = 'User'

var effectiveNamePrefix = empty(namePrefix) ? 'cc${substring(uniqueString(resourceGroup().id), 0, 10)}' : namePrefix
var createAoai          = empty(existingAoaiAccountName)
var location            = resourceGroup().location
var aoaiAccountName     = createAoai ? '${effectiveNamePrefix}-aoai' : existingAoaiAccountName
var cacheAccountName    = '${effectiveNamePrefix}-cache'
var cacheContainerName  = 'default-container'
var aoaiDeploymentName  = 'context-cache-deployment'
var modelName           = 'gpt-5.4'
var modelVersion        = '2026-03-05-contextcache'
var effectivePrincipalId = empty(principalId) ? deployer().objectId : principalId
var assignRole          = createAoai && !empty(effectivePrincipalId)
var openAiUserRoleId    = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var tags = {
  sample: 'azure-context-cache-quickstart'
  environment: 'demo'
}

resource aoaiNew 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (createAoai) {
  name: aoaiAccountName
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    customSubDomainName: aoaiAccountName
    publicNetworkAccess: 'Enabled'
  }
}

resource aoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aoaiAccountName
}

resource cacheAccount 'Microsoft.AzureContextCache/accounts@2026-01-01-preview' = {
  name: cacheAccountName
  location: location
  tags: tags
  properties: {
    accountKind: 'Regional'
    description: 'Context Cache account (azure-context-cache-quickstart)'
  }
}

resource cacheContainer 'Microsoft.AzureContextCache/accounts/containers@2026-01-01-preview' = {
  parent: cacheAccount
  name: cacheContainerName
  properties: {
    description: 'Prompt cache container for ${modelName}'
    modelName: modelName
    provider: 'OpenAI'
    timeToLive: 7
  }
}

resource aoaiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-03-15-preview' = {
  parent: aoai
  name: aoaiDeploymentName
  dependsOn: [
    aoaiNew
  ]
  sku: {
    name: 'Standard'
    capacity: 100
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    contextCacheContainerId: cacheContainer.id
  }
}

resource openAiUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (assignRole) {
  name: guid(aoai.id, effectivePrincipalId, openAiUserRoleId)
  scope: aoai
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', openAiUserRoleId)
    principalId: effectivePrincipalId
    principalType: principalType
  }
  dependsOn: [
    aoaiNew
  ]
}

output azureOpenAIAccountName string  = aoaiAccountName
output azureOpenAIEndpoint string     = createAoai ? aoaiNew.properties.endpoint : aoai.properties.endpoint
output aoaiDeploymentName string      = aoaiDeployment.name
output contextCacheAccountName string = cacheAccount.name
output contextCacheContainerId string = cacheContainer.id
output modelName string               = modelName
output modelVersion string            = modelVersion
output openAIUserPrincipalId string   = assignRole ? effectivePrincipalId : ''
