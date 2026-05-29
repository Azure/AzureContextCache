@description('Context Cache account name. 3-24 chars: lowercase letters, digits, hyphens; must start/end with letter or digit.')
@minLength(3)
@maxLength(24)
param accountName string = 'cc${uniqueString(resourceGroup().id)}'

@description('Context Cache container name. 3-63 chars.')
@minLength(3)
@maxLength(63)
param containerName string = 'default-container'

@description('Region for the Context Cache resources. centralus is the launch region; swedencentral is also supported.')
@allowed([
  'centralus'
  'swedencentral'
])
param location string = 'centralus'

@description('Account kind for the Context Cache account.')
@allowed([
  'Regional'
  'DataZone'
  'Global'
])
param accountKind string = 'Regional'

@description('Model name to bind to the cache container (e.g. gpt-5.4, gpt-4o).')
param modelName string = 'gpt-5.4'

@description('Model provider. OpenAI is currently the only supported value.')
@allowed([
  'OpenAI'
])
param provider string = 'OpenAI'

@description('Container cache entry time-to-live, in days.')
@minValue(1)
@maxValue(30)
param timeToLiveDays int = 7

@description('Optional. Name of an existing Azure OpenAI account in this RG to associate. Must be in the same region as the cache container.')
param existingAzureOpenAIAccountName string = ''

@description('If true and existingAzureOpenAIAccountName is set, creates/updates an AOAI deployment linked to the new container.')
param createOrUpdateAoaiDeployment bool = false

@description('Name of the AOAI deployment to create/update.')
param aoaiDeploymentName string = 'context-cache-deployment'

@description('AOAI deployment model.format.')
param aoaiModelFormat string = 'OpenAI'

@description('AOAI deployment model.name. Should match modelName.')
param aoaiModelName string = 'gpt-5.4'

@description('AOAI deployment model.version. Must be a context-cache-capable version.')
param aoaiModelVersion string = '2026-03-05-contextcache'

@description('AOAI deployment SKU name.')
param aoaiSkuName string = 'Standard'

@description('AOAI deployment SKU capacity (TPM units).')
param aoaiSkuCapacity int = 100

@description('Tags applied to created resources.')
param tagsByResource object = {
  environment: 'demo'
  sample: 'azure-context-cache-quickstart'
}

var associateAoai = !empty(existingAzureOpenAIAccountName)
var deployAoaiDeployment = associateAoai && createOrUpdateAoaiDeployment

resource account 'Microsoft.AzureContextCache/accounts@2026-01-01-preview' = {
  name: accountName
  location: location
  tags: tagsByResource
  properties: {
    accountKind: accountKind
    description: 'Context Cache account provisioned via azure-context-cache-quickstart'
  }
}

resource container 'Microsoft.AzureContextCache/accounts/containers@2026-01-01-preview' = {
  parent: account
  name: containerName
  properties: {
    description: 'Prompt cache container for ${modelName}'
    modelName: modelName
    provider: provider
    timeToLive: timeToLiveDays
  }
}

resource existingAoai 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (associateAoai) {
  name: existingAzureOpenAIAccountName
}

resource aoaiDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-03-15-preview' = if (deployAoaiDeployment) {
  parent: existingAoai
  name: aoaiDeploymentName
  sku: {
    name: aoaiSkuName
    capacity: aoaiSkuCapacity
  }
  properties: {
    model: {
      format: aoaiModelFormat
      name: aoaiModelName
      version: aoaiModelVersion
    }
    contextCacheContainerId: container.id
  }
}

output contextCacheAccountId string = account.id
output contextCacheAccountName string = account.name
output containerId string = container.id
output containerName string = container.name
output modelName string = modelName
output associatedAzureOpenAIAccountId string = associateAoai ? existingAoai.id : ''
output associatedAzureOpenAIEndpoint string = associateAoai ? existingAoai.properties.endpoint : ''
output aoaiDeploymentId string = deployAoaiDeployment ? aoaiDeployment.id : ''
output aoaiDeploymentName string = deployAoaiDeployment ? aoaiDeploymentName : ''
output nextSteps string = deployAoaiDeployment ? 'AOAI deployment ${aoaiDeploymentName} linked to container ${container.id}.' : 'To link an AOAI deployment, PUT properties.contextCacheContainerId = ${container.id} on a Microsoft.CognitiveServices/accounts/deployments resource (api-version 2026-03-15-preview).'
