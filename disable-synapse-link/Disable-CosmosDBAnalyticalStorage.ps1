<#
.SYNOPSIS
    Check, guide migration, or disable Cosmos DB Analytical Storage (Synapse Link) for containers.

.DESCRIPTION
    Supports three modes:
      Status  (default) - Non-destructive inventory of all containers with Synapse Link TTL status.
      Migrate           - Prints the Check->Migrate->Disable guide with migration link, then runs Status.
      Disable           - Sets analyticalStorageTTL=0 on enabled containers. DESTRUCTIVE. Explicit opt-in.

    Synapse Link is in maintenance mode. Migrate to Fabric Mirroring before disabling if you still
    need analytical store data:
    https://learn.microsoft.com/en-us/fabric/mirroring/azure-cosmos-db-migrate-synapse-link

.PARAMETER ResourceGroupName
    Resource group name containing the Cosmos DB account.

.PARAMETER AccountName
    Cosmos DB account name.

.PARAMETER DatabaseName
    (Optional) Specific SQL database to target. Processes all databases if not specified.

.PARAMETER Mode
    Operation mode: Status (default), Migrate, or Disable.
      Status  - Lists all containers and their analyticalStorageTTL. Non-destructive.
      Migrate - Prints the migration guide and link, then runs Status.
      Disable - Sets analyticalStorageTTL=0 on all enabled containers. DESTRUCTIVE.

.PARAMETER OutputCsv
    (Optional) Path to write a CSV inventory of containers. Applies to Status and Migrate modes.

.PARAMETER Force
    (Disable mode) Skips the confirmation prompt. Use for automation.

.PARAMETER ListEnabled
    DEPRECATED. Redirects to -Mode Status. Will be removed in a future release.

.EXAMPLE
    # Status check (safe default - no changes made)
    .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "myRG" -AccountName "myAccount"

.EXAMPLE
    # Status check with CSV export
    .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "myRG" -AccountName "myAccount" -Mode Status -OutputCsv .\sl-inventory.csv

.EXAMPLE
    # Print migration guide then show inventory
    .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "myRG" -AccountName "myAccount" -Mode Migrate

.EXAMPLE
    # Disable Synapse Link (destructive - explicit opt-in required)
    .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "myRG" -AccountName "myAccount" -Mode Disable

.EXAMPLE
    # Disable a specific database with auto-confirm (automation)
    .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName "myRG" -AccountName "myAccount" -Mode Disable -DatabaseName "myDb" -Force
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory=$true)]
    [string]$AccountName,

    [Parameter(Mandatory=$false)]
    [string]$DatabaseName,

    [Parameter(Mandatory=$false)]
    [ValidateSet('Status','Migrate','Disable')]
    [string]$Mode = 'Status',

    [Parameter(Mandatory=$false)]
    [string]$OutputCsv,

    [switch]$Force,

    # Deprecated: use -Mode Status instead
    [switch]$ListEnabled
)

$MIGRATE_URL = 'https://learn.microsoft.com/en-us/fabric/mirroring/azure-cosmos-db-migrate-synapse-link'

# Backward-compatibility: -ListEnabled deprecated
if ($ListEnabled) {
    Write-Warning "-ListEnabled is deprecated. Use -Mode Status instead. -ListEnabled will be removed in a future release."
    $Mode = 'Status'
}

# Default mode notice: surfaces when no -Mode was supplied (old callers who relied on implicit disable)
if (-not $PSBoundParameters.ContainsKey('Mode') -and -not $ListEnabled) {
    Write-Host ""
    Write-Host "INFO: Default mode changed from Disable to Status for safety." -ForegroundColor Cyan
    Write-Host "      No changes will be made. Run with -Mode Disable to disable Synapse Link." -ForegroundColor Cyan
    Write-Host ""
}

# Check for Az.CosmosDB module
if (-not (Get-Module -ListAvailable -Name Az.CosmosDB)) {
    Write-Error "Az.CosmosDB module required. Install with: Install-Module -Name Az.CosmosDB"
    exit 1
}

Import-Module Az.CosmosDB

