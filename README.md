# Azure Context Cache — Quickstart

A one-click sample for provisioning an **Azure Context Cache (Prompt Cache)** account + container in your subscription, and optionally surfacing the connection details for an **existing Azure OpenAI** endpoint so your app can start sending cache-aware requests immediately.

> Azure Context Cache (resource provider `Microsoft.AzureContextCache`) is in **preview**. The only supported region today is **`swedencentral`** and the only supported API version is **`2026-01-01-preview`**.

---

## One-click deploy

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fazuredeploy.json)

[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](https://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fazuredeploy.json)

The Deploy-to-Azure button opens the Azure Portal **Custom deployment** blade pre-loaded with [`azuredeploy.json`](azuredeploy.json). Pick a subscription + resource group, fill in the parameters, and click **Create**.

---

## What gets deployed

| Resource | Type | Notes |
|---|---|---|
| Context Cache account | `Microsoft.AzureContextCache/accounts` | `accountKind = Regional` by default |
| Cache container | `Microsoft.AzureContextCache/accounts/containers` | Bound to a `modelName` + `provider = OpenAI` |

If you provide `existingAzureOpenAIAccountName`, the deployment also reads that AOAI account and returns its **endpoint** + **resource id** as outputs so you can wire your client without an extra round trip.

---

## Prerequisites (one-time, per subscription)

These steps cannot be done from the Deploy-to-Azure button — run them once first.

### 1. Register the resource provider and preview feature

```powershell
./scripts/register-providers.ps1 -SubscriptionId <your-sub-id>
```

Or manually:

```bash
az provider register --namespace Microsoft.AzureContextCache
az feature register  --namespace Microsoft.AzureContextCache --name EnablePreview
```

The `EnablePreview` feature is **gated**. After registering, email **azurecontextcacherp@microsoft.com** for approval if state stays `Pending`.

Verify:

```bash
az provider show --namespace Microsoft.AzureContextCache --query registrationState
az feature  show --namespace Microsoft.AzureContextCache --name EnablePreview --query properties.state
# Both should print "Registered"
```

### 2. Grant the Cognitive Services RP `Reader` on your subscription

Until the built-in CSRP role definition rolls out globally, you must give the **Microsoft Cognitive Services** enterprise application (App ID `7d312290-28c8-473c-a0ed-8e53749b6d6d`) `Reader` on the subscription that hosts your Context Cache account.

Find its **Object ID** once:

1. Azure Portal → **Microsoft Entra ID** → **Enterprise applications**
2. Search for App ID `7d312290-28c8-473c-a0ed-8e53749b6d6d`
3. Copy the **Object ID** of "Microsoft Cognitive Services"

Then deploy [`prereqs/assign-reader-role.json`](prereqs/assign-reader-role.json) at subscription scope:

[![Deploy reader role](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkraman-msft-eng%2FAzureContextCache%2Fmain%2Fprereqs%2Fassign-reader-role.json)

CLI alternative:

```bash
az deployment sub create \
  --name assign-reader-role \
  --location swedencentral \
  --template-file ./prereqs/assign-reader-role.json \
  --parameters principalObjectId=<csrp-object-id>
```

or simply:

```bash
az role assignment create \
  --assignee-object-id <csrp-object-id> \
  --assignee-principal-type ServicePrincipal \
  --role Reader \
  --scope /subscriptions/<subscription-id>
```

---

## Parameters

| Name | Default | Description |
|---|---|---|
| `accountName` | `cc<hash>` | 3-24 chars, `^[a-z0-9][a-z0-9-]{1,22}[a-z0-9]$` |
| `containerName` | `default-container` | 3-63 chars, `^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$` |
| `location` | `swedencentral` | Only `swedencentral` is supported today |
| `accountKind` | `Regional` | `Regional` \| `DataZone` \| `Global` |
| `modelName` | `gpt-4` | Must match the underlying model of your AOAI deployment |
| `provider` | `OpenAI` | Only `OpenAI` is supported today |
| `timeToLiveDays` | `7` | 1-30 |
| `existingAzureOpenAIAccountName` | *(empty)* | Optional. Existing AOAI account in the same RG. Leave blank to skip association |

---

## Deploy from the CLI

```powershell
# ARM JSON
./scripts/deploy.ps1 -ResourceGroup rg-cc-demo -AccountName mycache01 -ContainerName gpt4-cache -ModelName gpt-4

# Same thing, but with Bicep
./scripts/deploy.ps1 -ResourceGroup rg-cc-demo -UseBicep -ExistingAzureOpenAIAccountName my-aoai
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

## Associating with your Azure OpenAI endpoint

Azure Context Cache containers are model-scoped, **not** physically bound to one AOAI deployment. To use the cache from your application:

1. Deploy this template with `modelName` matching the **underlying model** of your AOAI deployment (e.g., `gpt-4`, `gpt-4o`).
2. Pass `existingAzureOpenAIAccountName` so the deployment outputs your AOAI endpoint.
3. In your client, send requests to your **AOAI endpoint** as usual, and pass the cache **container resource id** (`/subscriptions/.../containers/<containerName>`) — surfaced in the `containerId` output — to the Azure OpenAI SDK as the prompt-cache target.

The Cognitive Services RP uses the `Reader` assignment from the prerequisites to look up your container.

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
| `FeatureNotRegistered` on deploy | Re-run `register-providers.ps1` and wait until `EnablePreview` shows `Registered`. Email azurecontextcacherp@microsoft.com if it stays `Pending`. |
| `LocationNotAvailableForResourceType` | The only supported region is `swedencentral`. |
| `InvalidResourceName` | Account names: 3-24 chars; container names: 3-63 chars. Lowercase letters/digits/hyphens, must start and end with a letter or digit. |
| Container reads from CSRP fail | Confirm the Reader role assignment on the Microsoft Cognitive Services enterprise app (Object ID step in prerequisites) is applied at the correct scope. |
| Deploy-to-Azure button shows raw JSON | The button URL must be the **raw.githubusercontent.com** URL, URL-encoded, and the repo/branch must be public. |

---

## License

MIT. See repository root.
