#!/usr/bin/env bash

set -euo pipefail

MAX_RETRIES=5
DELAY_SECONDS=5
MIGRATE_URL='https://learn.microsoft.com/en-us/fabric/mirroring/azure-cosmos-db-migrate-synapse-link'

print_usage() {
    cat <<'USAGE'
Usage: Disable-CosmosDBAnalyticalStorage.sh --resource-group <name> --account-name <name> [options]

Options:
  --resource-group, -g   Resource group name containing the Cosmos DB account (required)
  --account-name, -a     Cosmos DB account name (required)
  --database-name, -d    Specific database name to target (optional)
  --mode <mode>          Operation mode: status (default), migrate, or disable
                           status  - Non-destructive inventory of containers with Synapse Link TTL.
                           migrate - Prints the Check->Migrate->Disable guide, then runs status.
                           disable - Sets analyticalStorageTTL=0 on enabled containers. DESTRUCTIVE.
  --output-csv <path>    Write container inventory to a CSV file (status/migrate modes)
  --yes, -y              Skip confirmation prompt in disable mode (automation)
  --list-enabled, -l     DEPRECATED: use --mode status instead
  --help, -h             Show this help message

Examples:
  # Status check (safe default -- no changes made)
  ./Disable-CosmosDBAnalyticalStorage.sh --resource-group rg --account-name acct

  # Status with CSV export
  ./Disable-CosmosDBAnalyticalStorage.sh -g rg -a acct --mode status --output-csv ./sl-inventory.csv

  # Print migration guide then show inventory
  ./Disable-CosmosDBAnalyticalStorage.sh -g rg -a acct --mode migrate

  # Disable (destructive -- explicit opt-in)
  ./Disable-CosmosDBAnalyticalStorage.sh -g rg -a acct --mode disable

  # Disable with auto-confirm (automation)
  ./Disable-CosmosDBAnalyticalStorage.sh -g rg -a acct --mode disable --yes
USAGE
}

RESOURCE_GROUP=""
ACCOUNT_NAME=""
DATABASE_NAME=""
MODE="status"
OUTPUT_CSV=""
AUTO_CONFIRM=0
LIST_ENABLED=0
MODE_EXPLICITLY_SET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group|-g)
            RESOURCE_GROUP="$2"; shift 2 ;;
        --account-name|-a)
            ACCOUNT_NAME="$2"; shift 2 ;;
        --database-name|-d)
            DATABASE_NAME="$2"; shift 2 ;;
        --mode)
            MODE="${2,,}"; MODE_EXPLICITLY_SET=1; shift 2 ;;
        --output-csv)
            OUTPUT_CSV="$2"; shift 2 ;;
        --yes|-y)
            AUTO_CONFIRM=1; shift 1 ;;
        --list-enabled|-l)
            LIST_ENABLED=1; shift 1 ;;
        --help|-h)
            print_usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage >&2
            exit 1 ;;
    esac
done

# Validate mode
case "$MODE" in
    status|migrate|disable) ;;
    *)
        echo "Invalid --mode '$MODE'. Valid values: status, migrate, disable" >&2
        exit 1 ;;
esac

if [[ -z "$RESOURCE_GROUP" || -z "$ACCOUNT_NAME" ]]; then
    echo "--resource-group and --account-name are required" >&2
    print_usage >&2
    exit 1
fi

for tool in az jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool '$tool' not found. Install it before running this script." >&2
        exit 1
    fi
done

if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    CYAN="$(tput setaf 6)"
    YELLOW="$(tput setaf 3)"
    GREEN="$(tput setaf 2)"
    RED="$(tput setaf 1)"
    MAGENTA="$(tput setaf 5)"
    WHITE="$(tput setaf 7)"
    DARK_YELLOW="$(tput setaf 3)"
    RESET="$(tput sgr0)"
else
    CYAN="" YELLOW="" GREEN="" RED="" MAGENTA="" WHITE="" DARK_YELLOW="" RESET=""
fi

invoke_with_retry() {
    local max_retries=$1
    local delay_seconds=$2
    shift 2
    local attempt=1
    local output
    while (( attempt <= max_retries )); do
        if output="$("$@")"; then
            printf '%s' "$output"
            return 0
        fi
        local status=$?
        if (( attempt == max_retries )); then return "$status"; fi
        printf '  %sRetry %d/%d failed, waiting %d seconds...%s\n' \
            "$DARK_YELLOW" "$attempt" "$max_retries" "$delay_seconds" "$RESET" >&2
        sleep "$delay_seconds"
        ((attempt++))
    done
}

