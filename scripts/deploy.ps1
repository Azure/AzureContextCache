#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the Azure Context Cache quickstart sample to a resource group.

.PARAMETER ResourceGroup
    Target resource group. Created if it does not exist (in -Location).

.PARAMETER Location
    Region for the resource group AND the Context Cache resources. Defaults to centralus (launch region).
    Also supported: swedencentral.

.PARAMETER AccountName
    Context Cache account name (3-24 chars, lowercase letters/digits/hyphens).

.PARAMETER ContainerName
    Context Cache container name (3-63 chars, lowercase letters/digits/hyphens).

.PARAMETER ModelName
    Model name to associate with the container (e.g., gpt-5.4, gpt-4o).

.PARAMETER ExistingAzureOpenAIAccountName
    Optional. Name of an existing Azure OpenAI account in the same RG. Must be in the same region.

.PARAMETER CreateOrUpdateAoaiDeployment
    If set with -ExistingAzureOpenAIAccountName, creates/updates an AOAI deployment with
    properties.contextCacheContainerId pointing at the new container.

.PARAMETER AoaiDeploymentName
.PARAMETER AoaiModelName
.PARAMETER AoaiModelVersion
.PARAMETER AoaiSkuName
.PARAMETER AoaiSkuCapacity

.PARAMETER UseBicep
    Use bicep/main.bicep instead of azuredeploy.json.

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-cc-demo

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-cc-demo `
        -ExistingAzureOpenAIAccountName prkum-usc `
        -CreateOrUpdateAoaiDeployment `
        -AoaiDeploymentName ydou-context-cache
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ResourceGroup,
    [string]$Location = 'centralus',
    [string]$AccountName,
    [string]$ContainerName = 'default-container',
    [string]$ModelName = 'gpt-5.4',
    [string]$ExistingAzureOpenAIAccountName = '',
    [switch]$CreateOrUpdateAoaiDeployment,
    [string]$AoaiDeploymentName = 'context-cache-deployment',
    [string]$AoaiModelName = 'gpt-5.4',
    [string]$AoaiModelVersion = '2026-03-05-contextcache',
    [string]$AoaiSkuName = 'Standard',
    [int]$AoaiSkuCapacity = 100,
    [switch]$UseBicep
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

if (-not (az group show --name $ResourceGroup 2>$null)) {
    Write-Host "Creating resource group $ResourceGroup in $Location..." -ForegroundColor Cyan
    az group create --name $ResourceGroup --location $Location | Out-Null
}

$template = if ($UseBicep) { Join-Path $root 'bicep/main.bicep' } else { Join-Path $root 'azuredeploy.json' }
Write-Host "Deploying template: $template" -ForegroundColor Cyan

$cliParams = @(
    'deployment','group','create',
    '--resource-group', $ResourceGroup,
    '--template-file', $template,
    '--parameters',
    "location=$Location",
    "containerName=$ContainerName",
    "modelName=$ModelName",
    "existingAzureOpenAIAccountName=$ExistingAzureOpenAIAccountName",
    ("createOrUpdateAoaiDeployment={0}" -f ($CreateOrUpdateAoaiDeployment.IsPresent.ToString().ToLower())),
    "aoaiDeploymentName=$AoaiDeploymentName",
    "aoaiModelName=$AoaiModelName",
    "aoaiModelVersion=$AoaiModelVersion",
    "aoaiSkuName=$AoaiSkuName",
    "aoaiSkuCapacity=$AoaiSkuCapacity"
)
if ($AccountName) { $cliParams += "accountName=$AccountName" }

& az @cliParams
