<#
.SYNOPSIS
    All-in-one Azure Context Cache quickstart: validate prereqs → deploy → run the keyless demo.

.DESCRIPTION
    Single-script equivalent of the "Deploy to Azure" portal flow. Walks through:
      1. Login / subscription selection.
      2. Resource provider + preview-feature registration (Microsoft.Storage,
         Microsoft.CognitiveServices/OpenAI.ContextCacheAllowed).
         Auto-registers anything not yet 'Registered' and waits for it.
      3. Resource group create (if missing).
      4. ARM template deploy (azure-context-cache-quickstart/azuredeploy.json) - auto-grants
         "Cognitive Services OpenAI User" to the deploying user when the template creates the AOAI account.
      5. Demo run via AAD (DefaultAzureCredential - works for `az login`, system MI, UAMI),
         printing per-call cached_tokens + latency so you can see the cache hit shape.

    Any param not supplied is prompted for interactively.

.PARAMETER SubscriptionId
    Azure subscription ID. If omitted, the current `az` subscription is used (or you are asked to pick one).

.PARAMETER ResourceGroup
    Target resource group. Created in -Location if it doesn't exist.

.PARAMETER Location
    Azure region for the RG + resources. Must be one of: swedencentral, eastus2, centralus.

.PARAMETER NamePrefix
    Short prefix (3-12 lowercase letters/digits) used for resource names. Leave empty to auto-generate.

.PARAMETER ExistingAoaiAccountName
    OPTIONAL. Name of an existing AOAI account in -ResourceGroup to attach the cache-linked deployment to.
    Leave empty to create a brand-new AOAI account (requires S0 account quota).

.PARAMETER Runs
    Number of demo iterations (default 6 - first cold, rest warm).

.PARAMETER SkipDemo
    Skip the demo step after deployment.

.PARAMETER SkipPython
    Skip the auto venv + pip install step (assumes you already activated an env with the demo deps).

.PARAMETER SkipPrerequisiteRegistration
    Skip subscription-level provider and preview-feature checks. Use only after a subscription
    administrator has confirmed that all prerequisites are registered.

.EXAMPLE
    ./quickstart.ps1

    Fully interactive - prompts for everything, then deploys + runs the demo.

.EXAMPLE
    ./quickstart.ps1 -SubscriptionId 6a6fff00-... -ResourceGroup maperric-RG-3 -ExistingAoaiAccountName maperric

    Non-interactive: reuse an existing AOAI account, auto-generate prefix.
#>
[CmdletBinding()]
param(
    [string] $SubscriptionId,
    [string] $ResourceGroup,
    [ValidateSet('swedencentral', 'eastus2', 'centralus')]
    [string] $Location = 'centralus',
    [string] $NamePrefix,
    [string] $ExistingAoaiAccountName,
    [int]    $Runs = 6,
    [switch] $SkipDemo,
    [switch] $SkipPython,
    [switch] $SkipPrerequisiteRegistration
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$templatePath = Join-Path $repoRoot 'azuredeploy.json'
$demoDir    = Join-Path $repoRoot 'demo'

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Info([string]$msg) { Write-Host "    $msg" -ForegroundColor DarkGray }
function Write-Ok  ([string]$msg) { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "    [!]  $msg" -ForegroundColor Yellow }
function Read-NonEmpty([string]$prompt, [string]$default = '') {
    $hint = if ($default) { " [$default]" } else { '' }
    $val = Read-Host "$prompt$hint"
    if ([string]::IsNullOrWhiteSpace($val)) { return $default }
    return $val.Trim()
}

# ----- 0. az CLI sanity check -----
Write-Step "Checking Azure CLI"
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI (az) not found in PATH. Install from https://aka.ms/installazurecli and re-run."
}
$accountJson = az account show 2>$null
if (-not $accountJson) {
    Write-Info "Not logged in - running 'az login'..."
    az login --only-show-errors | Out-Null
    $accountJson = az account show
}
$currentAcct = $accountJson | ConvertFrom-Json
Write-Ok "Signed in as $($currentAcct.user.name)"

