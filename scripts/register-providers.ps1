#requires -Version 7.0
<#
.SYNOPSIS
    Registers the Microsoft.AzureContextCache resource provider and the EnablePreview feature flag.

.DESCRIPTION
    Run this once per subscription before deploying any azure-context-cache-quickstart template.
    The EnablePreview feature is gated. After registering, email azurecontextcacherp@microsoft.com
    to request approval if your subscription is not yet allow-listed.

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

Write-Host "Registering resource provider Microsoft.AzureContextCache..." -ForegroundColor Cyan
az provider register --namespace Microsoft.AzureContextCache | Out-Null

Write-Host "Registering preview feature Microsoft.AzureContextCache/EnablePreview..." -ForegroundColor Cyan
az feature register --namespace Microsoft.AzureContextCache --name EnablePreview | Out-Null

Write-Host ""
Write-Host "Current registration status:" -ForegroundColor Yellow
$providerState = az provider show --namespace Microsoft.AzureContextCache --query registrationState -o tsv
$featureState  = az feature show --namespace Microsoft.AzureContextCache --name EnablePreview --query properties.state -o tsv

Write-Host ("  Provider Microsoft.AzureContextCache : {0}" -f $providerState)
Write-Host ("  Feature  EnablePreview               : {0}" -f $featureState)

if ($providerState -ne 'Registered' -or $featureState -ne 'Registered') {
    Write-Host ""
    Write-Host "Registration is asynchronous. Re-run this script in a few minutes if state is still 'Registering'." -ForegroundColor Yellow
    Write-Host "If the feature stays 'Pending', email azurecontextcacherp@microsoft.com for approval." -ForegroundColor Yellow
}
else {
    Write-Host ""
    Write-Host "All prerequisites registered. You can now deploy azuredeploy.json or bicep/main.bicep." -ForegroundColor Green
}
