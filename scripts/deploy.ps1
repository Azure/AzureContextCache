#requires -Version 7.0
<#
.SYNOPSIS
    Deploys the Azure Context Cache quickstart sample to a resource group.

.PARAMETER ResourceGroup
    Target resource group. Created if it does not exist (in -Location).

.PARAMETER Location
    Region for the resource group. The Context Cache resources themselves are pinned to swedencentral.

.PARAMETER AccountName
    Context Cache account name (3-24 chars, lowercase letters/digits/hyphens).

.PARAMETER ContainerName
    Context Cache container name (3-63 chars, lowercase letters/digits/hyphens).

.PARAMETER ModelName
    Model name to associate with the container (e.g., gpt-4, gpt-4o).

.PARAMETER ExistingAzureOpenAIAccountName
    Optional. Name of an existing Azure OpenAI account in the same RG to surface via outputs.

.PARAMETER UseBicep
    Use bicep/main.bicep instead of azuredeploy.json.

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-cc-demo -AccountName mycache01 -ContainerName gpt4-cache -ModelName gpt-4

.EXAMPLE
    ./deploy.ps1 -ResourceGroup rg-cc-demo -ExistingAzureOpenAIAccountName my-aoai -UseBicep
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$ResourceGroup,
    [string]$Location = 'swedencentral',
    [string]$AccountName,
    [string]$ContainerName = 'default-container',
    [string]$ModelName = 'gpt-4',
    [string]$ExistingAzureOpenAIAccountName = '',
    [switch]$UseBicep
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Ensure RG exists
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
    "containerName=$ContainerName",
    "modelName=$ModelName",
    "existingAzureOpenAIAccountName=$ExistingAzureOpenAIAccountName"
)
if ($AccountName) { $cliParams += "accountName=$AccountName" }

& az @cliParams
