# Azure Context Cache — Quickstart

A one-click sample for provisioning an **Azure Context Cache (Prompt Cache)** account + container in your subscription, and (optionally, in the same deployment) creating or updating an **Azure OpenAI deployment** that is linked to that container via `properties.contextCacheContainerId`.

> Azure Context Cache (resource provider `Microsoft.AzureContextCache`) is in **preview**. The launch region is **`centralus`**; `swedencentral` is also supported. The cache RP API version is **`2026-01-01-preview`**, and AOAI deployments use **`2026-03-15-preview`**.

---

## One-click deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](https://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fazuredeploy.json)

The Deploy-to-Azure button opens the Azure Portal **Custom deployment** blade pre-loaded with [`azuredeploy.json`](azuredeploy.json). Pick a subscription + resource group, fill in the parameters, and click **Create**.

> Default region: **`centralus`** (the launch region for this offering).

---

## What gets deployed

| Resource | Type | Always? | Notes |
|---|---|---|---|
| Context Cache account | `Microsoft.AzureContextCache/accounts` | Yes | `accountKind = Regional` by default |
| Cache container | `Microsoft.AzureContextCache/accounts/containers` | Yes | Bound to `modelName` + `provider = OpenAI` |
| AOAI deployment linked to the container | `Microsoft.CognitiveServices/accounts/deployments` | When `existingAzureOpenAIAccountName` is set **and** `createOrUpdateAoaiDeployment = true` | API `2026-03-15-preview`; sets `properties.contextCacheContainerId` |

---

## Prerequisites (one-time, per subscription)

These steps cannot be done from the Deploy-to-Azure button — run them once first.

### 1. Register the resource providers and preview features

```powershell
./scripts/register-providers.ps1 -SubscriptionId <your-sub-id>
```

Or manually:

```bash
# Context Cache RP + preview feature
az provider register --namespace Microsoft.AzureContextCache
az feature register  --namespace Microsoft.AzureContextCache --name EnablePreview

# Azure OpenAI: allow context-cache-linked deployments
az feature register  --namespace Microsoft.CognitiveServices --name OpenAI.ContextCacheAllowed
az provider register --namespace Microsoft.CognitiveServices
```

The `EnablePreview` feature is **gated**. After registering, email **azurecontextcacherp@microsoft.com** for approval if state stays `Pending`. Same applies to `OpenAI.ContextCacheAllowed` for AOAI side.

Verify:

```bash
az provider show --namespace Microsoft.AzureContextCache --query registrationState
az feature  show --namespace Microsoft.AzureContextCache --name EnablePreview --query properties.state
az feature  show --namespace Microsoft.CognitiveServices --name OpenAI.ContextCacheAllowed --query properties.state
# All three should print "Registered"
```

### 2. Have (or create) an Azure OpenAI account in the same region

To link a cache container to an AOAI deployment, you need an existing AOAI (Cognitive Services) account **in the same region as the cache container** (e.g. both in `centralus`). The caller needs `Microsoft.CognitiveServices/accounts/deployments/write` on that account.

If you do not have one yet, create a minimal account:

```bash
az cognitiveservices account create \
  --name my-aoai-cus \
  --resource-group <rg-name> \
  --kind OpenAI \
  --sku S0 \
  --location centralus \
  --yes
```

> **Bug-bash shortcut:** For internal testing you can reuse the pre-registered BugBash AOAI account `prkum-usc` in resource group `prkum` (subscription `6a6fff00-4464-4eab-a6b1-0b533c7202e0`, region Central US). Pass `existingAzureOpenAIAccountName=prkum-usc` and deploy this template into that RG.

Example reference resources used in the docs:

| Resource | Value |
|---|---|
| Azure OpenAI account | `/subscriptions/6a6fff00-4464-4eab-a6b1-0b533c7202e0/resourceGroups/prkum/providers/Microsoft.CognitiveServices/accounts/prkum-usc` |
| AOAI deployment name | `ydou-context-cache` |
| Context cache container | `/subscriptions/6a6fff00-4464-4eab-a6b1-0b533c7202e0/resourceGroups/ydou-usc/providers/Microsoft.AzureContextCache/accounts/ydoucontextcacheusc/containers/gpt54container` |
| AOAI deployment API version | `2026-03-15-preview` |
| Model | `gpt-5.4`, version `2026-03-05-contextcache` |

### 3. Grant the Cognitive Services RP `Reader` on your subscription

Until the built-in CSRP role definition rolls out globally, give the **Microsoft Cognitive Services** enterprise application (App ID `7d312290-28c8-473c-a0ed-8e53749b6d6d`) `Reader` on the subscription that hosts your Context Cache account.

Find its **Object ID** once (Portal → Entra ID → Enterprise applications → search the App ID → copy Object ID), then deploy [`prereqs/assign-reader-role.json`](prereqs/assign-reader-role.json) at subscription scope:

