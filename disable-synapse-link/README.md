<!--
---
page_type: sample
languages:
- powershell
- bash
products:
- fabric
- fabric-database-cosmos-db
- cosmos-db-synapse-link
name: |
    Disable Synapse Link Helper
urlFragment: disable-synapse-link-helper
description: Helper scripts to check Synapse Link status, guide migration to Fabric Mirroring, and safely disable analytical storage on Azure Cosmos DB NoSQL containers.
---
-->

# Disable Synapse Link Helper

> **This sample helps you: Check -> Migrate -> Disable Synapse Link safely.**

Synapse Link is in **maintenance mode**. Microsoft recommends migrating analytical workloads to **Fabric Mirroring** -- the strategic replacement that offers real-time replication of your Cosmos DB data into Microsoft Fabric OneLake.

> **WARNING: If you have analytical store data you still need, complete Fabric Mirroring migration BEFORE disabling Synapse Link.**
> Disabling makes the existing analytical store immediately and irreversibly inaccessible.
>
> **Migration guide: https://learn.microsoft.com/en-us/fabric/mirroring/azure-cosmos-db-migrate-synapse-link**

## The three-step workflow

### 1. Check -- inventory your Synapse Link usage (non-destructive)

Run the script in **Status mode** (the default) to see every container, its `analyticalStorageTTL` value, and whether the analytical store is likely active. No changes are made. Optionally export the inventory to CSV.

### 2. Migrate -- move analytical workloads to Fabric Mirroring

Before disabling, set up Fabric Mirroring for your Cosmos DB account so that your analytical pipelines continue to work. Run the script in **Migrate mode** to print the step-by-step guide with a direct link to the migration documentation, followed by a live inventory of your account.

### 3. Disable -- turn off Synapse Link billing

Once migration is complete and you no longer need the existing analytical store, run the script in **Disable mode**. The script displays an explicit destructive-action warning, lists the containers that will be affected, and requires confirmation before proceeding.

## Quick start

```powershell
# Status check (safe default -- no changes made)
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account"
```

```bash
# Status check (safe default -- no changes made)
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account
```

## Files

| File | Description |
|------|-------------|
| `Disable-CosmosDBAnalyticalStorage.ps1` | PowerShell script (Az PowerShell module) |
| `Disable-CosmosDBAnalyticalStorage.sh`  | Bash script (Azure CLI + jq)             |

## Prerequisites

### PowerShell

- PowerShell 7+ or Windows PowerShell 5.1
- Az PowerShell modules: `Install-Module Az -Scope CurrentUser`
- Logged in with `Connect-AzAccount` and **Cosmos DB Account Contributor** rights

### Bash

- Azure CLI 2.49 or later (`az version`)
- `jq` installed
- Logged in with `az login` and write access to the Cosmos DB account
- Bash environment (Azure Cloud Shell, WSL, macOS, or Linux)

## Usage by mode

### Status mode (default)

Lists all NoSQL containers with their `analyticalStorageTTL` value and a human-readable interpretation. **Non-destructive.**

TTL values are interpreted as follows:

| Raw TTL | Interpretation |
|---------|----------------|
| `0` or not set | Disabled -- Synapse Link is off |
| `-1` | Enabled, infinite retention |
| `N` (positive integer) | Enabled, N days retention |

```powershell
# Default -- same as -Mode Status
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account"

# Explicit mode flag
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Status

# Export inventory to CSV
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Status -OutputCsv .\sl-inventory.csv

# Target a specific database only
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Status -DatabaseName "myDb"
```

```bash
# Default -- same as --mode status
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account

# Explicit mode flag
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode status

# Export inventory to CSV
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode status --output-csv ./sl-inventory.csv

# Target a specific database
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode status --database-name myDb
```

### Migrate mode

Prints the Check->Migrate->Disable guide with a direct link to the Fabric Mirroring migration documentation, then runs a status check so you can see your current inventory. **Non-destructive.**

