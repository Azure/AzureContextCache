#requires -Version 7.0
<#
.SYNOPSIS
    Registers the Microsoft.Storage resource provider.

.DESCRIPTION
    Run this once per subscription before deploying any azure-context-cache-quickstart template.

.PARAMETER SubscriptionId
    Target Azure subscription ID. Optional; the currently selected az subscription is used if omitted.

.EXAMPLE
    ./register-providers.ps1 -SubscriptionId 00000000-0000-0000-0000-000000000000
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId
)

$ErrorActionPreference = 'Stop'

if ($SubscriptionId) {
    Write-Host "Setting subscription to $SubscriptionId" -ForegroundColor Cyan
    az account set --subscription $SubscriptionId | Out-Null
}

Write-Host "Registering resource provider Microsoft.Storage..." -ForegroundColor Cyan
az provider register --namespace Microsoft.Storage | Out-Null

Write-Host "Registering preview feature Microsoft.CognitiveServices/OpenAI.ContextCacheAllowed..." -ForegroundColor Cyan
az feature register --namespace Microsoft.CognitiveServices --name OpenAI.ContextCacheAllowed | Out-Null

Write-Host "Ensuring Microsoft.CognitiveServices provider is registered..." -ForegroundColor Cyan
az provider register --namespace Microsoft.CognitiveServices | Out-Null

Write-Host ""
Write-Host "Current registration status:" -ForegroundColor Yellow
$providerState   = az provider show --namespace Microsoft.Storage --query registrationState -o tsv
$aoaiFeatState   = az feature show --namespace Microsoft.CognitiveServices --name OpenAI.ContextCacheAllowed --query properties.state -o tsv
$csProviderState = az provider show --namespace Microsoft.CognitiveServices --query registrationState -o tsv

Write-Host ("  Provider Microsoft.Storage                 : {0}" -f $providerState)
Write-Host ("  Provider Microsoft.CognitiveServices       : {0}" -f $csProviderState)
Write-Host ("  Feature  OpenAI.ContextCacheAllowed         : {0}" -f $aoaiFeatState)

$allGood = ($providerState -eq 'Registered') -and ($csProviderState -eq 'Registered') -and ($aoaiFeatState -eq 'Registered')

if (-not $allGood) {
    Write-Host ""
    Write-Host "Registration is asynchronous. Re-run this script in a few minutes if any state is still 'Registering'." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "All prerequisites registered. You can now deploy azuredeploy.json or bicep/main.bicep." -ForegroundColor Green
}