# Retry helper function
function Invoke-WithRetry {
    param(
        [ScriptBlock]$ScriptBlock,
        [int]$MaxRetries = 5,
        [int]$DelaySeconds = 5
    )
    $attempt = 1
    while ($attempt -le $MaxRetries) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($attempt -eq $MaxRetries) { throw }
            Write-Host "  Retry $attempt/$MaxRetries failed, waiting $DelaySeconds seconds..." -ForegroundColor DarkYellow
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

# TTL interpretation helper
function Get-TtlInterpretation {
    param($Ttl)
    if ($null -eq $Ttl -or $Ttl -eq 0) { return 'Disabled (0)' }
    if ($Ttl -eq -1)                    { return 'Enabled, infinite retention (-1)' }
    return "Enabled, $Ttl days retention"
}

# Ensure Azure login
if (-not (Get-AzContext)) {
    Write-Host "Not logged into Azure. Initiating login..." -ForegroundColor Yellow
    Connect-AzAccount
    Write-Host "Login successful. Initializing Azure context..." -ForegroundColor Green
}

Write-Host ""
Write-Host "Cosmos DB Synapse Link Status Tool" -ForegroundColor Cyan
Write-Host "Account: $AccountName | Resource Group: $ResourceGroupName | Mode: $Mode" -ForegroundColor White
Write-Host ""

# MIGRATE mode: print guide banner, then fall through to Status logic
if ($Mode -eq 'Migrate') {
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "        SYNAPSE LINK -> FABRIC MIRRORING MIGRATION GUIDE" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "WHY MIGRATE?" -ForegroundColor Yellow
    Write-Host "  Azure Synapse Link is in maintenance mode and is not receiving new"
    Write-Host "  investment. Fabric Mirroring is the strategic replacement, offering"
    Write-Host "  real-time replication of your Cosmos DB data into Microsoft Fabric"
    Write-Host "  OneLake with richer analytics capabilities."
    Write-Host ""
    Write-Host "THREE-STEP PROCESS:" -ForegroundColor Yellow
    Write-Host "  1. CHECK   -> Run this script in Status mode (default) to inventory"
    Write-Host "               which containers have Synapse Link enabled."
    Write-Host "  2. MIGRATE -> Complete Fabric Mirroring setup so analytical workloads"
    Write-Host "               run on Fabric before you touch Synapse Link."
    Write-Host "  3. DISABLE -> Run this script with -Mode Disable to set"
    Write-Host "               analyticalStorageTTL=0 once migration is complete."
    Write-Host ""
    Write-Host "MIGRATION GUIDE:" -ForegroundColor Yellow
    Write-Host "  $MIGRATE_URL" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "DISABLE SCRIPT (use after migration is complete):" -ForegroundColor Yellow
    Write-Host "  https://github.com/AzureCosmosDB/cosmos-fabric-samples/tree/main/disable-synapse-link" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "  Running STATUS CHECK below so you can see your current inventory..." -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Enumerate databases
if ($DatabaseName) {
    $databases = @(Invoke-WithRetry -ScriptBlock {
        Get-AzCosmosDBSqlDatabase -ResourceGroupName $ResourceGroupName -AccountName $AccountName -Name $DatabaseName -ErrorAction Stop
    })
} else {
    $databases = Invoke-WithRetry -ScriptBlock {
        Get-AzCosmosDBSqlDatabase -ResourceGroupName $ResourceGroupName -AccountName $AccountName -ErrorAction Stop
    }
}

Write-Host "Processing $($databases.Count) database(s)..." -ForegroundColor Green
Write-Host ""

# Enumerate containers and classify
$allContainers     = @()
$enabledContainers = @()

foreach ($db in $databases) {
    $containers = Invoke-WithRetry -ScriptBlock {
        Get-AzCosmosDBSqlContainer -ResourceGroupName $ResourceGroupName -AccountName $AccountName -DatabaseName $db.Name -ErrorAction Stop
    }
    foreach ($container in $containers) {
        $ttl    = $container.Resource.AnalyticalStorageTtl
        $interp = Get-TtlInterpretation -Ttl $ttl
        $active = if ($null -ne $ttl -and $ttl -ne 0) {
            'Analytical store ACTIVE - data may exist'
        } else {
            'Not active'
        }
        $obj = [pscustomobject]@{
            Database             = $db.Name
            Container            = $container.Name
            AnalyticalStorageTTL = if ($null -eq $ttl) { 0 } else { $ttl }
            Interpretation       = $interp
            Status               = $active
        }
        $allContainers += $obj
        if ($null -ne $ttl -and $ttl -ne 0) {
            $enabledContainers += $obj
        }
    }
}

# STATUS and MIGRATE modes: print inventory and recommendations
if ($Mode -eq 'Status' -or $Mode -eq 'Migrate') {

    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "SYNAPSE LINK INVENTORY" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($allContainers.Count -eq 0) {
        Write-Host "No SQL containers found in the target scope." -ForegroundColor Yellow
    } else {
        $allContainers | Format-Table -AutoSize -Property Database, Container, AnalyticalStorageTTL, Interpretation, Status | Out-String | Write-Host
    }

    if ($OutputCsv) {
        $allContainers | Export-Csv -Path $OutputCsv -NoTypeInformation -Force
        Write-Host "CSV inventory written to: $OutputCsv" -ForegroundColor Green
        Write-Host ""
    }

    Write-Host "NOTE: 'Analytical store ACTIVE' means analyticalStorageTTL is non-zero. This" -ForegroundColor DarkYellow
    Write-Host "      script cannot reliably measure actual data volume from the control plane." -ForegroundColor DarkYellow
    Write-Host "      Treat any ACTIVE container as potentially having data to migrate." -ForegroundColor DarkYellow
    Write-Host ""

    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "WHAT TO DO NEXT" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""

    if ($enabledContainers.Count -eq 0) {
        Write-Host "No containers have Synapse Link enabled -- no action needed." -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "$($enabledContainers.Count) container(s) have Synapse Link enabled -- review carefully before disabling." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  !! MIGRATE TO FABRIC MIRRORING FIRST if you have analytical store data you still need." -ForegroundColor Red
        Write-Host "     Migration guide: $MIGRATE_URL" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Once migration is complete, disable with:" -ForegroundColor White
        Write-Host "  .\Disable-CosmosDBAnalyticalStorage.ps1 -ResourceGroupName `"$ResourceGroupName`" -AccountName `"$AccountName`" -Mode Disable" -ForegroundColor Magenta
        Write-Host ""
    }
    return
}

# DISABLE mode
if ($Mode -eq 'Disable') {

    if ($enabledContainers.Count -eq 0) {
        Write-Host "No containers have Synapse Link enabled. Nothing to disable." -ForegroundColor Green
        Write-Host ""
        return
    }

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host "                    !! DESTRUCTIVE ACTION !!" -ForegroundColor Red
    Write-Host "======================================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  This will set analyticalStorageTTL=0 on $($enabledContainers.Count) container(s). The existing" -ForegroundColor Red
    Write-Host "  analytical store becomes INACCESSIBLE IMMEDIATELY. This cannot be" -ForegroundColor Red
    Write-Host "  reversed without re-enabling and starting from an empty analytical store." -ForegroundColor Red
    Write-Host ""
    Write-Host "  !! If you have analytical store data you still need, STOP NOW and complete" -ForegroundColor Yellow
    Write-Host "     Fabric Mirroring migration first:" -ForegroundColor Yellow
    Write-Host "     $MIGRATE_URL" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Containers to be disabled:" -ForegroundColor Yellow
    foreach ($item in $enabledContainers) {
        Write-Host ("  {0}/{1}  (TTL: {2} -- {3})" -f $item.Database, $item.Container, $item.AnalyticalStorageTTL, $item.Interpretation) -ForegroundColor Yellow
    }
    Write-Host ""

    if (-not $Force) {
        $confirmation = Read-Host "Do you want to disable analytical storage for $($enabledContainers.Count) container(s)? This action cannot be undone. [y/N]"
        if ($confirmation -notmatch '^[Yy]$') {
            Write-Host "Operation cancelled." -ForegroundColor Yellow
            return
        }
    }

    $disabledCount = 0
    foreach ($item in $enabledContainers) {
        try {
            Invoke-WithRetry -ScriptBlock {
                Update-AzCosmosDBSqlContainer `
                    -ResourceGroupName $ResourceGroupName `
                    -AccountName $AccountName `
                    -DatabaseName $item.Database `
                    -Name $item.Container `
                    -AnalyticalStorageTtl 0 `
                    -ErrorAction Stop | Out-Null
            }
            Write-Host "  OK Disabled $($item.Database)/$($item.Container)" -ForegroundColor Green
            $disabledCount++
        }
        catch {
            Write-Host "  FAILED $($item.Database)/$($item.Container): $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host "SUMMARY" -ForegroundColor Cyan
    Write-Host "======================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Containers disabled: $disabledCount of $($enabledContainers.Count)" -ForegroundColor Green
    Write-Host ""
}