get_ttl_interpretation() {
    local ttl="$1"
    if [[ -z "$ttl" || "$ttl" == "0" || "$ttl" == "null" ]]; then
        echo "Disabled (0)"
    elif [[ "$ttl" == "-1" ]]; then
        echo "Enabled, infinite retention (-1)"
    else
        echo "Enabled, ${ttl} days retention"
    fi
}

# Backward-compatibility: --list-enabled deprecated
if (( LIST_ENABLED == 1 )); then
    printf '%sWARNING: --list-enabled is deprecated. Use --mode status instead. --list-enabled will be removed in a future release.%s\n' "$YELLOW" "$RESET" >&2
    MODE="status"
    MODE_EXPLICITLY_SET=1
fi

# Default mode notice: surfaces when no --mode was supplied
if (( MODE_EXPLICITLY_SET == 0 )); then
    printf '\n%sINFO: Default mode changed from disable to status for safety.%s\n' "$CYAN" "$RESET"
    printf '%s     No changes will be made. Run with --mode disable to disable Synapse Link.%s\n\n' "$CYAN" "$RESET"
fi

# Azure login check
if ! az account show >/dev/null 2>&1; then
    printf '%sNot logged into Azure. Initiating login...%s\n' "$YELLOW" "$RESET"
    az login >/dev/null
    printf '%sLogin successful. Initializing Azure context...%s\n' "$GREEN" "$RESET"
fi

printf '\n%sCosmos DB Synapse Link Status Tool%s\n' "$CYAN" "$RESET"
printf '%sAccount: %s | Resource Group: %s | Mode: %s%s\n\n' "$WHITE" "$ACCOUNT_NAME" "$RESOURCE_GROUP" "$MODE" "$RESET"

# MIGRATE mode: print guide banner then fall through to status logic
if [[ "$MODE" == "migrate" ]]; then
    printf '%s======================================================================%s\n' "$CYAN" "$RESET"
    printf '%s       SYNAPSE LINK -> FABRIC MIRRORING MIGRATION GUIDE%s\n' "$CYAN" "$RESET"
    printf '%s======================================================================%s\n\n' "$CYAN" "$RESET"
    printf '%sWHY MIGRATE?%s\n' "$YELLOW" "$RESET"
    printf '  Azure Synapse Link is in maintenance mode and is not receiving new\n'
    printf '  investment. Fabric Mirroring is the strategic replacement, offering\n'
    printf '  real-time replication of your Cosmos DB data into Microsoft Fabric\n'
    printf '  OneLake with richer analytics capabilities.\n\n'
    printf '%sTHREE-STEP PROCESS:%s\n' "$YELLOW" "$RESET"
    printf '  1. CHECK   -> Run this script in status mode (default) to inventory\n'
    printf '               which containers have Synapse Link enabled.\n'
    printf '  2. MIGRATE -> Complete Fabric Mirroring setup so analytical workloads\n'
    printf '               run on Fabric before you touch Synapse Link.\n'
    printf '  3. DISABLE -> Run this script with --mode disable to set\n'
    printf '               analyticalStorageTTL=0 once migration is complete.\n\n'
    printf '%sMIGRATION GUIDE:%s\n' "$YELLOW" "$RESET"
    printf '  %s%s%s\n\n' "$CYAN" "$MIGRATE_URL" "$RESET"
    printf '%sDISABLE SCRIPT (use after migration is complete):%s\n' "$YELLOW" "$RESET"
    printf '  %shttps://github.com/AzureCosmosDB/cosmos-fabric-samples/tree/main/disable-synapse-link%s\n\n' "$CYAN" "$RESET"
    printf '%s======================================================================%s\n' "$CYAN" "$RESET"
    printf '%s  Running STATUS CHECK below so you can see your current inventory...%s\n' "$WHITE" "$RESET"
    printf '%s======================================================================%s\n\n' "$CYAN" "$RESET"
fi

