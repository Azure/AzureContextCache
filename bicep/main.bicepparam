using './main.bicep'

param accountName = 'my-context-cache-account'
param containerName = 'my-context-cache-container'
param location = 'swedencentral'
param accountKind = 'Regional'
param modelName = 'gpt-4'
param provider = 'OpenAI'
param timeToLiveDays = 7
param existingAzureOpenAIAccountName = ''
