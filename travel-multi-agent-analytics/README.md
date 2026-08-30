# Travel Multi-Agent Application: Demo and Reference Implementation

The [Travel Multi-Agent Workshop](https://github.com/AzureCosmosDB/travel-multi-agent-workshop) includes a complete multi-agent travel assistant that you can deploy as a hosted demo or use as a reference implementation.

The [`02_completed` solution](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/02_completed) is the fastest way to explore the finished application. It includes the agent application, web frontend, infrastructure as code, sample data, analytics, and optimization features developed throughout the workshop.

> The links in this guide intentionally target the workshop's `main` branch.

## What the complete solution includes

- **Multi-agent travel planning** - a LangGraph supervisor coordinates hotel, dining, activity, itinerary, and other specialist agents.
- **Persistent agent memory** - the [`azure-cosmos-agent-memory`](https://pypi.org/project/azure-cosmos-agent-memory/) SDK stores facts, summaries, and user context in Azure Cosmos DB.
- **Agent tools** - a FastMCP server provides place discovery, trip management, memory, summarization, and agent handoff tools.
- **Hosted demo** - an Angular frontend, FastAPI backend, and MCP server deploy to Azure Container Apps.
- **Analytics and optimization** - an Analytics Portal surfaces agent quality, cost, conversion, and model-usage signals, with reversible optimization policies.
- **Microsoft Fabric integration** - optional Cosmos DB mirroring, Spark, reverse ETL, and Power BI components extend the operational application with analytics.

## Deploy the hosted demo

### Prerequisites

- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli)
- [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Python 3.11 or later](https://www.python.org/downloads/)
- [Node.js 18 or later](https://nodejs.org/en/download/)

### Deploy

```powershell
git clone --branch main https://github.com/AzureCosmosDB/travel-multi-agent-workshop.git
cd travel-multi-agent-workshop\02_completed
azd auth login
azd up
```

`azd up` provisions and seeds the required Azure resources, builds the application images, and deploys the frontend, API, and MCP server to Azure Container Apps. When deployment finishes, open the public `FRONTEND_URI` shown in the output.

The complete solution uses demo-friendly defaults:

| Environment variable | Default | Purpose |
|---|---:|---|
| `DEPLOY_HOSTED_APP` | `true` | Deploys the frontend, API, and MCP server to Azure Container Apps. |
| `DEPLOY_ANALYTICS` | `true` | Provisions the analytics and optimization containers and Microsoft Fabric F2 capacity used by the optional analytics modules. |
| `DEPLOY_GSI` | `false` | Optionally provisions a global secondary index demonstration with a larger trip dataset. |

Set a value before deployment when you want a leaner environment:

```powershell
azd env set DEPLOY_ANALYTICS false
azd up
```

See the [complete solution README](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/blob/main/02_completed/README.md) for all deployment and configuration options.

## Run the application locally

Run `azd provision` from `02_completed` first. The post-provision hook creates `.venv-travel`, writes the application environment files, and seeds Cosmos DB.

Then open three terminals from the `02_completed` directory:

```powershell
# Terminal 1 - MCP server
.\.venv-travel\Scripts\Activate.ps1
cd mcp_server
$env:PYTHONPATH="..\python"
python mcp_http_server.py
```

```powershell
# Terminal 2 - Travel API
.\.venv-travel\Scripts\Activate.ps1
cd python
uvicorn src.app.travel_agents_api:app --reload --host 0.0.0.0 --port 8000
```

```powershell
# Terminal 3 - Angular frontend
cd frontend
npm install
npm start
```

Open:

- Frontend: [http://localhost:4200](http://localhost:4200)
- Travel API documentation: [http://localhost:8000/docs](http://localhost:8000/docs)
- MCP server: [http://localhost:8080](http://localhost:8080)

## Use it as a reference implementation

The completed solution is organized by application layer:

| Path | Contents |
|---|---|
| [`02_completed/python`](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/02_completed/python) | LangGraph agents, FastAPI endpoints, prompts, Azure integrations, data models, and seed data. |
| [`02_completed/mcp_server`](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/02_completed/mcp_server) | FastMCP tools used by the agents. |
| [`02_completed/frontend`](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/02_completed/frontend) | Angular chat application and analytics user experience. |
| [`02_completed/infra`](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/02_completed/infra) | Bicep templates and deployment configuration. |
| [`analytics`](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/analytics) | Analytics Portal, Fabric automation, Power BI assets, seeders, and evaluation resources. |

Use the [workshop exercises](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/tree/main/01_exercises) for the guided learning path, and compare your implementation with `02_completed` as you progress.

## Demo and analytics guides

- [User and Demo Guide](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/blob/main/02_completed/USER_GUIDE.md) - configure the solution, run the application, generate traffic, and present the demo.
- [Analytics overview](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/blob/main/analytics/README.md) - understand the Analytics Portal, Fabric reverse ETL, Power BI report, and supporting tools.
- [Fabric automation runbook](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/blob/main/analytics/fabric/README.md) - provision the Fabric components used by the analytics and optimization scenario.
- [Power BI build guide](https://github.com/AzureCosmosDB/travel-multi-agent-workshop/blob/main/analytics/powerbi/PowerBI_Optimization_Build_Guide.md) - understand and maintain the report and semantic model.
