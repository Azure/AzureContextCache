using './main.bicep'

param accountName = 'my-context-cache-account'
param containerName = 'my-context-cache-container'
param location = 'centralus'
param accountKind = 'Regional'
param modelName = 'gpt-5.4'
param provider = 'OpenAI'
param timeToLiveDays = 7

// Optional: link to an existing AOAI account in the same RG and region.
param existingAzureOpenAIAccountName = ''
param createOrUpdateAoaiDeployment = false
param aoaiDeploymentName = 'context-cache-deployment'
param aoaiModelFormat = 'OpenAI'
param aoaiModelName = 'gpt-5.4'
param aoaiModelVersion = '2026-03-05-contextcache'
param aoaiSkuName = 'Standard'
param aoaiSkuCapacity = 100
