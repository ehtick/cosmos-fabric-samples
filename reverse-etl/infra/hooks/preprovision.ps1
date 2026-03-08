# Pre-provision hook: Get the current signed-in user's Object ID
# and set it as an azd environment variable for the Bicep deployment.

Write-Host "Getting current user's Object ID..."

$userId = az ad signed-in-user show --query id -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to get signed-in user. Make sure you're logged in with 'az login'."
    exit 1
}

Write-Host "Current user Object ID: $userId"
azd env set AZURE_PRINCIPAL_ID $userId