# ----- 1. Subscription -----
Write-Step "Selecting subscription"
if (-not $SubscriptionId) {
    Write-Info "Current subscription: $($currentAcct.name) ($($currentAcct.id))"
    $useCurrent = Read-NonEmpty "Use this subscription? (Y/n)" 'Y'
    if ($useCurrent -notmatch '^[Yy]') {
        Write-Host "  Available subscriptions:"
        az account list --query '[].{Name:name, Id:id}' -o table
        $SubscriptionId = Read-NonEmpty "Enter subscription ID"
    } else {
        $SubscriptionId = $currentAcct.id
    }
}
az account set --subscription $SubscriptionId | Out-Null
$currentAcct = az account show | ConvertFrom-Json
Write-Ok "Using subscription $($currentAcct.name) ($SubscriptionId)"

# ----- 2. Resource group + location -----
Write-Step "Resource group"
if (-not $ResourceGroup) {
    $ResourceGroup = Read-NonEmpty "Resource group name"
    if (-not $ResourceGroup) { throw "Resource group name is required." }
}
$rgInfo = az group show --name $ResourceGroup 2>$null | ConvertFrom-Json
if ($rgInfo) {
    $Location = $rgInfo.location
    Write-Ok "Using existing RG '$ResourceGroup' in $Location"
} else {
    Write-Info "RG '$ResourceGroup' does not exist - will create in '$Location'."
    if (-not $PSBoundParameters.ContainsKey('Location')) {
        $loc = Read-NonEmpty "Location (swedencentral|eastus2|centralus)" $Location
        if ($loc -notin 'swedencentral','eastus2','centralus') { throw "Location '$loc' not supported." }
        $Location = $loc
    }
    az group create --name $ResourceGroup --location $Location | Out-Null
    Write-Ok "Created RG '$ResourceGroup' in $Location"
}

# ----- 3. Optional existing AOAI -----
Write-Step "AOAI account"
if (-not $PSBoundParameters.ContainsKey('ExistingAoaiAccountName')) {
    $reuse = Read-NonEmpty "Attach to an EXISTING AOAI account? (y/N)" 'N'
    if ($reuse -match '^[Yy]') {
        Write-Host "  AOAI accounts in '$ResourceGroup':"
        az cognitiveservices account list -g $ResourceGroup --query '[?kind==`OpenAI`].{Name:name, Location:location}' -o table
        $ExistingAoaiAccountName = Read-NonEmpty "Existing AOAI account name (blank to create new)"
    }
}
if ($ExistingAoaiAccountName) {
    $aoaiCheck = az cognitiveservices account show -n $ExistingAoaiAccountName -g $ResourceGroup 2>$null | ConvertFrom-Json
    if (-not $aoaiCheck) { throw "AOAI account '$ExistingAoaiAccountName' not found in RG '$ResourceGroup'." }
    if ($aoaiCheck.location -ne $Location) {
        Write-Warn "AOAI account is in $($aoaiCheck.location), template will deploy other resources in $Location."
    }
    Write-Ok "Will reuse existing AOAI account '$ExistingAoaiAccountName'"
} else {
    Write-Ok "Template will create a NEW AOAI account (requires S0 account quota in $Location)."
}

# ----- 4. Name prefix -----
Write-Step "Name prefix"
if (-not $PSBoundParameters.ContainsKey('NamePrefix')) {
    $NamePrefix = Read-NonEmpty "Name prefix (3-12 lowercase letters/digits, blank = auto-generate)" ''
}
if ($NamePrefix -and ($NamePrefix -notmatch '^[a-z0-9]{3,12}$')) {
    throw "NamePrefix '$NamePrefix' invalid. Must be 3-12 lowercase letters/digits."
}

# ----- 5. Provider + feature registration -----
Write-Step "Validating RP + preview-feature registration"