```powershell
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Migrate
```

```bash
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode migrate
```

### Disable mode

Sets `analyticalStorageTTL=0` on every container that has Synapse Link enabled in the target scope. **Destructive -- explicit `-Mode Disable` / `--mode disable` flag required.**

The script displays a destructive-action warning, lists the containers affected, and requires confirmation before making any changes.

```powershell
# Disable across the account (confirmation prompt shown)
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Disable

# Restrict to a specific database
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Disable -DatabaseName "myDb"

# Skip confirmation prompt (automation / CI pipelines)
.\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "rg-name" -AccountName "cosmos-account" -Mode Disable -Force
```

```bash
# Disable across the account
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode disable

# Restrict to a specific database
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode disable --database-name myDb

# Skip confirmation (automation)
./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg-name --account-name cosmos-account --mode disable --yes
```

## Parameters

| Option | Description |
|--------|-------------|
| `-ResourceGroupName` / `--resource-group` | **Required.** Resource group hosting the Cosmos DB account. |
| `-AccountName` / `--account-name` | **Required.** Cosmos DB account name to scan. |
| `-DatabaseName` / `--database-name` | Optional. Limit processing to one NoSQL database. |
| `-Mode` / `--mode` | Operation mode: `Status` (default), `Migrate`, or `Disable`. |
| `-OutputCsv` / `--output-csv` | Optional. Path to write a CSV inventory (Status and Migrate modes). |
| `-Force` / `--yes` | Bypass confirmation prompt in Disable mode (for unattended runs). |
| `-ListEnabled` / `--list-enabled` | **Deprecated.** Redirects to Status mode. Will be removed in a future release. |

## Backward compatibility

The `-ListEnabled` / `--list-enabled` flag is **preserved but deprecated**. It redirects to Status mode and prints a deprecation warning. It will be removed in a future release.

**The old behavior of running with no flags previously triggered a destructive disable. This has changed: the default is now Status (non-destructive).** If you have automation that omitted the mode flag and relied on implicit disable behavior, add `-Mode Disable` / `--mode disable` explicitly.

## Verification

After disabling, confirm that all containers report `analyticalStorageTTL = 0`:

```powershell
Get-AzCosmosDBSqlContainer `
    -ResourceGroupName "rg-name" `
    -AccountName "cosmos-account" `
    -DatabaseName "db-name" | `
    Select-Object Name, @{Name='AnalyticalStorageTTL';Expression={$_.Resource.AnalyticalStorageTtl}}
```

```bash
az cosmosdb sql container list \
  --resource-group rg-name \
  --account-name cosmos-account \
  --database-name db-name \
  --query "[].{name:name, analyticalStorageTTL:resource.analyticalStorageTtl}"
```

Every container should report `analyticalStorageTTL` equal to `0`.

## Caveats and troubleshooting

- **Disabling is irreversible for existing analytical data.** Re-enabling creates a new, empty analytical store seeded from current transactional data -- any data in the previous analytical store is permanently lost. Complete Fabric Mirroring migration before running Disable mode.
- The Status mode reports `Analytical store ACTIVE - data may exist` for any container with a non-zero TTL. The scripts cannot measure actual data volume from the Azure control plane; treat any ACTIVE container as potentially having data that needs migrating.
- Run the scripts only after Fabric Mirroring has fully replaced Synapse Link in your production scenarios.
- Use `-DatabaseName` / `--database-name` to scope the operation to a single database when working in large accounts.
- To avoid 403 Forbidden responses in the Azure Portal, ensure you have **Cosmos DB Account Contributor** rights (PowerShell) or the built-in data-plane roles **Cosmos DB Built-in Data Reader** and **Cosmos DB Built-in Data Writer** (CLI). These Azure Portal errors do not affect the scripts' ability to update `analyticalStorageTTL`.
- Run `az version` (CLI >= 2.49) or `Get-Module Az.CosmosDB` (PS) to verify your tooling meets the prerequisites before running the scripts.