[![Deploy reader role](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fprereqs%2Fassign-reader-role.json)

CLI alternative:

```bash
az deployment sub create \
  --name assign-reader-role \
  --location centralus \
  --template-file ./prereqs/assign-reader-role.json \
  --parameters principalObjectId=<csrp-object-id>
```

---

## Parameters

### Context Cache
| Name | Default | Description |
|---|---|---|
| `accountName` | `cc<hash>` | 3-24 chars |
| `containerName` | `default-container` | 3-63 chars |
| `location` | `centralus` | `centralus` (launch) or `swedencentral` |
| `accountKind` | `Regional` | `Regional` \| `DataZone` \| `Global` |
| `modelName` | `gpt-5.4` | Must match the AOAI deployment's underlying model |
| `provider` | `OpenAI` | Only value supported today |
| `timeToLiveDays` | `7` | 1-30 |

### AOAI association (optional)
| Name | Default | Description |
|---|---|---|
| `existingAzureOpenAIAccountName` | *(empty)* | Existing AOAI account in this RG; **must be in the same region** as the cache |
| `createOrUpdateAoaiDeployment` | `false` | When true, creates/updates an AOAI deployment linked to the new container |
| `aoaiDeploymentName` | `context-cache-deployment` | Name of the AOAI deployment |
| `aoaiModelFormat` | `OpenAI` | |
| `aoaiModelName` | `gpt-5.4` | Should match `modelName` |
| `aoaiModelVersion` | `2026-03-05-contextcache` | Must be a context-cache-capable model version |
| `aoaiSkuName` | `Standard` | |
| `aoaiSkuCapacity` | `100` | TPM units |

---

## Deploy from the CLI

```powershell
# Just create the cache account + container (default: centralus)
./scripts/deploy.ps1 -ResourceGroup rg-cc-demo

# Also create/update an AOAI deployment that links to the new container
./scripts/deploy.ps1 -ResourceGroup prkum `
    -ExistingAzureOpenAIAccountName prkum-usc `
    -CreateOrUpdateAoaiDeployment `
    -AoaiDeploymentName ydou-context-cache `
    -AoaiModelName gpt-5.4 `
    -AoaiModelVersion 2026-03-05-contextcache

# Same, using Bicep
./scripts/deploy.ps1 -ResourceGroup prkum -UseBicep -ExistingAzureOpenAIAccountName prkum-usc -CreateOrUpdateAoaiDeployment
```

Equivalent raw `az` commands:

```bash
az deployment group create \
  --resource-group rg-cc-demo \
  --template-file ./azuredeploy.json \
  --parameters @azuredeploy.parameters.json

az deployment group create \
  --resource-group rg-cc-demo \
  --template-file ./bicep/main.bicep \
  --parameters ./bicep/main.bicepparam
```

---

## Linking AOAI to Context Cache (under the hood)

The template binds the AOAI deployment to the cache container by setting `properties.contextCacheContainerId` to the container's ARM resource id, using the `2026-03-15-preview` API version. The equivalent raw REST call is:

```http
PUT https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai>/deployments/<deploymentName>?api-version=2026-03-15-preview
Content-Type: application/json
Authorization: Bearer <token>

{
  "sku":  { "name": "Standard", "capacity": 100 },
  "properties": {
    "model": { "format": "OpenAI", "name": "gpt-5.4", "version": "2026-03-05-contextcache" },
    "contextCacheContainerId": "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.AzureContextCache/accounts/<cacheAcct>/containers/<containerName>"
  }
}
```

**To unlink the cache later**, PUT the same deployment payload without `properties.contextCacheContainerId` — keeping `sku` and `model` identical to the existing deployment:

```bash
ARM_TOKEN="$(az account get-access-token --resource https://management.azure.com/ --query accessToken -o tsv)"
curl -i --fail-with-body -X PUT \
  "https://management.azure.com/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<aoai>/deployments/<deploymentName>?api-version=2026-03-15-preview" \
  -H "Authorization: Bearer ${ARM_TOKEN}" -H 'Content-Type: application/json' \
  --data-raw '{
    "sku": { "name": "Standard", "capacity": 100 },
    "properties": {
      "model": { "format": "OpenAI", "name": "gpt-5.4", "version": "2026-03-05-contextcache" }
    }
  }'
```

---

## Repository layout

```
.
├── azuredeploy.json                    # Main ARM template (Deploy-to-Azure button target)
├── azuredeploy.parameters.json         # Example parameters
├── bicep/
│   ├── main.bicep                      # Bicep equivalent of azuredeploy.json
│   └── main.bicepparam
├── prereqs/
│   ├── assign-reader-role.json         # Sub-scope ARM: Reader for CSRP
│   └── assign-reader-role.bicep
├── scripts/
│   ├── register-providers.ps1          # RP + preview feature registration
│   └── deploy.ps1                      # Convenience wrapper around az deployment
└── .github/workflows/validate.yml      # Bicep build + ARM JSON syntax check on PR
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FeatureNotRegistered: Microsoft.AzureContextCache/EnablePreview` | Re-run `register-providers.ps1`. Email azurecontextcacherp@microsoft.com if state stays `Pending`. |
| `FeatureNotRegistered: OpenAI.ContextCacheAllowed` | `az feature register --namespace Microsoft.CognitiveServices --name OpenAI.ContextCacheAllowed`, wait for approval. |
| `403 AuthorizationFailed` on `Microsoft.CognitiveServices/accounts/deployments/write` | Caller needs write on the AOAI account / RG / sub. After a fresh role assignment, get a new token (`az account get-access-token`) and retry. |
| Deployment succeeds but cache is not linked | Confirm `properties.contextCacheContainerId` is present, points to the container ARM id, and the AOAI account is **in the same region** as the cache container. |
| `LocationNotAvailableForResourceType` | Supported regions today are `centralus` (launch) and `swedencentral`. |
| `InvalidResourceName` | Account: 3-24 chars; container: 3-63 chars. Lowercase letters/digits/hyphens; must start and end with a letter or digit. |
| Schema / API errors on AOAI PUT | Confirm `api-version=2026-03-15-preview` and that subscription feature registration is complete. |

---

## License

MIT.
