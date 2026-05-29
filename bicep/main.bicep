@description('Context Cache account name. 3-24 chars: lowercase letters, digits, hyphens; must start/end with letter or digit.')
@minLength(3)
@maxLength(24)
param accountName string = 'cc${uniqueString(resourceGroup().id)}'

@description('Container name. 3-63 chars: lowercase letters, digits, hyphens; must start/end with letter or digit.')
@minLength(3)
@maxLength(63)
param containerName string = 'default-container'

@description('Region for the Context Cache resources. Only swedencentral is currently supported.')
@allowed([
  'swedencentral'
])
param location string = 'swedencentral'

@description('Account kind for the Context Cache account.')
@allowed([
  'Regional'
  'DataZone'
  'Global'
])
param accountKind string = 'Regional'

@description('Model name to associate with the cache container. Must match an Azure OpenAI deployment underlying model.')
param modelName string = 'gpt-4'

@description('Model provider. OpenAI is currently the only supported value.')
@allowed([
  'OpenAI'
])
param provider string = 'OpenAI'

@description('Container cache entry time-to-live, in days.')
@minValue(1)
@maxValue(30)
param timeToLiveDays int = 7

@description('Optional. Name of an existing Azure OpenAI account in this RG to associate via outputs. Leave blank to skip.')
param existingAzureOpenAIAccountName string = ''

@description('Tags applied to created resources.')
param tagsByResource object = {
  environment: 'demo'
  sample: 'azure-context-cache-quickstart'
}

var associateAoai = !empty(existingAzureOpenAIAccountName)

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

output contextCacheAccountId string = account.id
output contextCacheAccountName string = account.name
output containerId string = container.id
output containerName string = container.name
output modelName string = modelName
output associatedAzureOpenAIAccountId string = associateAoai ? existingAoai.id : ''
output associatedAzureOpenAIEndpoint string = associateAoai ? existingAoai.properties.endpoint : ''
output nextSteps string = 'Context Cache container ready. Use container resource id with your Azure OpenAI client: ${container.id}'