# Enumerate databases
databases_json=""
if [[ -n "$DATABASE_NAME" ]]; then
    if ! databases_json=$(invoke_with_retry "$MAX_RETRIES" "$DELAY_SECONDS" \
        az cosmosdb sql database show \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$ACCOUNT_NAME" \
        --name "$DATABASE_NAME" \
        --output json); then
        echo "Failed to retrieve database '$DATABASE_NAME'." >&2
        exit 1
    fi
    databases_json="[$databases_json]"
else
    if ! databases_json=$(invoke_with_retry "$MAX_RETRIES" "$DELAY_SECONDS" \
        az cosmosdb sql database list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$ACCOUNT_NAME" \
        --output json); then
        echo "Failed to retrieve databases." >&2
        exit 1
    fi
fi

database_count=$(jq 'length' <<<"$databases_json")
printf '%sProcessing %d database(s)...%s\n\n' "$GREEN" "$database_count" "$RESET"

declare -a all_containers=()
declare -a enabled_containers=()

mapfile -t database_array < <(jq -c '.[]' <<<"$databases_json")

for db in "${database_array[@]}"; do
    db_name=$(jq -r '.name' <<<"$db")
    [[ -z "$db_name" ]] && continue

    containers_json=""
    if ! containers_json=$(invoke_with_retry "$MAX_RETRIES" "$DELAY_SECONDS" \
        az cosmosdb sql container list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$ACCOUNT_NAME" \
        --database-name "$db_name" \
        --output json); then
        printf '%sFailed to retrieve containers for %s%s\n' "$RED" "$db_name" "$RESET" >&2
        continue
    fi

    while IFS= read -r container; do
        container_name=$(jq -r '.name' <<<"$container")
        ttl=$(jq -r '.analyticalStorageTtl // .resource.analyticalStorageTtl // empty' <<<"$container")
        [[ -z "$ttl" || "$ttl" == "null" ]] && ttl="0"

        interp=$(get_ttl_interpretation "$ttl")

        if [[ "$ttl" != "0" && "$ttl" != "null" && -n "$ttl" ]]; then
            active_status="Analytical store ACTIVE - data may exist"
        else
            active_status="Not active"
        fi

        all_containers+=("${db_name}|${container_name}|${ttl}|${interp}|${active_status}")
        if [[ "$ttl" != "0" && "$ttl" != "null" && -n "$ttl" ]]; then
            enabled_containers+=("${db_name}|${container_name}|${ttl}|${interp}|${active_status}")
        fi
    done < <(jq -c '.[]' <<<"$containers_json")
done

# STATUS and MIGRATE modes
if [[ "$MODE" == "status" || "$MODE" == "migrate" ]]; then
    printf '%s======================================================================%s\n' "$CYAN" "$RESET"
    printf '%sSYNAPSE LINK INVENTORY%s\n' "$CYAN" "$RESET"
    printf '%s======================================================================%s\n\n' "$CYAN" "$RESET"

    if (( ${#all_containers[@]} == 0 )); then
        printf '%sNo NoSQL containers found in the target scope.%s\n\n' "$YELLOW" "$RESET"
    else
        printf '%-28s %-28s %6s  %-38s  %s\n' "Database" "Container" "TTL" "Interpretation" "Status"
        printf '%-28s %-28s %6s  %-38s  %s\n' "--------" "---------" "---" "--------------" "------"
        for entry in "${all_containers[@]}"; do
            IFS='|' read -r db_name container_name ttl interp active_status <<<"$entry"
            if [[ "$active_status" == *"ACTIVE"* ]]; then
                row_color="$YELLOW"
            else
                row_color="$GREEN"
            fi
            printf "${row_color}%-28s %-28s %6s  %-38s  %s${RESET}\n" \
                "$db_name" "$container_name" "$ttl" "$interp" "$active_status"
        done
        printf '\n'
    fi

    if [[ -n "$OUTPUT_CSV" ]]; then
        {
            printf 'Database,Container,AnalyticalStorageTTL,Interpretation,Status\n'
            for entry in "${all_containers[@]}"; do
                IFS='|' read -r db_name container_name ttl interp active_status <<<"$entry"
                printf '"%s","%s","%s","%s","%s"\n' \
                    "$db_name" "$container_name" "$ttl" "$interp" "$active_status"
            done
        } > "$OUTPUT_CSV"
        printf '%sCSV inventory written to: %s%s\n\n' "$GREEN" "$OUTPUT_CSV" "$RESET"
    fi

    printf '%sNOTE: '"'"'Analytical store ACTIVE'"'"' means analyticalStorageTTL is non-zero. This%s\n' "$DARK_YELLOW" "$RESET"
    printf '%s      script cannot reliably measure actual data volume from the control plane.%s\n' "$DARK_YELLOW" "$RESET"
    printf '%s      Treat any ACTIVE container as potentially having data to migrate.%s\n\n' "$DARK_YELLOW" "$RESET"

    printf '%s======================================================================%s\n' "$CYAN" "$RESET"
    printf '%sWHAT TO DO NEXT%s\n' "$CYAN" "$RESET"
    printf '%s======================================================================%s\n\n' "$CYAN" "$RESET"

    if (( ${#enabled_containers[@]} == 0 )); then
        printf '%sNo containers have Synapse Link enabled -- no action needed.%s\n\n' "$GREEN" "$RESET"
    else
        printf '%s%d container(s) have Synapse Link enabled -- review carefully before disabling.%s\n\n' \
            "$YELLOW" "${#enabled_containers[@]}" "$RESET"
        printf '%s  !! MIGRATE TO FABRIC MIRRORING FIRST if you have analytical store data you still need.%s\n' "$RED" "$RESET"
        printf '%s     Migration guide: %s%s%s\n\n' "$RED" "$CYAN" "$MIGRATE_URL" "$RESET"
        printf '%s  Once migration is complete, disable with:%s\n' "$WHITE" "$RESET"
        printf '%s  ./Disable-CosmosDBAnalyticalStorage.sh --resource-group "%s" --account-name "%s" --mode disable%s\n\n' \
            "$MAGENTA" "$RESOURCE_GROUP" "$ACCOUNT_NAME" "$RESET"
    fi
    exit 0
fi

# DISABLE mode
if [[ "$MODE" == "disable" ]]; then
    if (( ${#enabled_containers[@]} == 0 )); then
        printf '%sNo containers have Synapse Link enabled. Nothing to disable.%s\n\n' "$GREEN" "$RESET"
        exit 0
    fi

    printf '\n%s======================================================================%s\n' "$RED" "$RESET"
    printf '%s                   !! DESTRUCTIVE ACTION !!%s\n' "$RED" "$RESET"
    printf '%s======================================================================%s\n\n' "$RED" "$RESET"
    printf '%s  This will set analyticalStorageTTL=0 on %d container(s). The existing%s\n' "$RED" "${#enabled_containers[@]}" "$RESET"
    printf '%s  analytical store becomes INACCESSIBLE IMMEDIATELY. This cannot be%s\n' "$RED" "$RESET"
    printf '%s  reversed without re-enabling and starting from an empty analytical store.%s\n\n' "$RED" "$RESET"
    printf '%s  !! If you have analytical store data you still need, STOP NOW and complete%s\n' "$YELLOW" "$RESET"
    printf '%s     Fabric Mirroring migration first:%s\n' "$YELLOW" "$RESET"
    printf '     %s%s%s\n\n' "$CYAN" "$MIGRATE_URL" "$RESET"

    printf '%sContainers to be disabled:%s\n' "$YELLOW" "$RESET"
    for entry in "${enabled_containers[@]}"; do
        IFS='|' read -r db_name container_name ttl interp active_status <<<"$entry"
        printf '  %s%s/%s  (TTL: %s -- %s)%s\n' "$YELLOW" "$db_name" "$container_name" "$ttl" "$interp" "$RESET"
    done
    printf '\n'

    if (( AUTO_CONFIRM == 0 )); then
        printf 'Do you want to disable analytical storage for %d container(s)? This action cannot be undone. [y/N]: ' \
            "${#enabled_containers[@]}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            printf '%sOperation cancelled.%s\n\n' "$YELLOW" "$RESET"
            exit 0
        fi
    fi

    disabled_count=0
    set +e
    for entry in "${enabled_containers[@]}"; do
        IFS='|' read -r db_name container_name ttl interp active_status <<<"$entry"
        printf '%sDisabling %s/%s...%s\n' "$YELLOW" "$db_name" "$container_name" "$RESET"
        if invoke_with_retry "$MAX_RETRIES" "$DELAY_SECONDS" \
            az cosmosdb sql container update \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$ACCOUNT_NAME" \
            --database-name "$db_name" \
            --name "$container_name" \
            --analytical-storage-ttl 0 >/dev/null; then
            printf '%s  OK Disabled %s/%s%s\n' "$GREEN" "$db_name" "$container_name" "$RESET"
            ((disabled_count++))
        else
            printf '%s  FAILED %s/%s%s\n' "$RED" "$db_name" "$container_name" "$RESET" >&2
        fi
    done
    set -euo pipefail

    printf '\n%s======================================================================%s\n' "$CYAN" "$RESET"
    printf '%sSUMMARY%s\n' "$CYAN" "$RESET"
    printf '%s======================================================================%s\n\n' "$CYAN" "$RESET"
    printf '%sContainers disabled: %d of %d%s\n\n' "$GREEN" "$disabled_count" "${#enabled_containers[@]}" "$RESET"
fi

exit 0