if ($SkipPrerequisiteRegistration) {
    Write-Warn "Skipping subscription-level registration checks; assuming an administrator completed them."
} else {
    $checks = @(
        @{ Kind='provider'; Namespace='Microsoft.Storage'; Name=$null }
        @{ Kind='provider'; Namespace='Microsoft.CognitiveServices';  Name=$null }
        @{ Kind='feature';  Namespace='Microsoft.CognitiveServices';  Name='OpenAI.ContextCacheAllowed' }
    )

    function Get-RegState($c) {
        if ($c.Kind -eq 'provider') {
            return az provider show --namespace $c.Namespace --query registrationState -o tsv 2>$null
        }
        return az feature show --namespace $c.Namespace --name $c.Name --query properties.state -o tsv 2>$null
    }

    $toRegister = @()
    foreach ($c in $checks) {
        $state = Get-RegState $c
        $label = if ($c.Kind -eq 'provider') { "provider $($c.Namespace)" } else { "feature  $($c.Namespace)/$($c.Name)" }
        if ($state -eq 'Registered') {
            Write-Ok ("{0,-65} {1}" -f $label, $state)
        } else {
            Write-Warn ("{0,-65} {1}" -f $label, $(if ($state) { $state } else { 'NotRegistered' }))
            $toRegister += $c
        }
    }

    if ($toRegister.Count -gt 0) {
        Write-Info "Registering missing items..."
        foreach ($c in $toRegister) {
            if ($c.Kind -eq 'provider') {
                az provider register --namespace $c.Namespace | Out-Null
            } else {
                az feature register --namespace $c.Namespace --name $c.Name | Out-Null
            }
        }
        Write-Info "Waiting for all to reach 'Registered' (up to 10 min, refreshes every 20s)..."
        $deadline = (Get-Date).AddMinutes(10)
        do {
            Start-Sleep -Seconds 20
            $stillPending = @()
            foreach ($c in $toRegister) {
                $state = Get-RegState $c
                $label = if ($c.Kind -eq 'provider') { "provider $($c.Namespace)" } else { "feature  $($c.Namespace)/$($c.Name)" }
                if ($state -ne 'Registered') {
                    $stillPending += "$label = $state"
                }
            }
            if ($stillPending.Count -eq 0) { break }
            Write-Info ("[{0}] still pending: {1}" -f (Get-Date -Format HH:mm:ss), ($stillPending -join '; '))
        } while ((Get-Date) -lt $deadline)

        $finalPending = @()
        foreach ($c in $toRegister) {
            if ((Get-RegState $c) -ne 'Registered') { $finalPending += $c }
        }
        if ($finalPending.Count -gt 0) {
            Write-Warn "Some items did not reach 'Registered' in time. Gated preview features may require allow-listing - email azurecontextcacherp@microsoft.com."
            $cont = Read-NonEmpty "Continue with deployment anyway? (y/N)" 'N'
            if ($cont -notmatch '^[Yy]') { throw "Aborted due to incomplete registration." }
        } else {
            Write-Ok "All providers and features are Registered."
        }
    }
}

# ----- 6. ARM deployment -----
Write-Step "Deploying ARM template"
$deploymentName = "cc-quickstart-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$paramsArr = @()
if ($NamePrefix)              { $paramsArr += "namePrefix=$NamePrefix" }
if ($ExistingAoaiAccountName) { $paramsArr += "existingAoaiAccountName=$ExistingAoaiAccountName" }

$azArgs = @('deployment','group','create',
    '--resource-group', $ResourceGroup,
    '--name', $deploymentName,
    '--template-file', $templatePath,
    '--only-show-errors')
if ($paramsArr.Count -gt 0) { $azArgs += @('--parameters') + $paramsArr }

Write-Info "az $($azArgs -join ' ')"
$resultJson = & az @azArgs
if ($LASTEXITCODE -ne 0) { throw "Deployment failed (exit $LASTEXITCODE)." }
$result = $resultJson | ConvertFrom-Json
$outputs = $result.properties.outputs

