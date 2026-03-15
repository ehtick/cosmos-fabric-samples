# Post-provision hook: Write deployment outputs to webapp/.env

Write-Host "Writing deployment outputs to webapp/.env..."

$cosmosEndpoint   = azd env get-value COSMOS_ENDPOINT
$cosmosDatabase   = azd env get-value COSMOS_DATABASE
$cosmosContainer  = azd env get-value COSMOS_CONTAINER
$openAiEndpoint   = azd env get-value AZURE_OPENAI_ENDPOINT
$openAiKey        = azd env get-value AZURE_OPENAI_KEY
$embeddingModel   = azd env get-value OPENAI_EMBEDDING_MODEL
$apiVersion       = azd env get-value OPENAI_API_VERSION
$fabricSqlEndpoint = azd env get-value FABRIC_SQL_ENDPOINT 2>$null
$fabricLakehouse   = azd env get-value FABRIC_LAKEHOUSE 2>$null

$envContent = @"
# Cosmos DB
COSMOS_ENDPOINT=$cosmosEndpoint
COSMOS_DATABASE=$cosmosDatabase
COSMOS_CONTAINER=$cosmosContainer

# Azure OpenAI
AZURE_OPENAI_ENDPOINT=$openAiEndpoint
AZURE_OPENAI_KEY=$openAiKey
OPENAI_EMBEDDING_MODEL=$embeddingModel
OPENAI_API_VERSION=$apiVersion

# Fabric Lakehouse SQL Analytics Endpoint (for benchmark page)
FABRIC_SQL_ENDPOINT=$fabricSqlEndpoint
FABRIC_LAKEHOUSE=$fabricLakehouse
"@

$envPath = Join-Path $PSScriptRoot "../../webapp/.env"
Set-Content -Path $envPath -Value $envContent -Encoding UTF8
Write-Host "Wrote webapp/.env with deployed resource values."
