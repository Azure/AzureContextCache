<#
.SYNOPSIS
    Clean up resources created by a single azure-context-cache-quickstart deployment.

.DESCRIPTION
    Deletes (in dependency-safe order):
      1. The AOAI model deployment (default name: context-cache-deployment) on the
         specified AOAI account.
      2. The Context Cache container, then the Context Cache account.
      3. OPTIONAL: the AOAI account itself (only if -DeleteAoaiAccount is passed --
         skip this when you attached the deployment to a pre-existing AOAI account
         that you want to keep).
      4. OPTIONAL: the deployment record itself.

    You can either:
      * Pass the names explicitly (-CacheAccountName / -AoaiAccountName / -AoaiDeploymentName), OR
      * Pass -DeploymentName and the names will be read from that ARM deployment's outputs.

.EXAMPLE
    # Clean up using outputs from a named ARM deployment
    ./cleanup.ps1 -ResourceGroup maperric-RG-3 -DeploymentName cc-e2e-test2

.EXAMPLE
    # Clean up by explicit names (matches the values from the portal Outputs blade)
    ./cleanup.ps1 -ResourceGroup maperric-RG-3 `
                  -AoaiAccountName maperric `
                  -AoaiDeploymentName context-cache-deployment `
                  -CacheAccountName mycontext-cache

.EXAMPLE
    # Also remove the AOAI account (only safe if the template created it)
    ./cleanup.ps1 -ResourceGroup myrg -DeploymentName mydep -DeleteAoaiAccount
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [string] $ResourceGroup,

    [string] $SubscriptionId,

    [string] $DeploymentName,

    [string] $AoaiAccountName,
    [string] $AoaiDeploymentName = 'context-cache-deployment',
    [string] $CacheAccountName,
    [string] $CacheContainerName = 'default-container',

    [switch] $DeleteAoaiAccount,
    [switch] $DeleteDeploymentRecord
)

$ErrorActionPreference = 'Stop'

function Invoke-Az {
    param([Parameter(Mandatory)][string[]] $Args)
    Write-Host "  az $($Args -join ' ')" -ForegroundColor DarkGray
    & az @Args
    if ($LASTEXITCODE -ne 0) { throw "az exited with $LASTEXITCODE" }
}

if ($SubscriptionId) {
    Invoke-Az @('account', 'set', '--subscription', $SubscriptionId)
}
$SubscriptionId = az account show --query id -o tsv

# ---------- Resolve names from deployment outputs (if requested) ----------
if ($DeploymentName) {
    Write-Host "Reading outputs from deployment '$DeploymentName'..." -ForegroundColor Cyan
    $outJson = az deployment group show `
        --resource-group $ResourceGroup `
        --name $DeploymentName `
        --query properties.outputs -o json
    if ($LASTEXITCODE -ne 0 -or -not $outJson) {
        throw "Failed to read deployment '$DeploymentName' in RG '$ResourceGroup'."
    }
    $outputs = $outJson | ConvertFrom-Json
    if (-not $AoaiAccountName -and $outputs.azureOpenAIAccountName) {
        $AoaiAccountName = $outputs.azureOpenAIAccountName.value
    }
    if ($outputs.aoaiDeploymentName) {
        $AoaiDeploymentName = $outputs.aoaiDeploymentName.value
    }
    if (-not $CacheAccountName -and $outputs.contextCacheAccountName) {
        $CacheAccountName = $outputs.contextCacheAccountName.value
    }
}

if (-not $AoaiAccountName)  { throw "AoaiAccountName is required (pass -AoaiAccountName or -DeploymentName)." }
if (-not $CacheAccountName) { throw "CacheAccountName is required (pass -CacheAccountName or -DeploymentName)." }

Write-Host ""
Write-Host "Cleanup plan:" -ForegroundColor Yellow
Write-Host "  Subscription      : $SubscriptionId"
Write-Host "  Resource group    : $ResourceGroup"
Write-Host "  AOAI account      : $AoaiAccountName   (delete entire account: $DeleteAoaiAccount)"
Write-Host "  AOAI deployment   : $AoaiDeploymentName"
Write-Host "  Cache account     : $CacheAccountName"
Write-Host "  Cache container   : $CacheContainerName"
if ($DeploymentName) {
    Write-Host "  ARM deployment    : $DeploymentName (delete record: $DeleteDeploymentRecord)"
}
Write-Host ""

if (-not $PSCmdlet.ShouldProcess("$ResourceGroup/$CacheAccountName + $AoaiAccountName/$AoaiDeploymentName", 'Delete')) {
    return
}

$cacheContainerId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/contextCaches/$CacheAccountName/contextCacheContainers/$CacheContainerName"
$cacheAccountId   = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Storage/contextCaches/$CacheAccountName"
$aoaiDeploymentId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$AoaiAccountName/deployments/$AoaiDeploymentName"
$aoaiAccountId    = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.CognitiveServices/accounts/$AoaiAccountName"

# 1. AOAI deployment (must go before deleting the cache container it points at).
Write-Host "[1/4] Deleting AOAI model deployment..." -ForegroundColor Cyan
az resource delete --ids $aoaiDeploymentId --api-version 2026-03-15-preview 2>&1 | Out-Host

# 2. Cache container, then cache account.
Write-Host "[2/4] Deleting context cache container..." -ForegroundColor Cyan
az resource delete --ids $cacheContainerId --api-version 2026-01-01-preview 2>&1 | Out-Host

Write-Host "[3/4] Deleting context cache account..." -ForegroundColor Cyan
az resource delete --ids $cacheAccountId --api-version 2026-01-01-preview 2>&1 | Out-Host

# 3. Optionally delete the AOAI account.
if ($DeleteAoaiAccount) {
    Write-Host "[4/4] Deleting AOAI account..." -ForegroundColor Cyan
    az resource delete --ids $aoaiAccountId --api-version 2024-10-01 2>&1 | Out-Host
} else {
    Write-Host "[4/4] Skipping AOAI account deletion (pass -DeleteAoaiAccount to remove it)." -ForegroundColor DarkGray
}

# 4. Optionally remove the ARM deployment history entry.
if ($DeploymentName -and $DeleteDeploymentRecord) {
    Write-Host "Removing ARM deployment record '$DeploymentName'..." -ForegroundColor Cyan
    az deployment group delete --resource-group $ResourceGroup --name $DeploymentName 2>&1 | Out-Host
}

Write-Host ""
Write-Host "Cleanup complete." -ForegroundColor Green