$endpoint           = $outputs.azureOpenAIEndpoint.value
$aoaiDeploymentName = $outputs.aoaiDeploymentName.value
$aoaiAccountName    = $outputs.azureOpenAIAccountName.value
$cacheAccount       = $outputs.contextCacheAccountName.value

Write-Ok "Deployment '$deploymentName' Succeeded"
Write-Host ""
Write-Host "  AOAI account     : $aoaiAccountName"
Write-Host "  AOAI endpoint    : $endpoint"
Write-Host "  AOAI deployment  : $aoaiDeploymentName"
Write-Host "  Cache account    : $cacheAccount"

# ----- 7. Ensure the running identity has OpenAI User on the AOAI account (covers BYO-AOAI case) -----
if ($ExistingAoaiAccountName) {
    Write-Step "Granting 'Cognitive Services OpenAI User' to the current user on existing AOAI"
    $callerId = az ad signed-in-user show --query id -o tsv 2>$null
    if ($callerId) {
        $aoaiId = az cognitiveservices account show -n $aoaiAccountName -g $ResourceGroup --query id -o tsv
        $existing = az role assignment list --assignee $callerId --scope $aoaiId --include-inherited --role "Cognitive Services OpenAI User" --query "[].id" -o tsv 2>$null
        if (-not $existing) {
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $null = az role assignment create --assignee-object-id $callerId --assignee-principal-type User `
                    --role "Cognitive Services OpenAI User" --scope $aoaiId --only-show-errors 2>&1
                $rc = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $prevEAP
            }
            if ($rc -eq 0) {
                Write-Ok "Granted (waiting 30s for propagation)."
                Start-Sleep -Seconds 30
            } else {
                Write-Warn "Could not auto-grant role (need Owner/User Access Admin on the AOAI account). Demo --aad mode will fail with 401 unless you (or an owner) assigns 'Cognitive Services OpenAI User' to $callerId on $aoaiId."
            }
        } else {
            Write-Ok "Role already assigned."
        }
    }
}

# ----- 8. Demo -----
if ($SkipDemo) {
    Write-Step 'Skipping demo (-SkipDemo specified).'
    return
}
if (-not (Test-Path (Join-Path $demoDir 'code_reviewer_demo.py'))) {
    Write-Warn "Demo script not found at $demoDir - skipping."
    return
}

Write-Step "Running keyless demo (DefaultAzureCredential, $Runs iterations)"

$pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $pythonCommand) {
    $pythonCommand = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $pythonCommand) {
    Write-Warn "python3/python not in PATH; skipping demo. Install Python 3.10+ to run it."
    return
}
$demoPython = $pythonCommand.Source

Push-Location $demoDir
try {
    if (-not $SkipPython) {
        $venv = Join-Path $demoDir '.venv'
        if (-not (Test-Path $venv)) {
            Write-Info "Creating venv at .venv ..."
            & $demoPython -m venv $venv
        }
        $venvPythonRelativePath = if ($IsWindows) { 'Scripts/python.exe' } else { 'bin/python' }
        $demoPython = Join-Path $venv $venvPythonRelativePath
        if (-not (Test-Path $demoPython)) {
            throw "Virtual-environment Python not found at '$demoPython'. Remove '$venv' and re-run."
        }
        Write-Info "Installing demo requirements (quiet)..."
        & $demoPython -m pip install -q -r requirements.txt
    }

    $env:AOAI_ENDPOINT   = $endpoint
    $env:AOAI_DEPLOYMENT = $aoaiDeploymentName
    Remove-Item Env:AOAI_API_KEY -ErrorAction SilentlyContinue

    Write-Host ""
    & $demoPython code_reviewer_demo.py --aad --runs $Runs
    $demoExit = $LASTEXITCODE
} finally {
    Pop-Location
}

Write-Host ""
if ($demoExit -eq 0) {
    Write-Ok "Quickstart complete. The cache-hit% column above shows Azure Context Cache serving the warm calls."
} else {
    Write-Warn "Demo exited with code $demoExit. If you saw a 401, role propagation can take a minute - re-run the demo."
}
