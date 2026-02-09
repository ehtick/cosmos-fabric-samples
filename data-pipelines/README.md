<!--
---
page_type: sample
languages:
- python
products:
- fabric
- fabric-database-cosmos-db
name: |
   Round-Trip Data Pipeline with Cosmos DB in Fabric
urlFragment: data-pipelines
description: Build a medallion pipeline (Bronze→Silver→Gold) in a Fabric Lakehouse using Cosmos DB sample data, then write enriched insights back to Cosmos DB (reverse ETL) with pipeline metadata logging.
---
-->

# 🔄 Round-Trip Data Pipeline with Cosmos DB in Microsoft Fabric

**Cosmos DB → Lakehouse (Bronze → Silver → Gold) → Cosmos DB**

This sample builds a complete round-trip data pipeline using **Cosmos DB in Microsoft Fabric** and **Fabric Data Pipelines**. It demonstrates two key patterns:

1. **Reverse ETL** — Processed Gold-layer insights written back to Cosmos DB for operational serving
2. **Pipeline Metastore** — Data quality, dataset profiles, and transform lineage logged to Cosmos DB via User Data Functions

## 📖 Scenario

A product catalog team stores products and customer reviews in Cosmos DB. They need analytics (ratings, pricing trends, category KPIs) but also want those insights served back through their operational APIs with sub-10ms reads. The pipeline reads auto-mirrored Cosmos DB data via a Lakehouse shortcut (Bronze), cleans and separates mixed document types into Silver tables, builds a Gold star schema, and writes pre-aggregated product insight cards and category KPI documents back to Cosmos DB. Each notebook also logs data quality, dataset profiles, and transform lineage to a pipeline metastore in Cosmos DB via User Data Functions.

## 🎯 What You'll Learn

- **Lakehouse shortcuts** to Cosmos DB mirrored data (zero-ETL Bronze layer)
- **Medallion architecture** with PySpark (Bronze → Silver → Gold star schema)
- **Cosmos DB Spark connector** for writing data back to Cosmos DB
- **User Data Functions** for reusable pipeline metadata logging
- **Fabric Data Pipelines** orchestrating notebooks and functions

## 📋 Prerequisites

- Microsoft Fabric workspace
- Cosmos DB database in Fabric with sample data loaded
- Fabric Lakehouse
- Custom Spark environment with Cosmos DB Spark connector JARs (for the reverse ETL notebook)

### Required Libraries (for `04_gold_to_cosmos` notebook)

Download from Maven Central (same JARs used in [`spark-scala/spark-scala.ipynb`](../spark-scala/spark-scala.ipynb)):

1. [azure-cosmos-spark_3-5_2-12-4.41.0.jar](https://repo1.maven.org/maven2/com/azure/cosmos/spark/azure-cosmos-spark_3-5_2-12/4.41.0/azure-cosmos-spark_3-5_2-12-4.41.0.jar)
2. [fabric-cosmos-spark-auth_3-1.1.0.jar](https://repo1.maven.org/maven2/com/azure/cosmos/spark/fabric-cosmos-spark-auth_3/1.1.0/fabric-cosmos-spark-auth_3-1.1.0.jar)

## 🗂️ Files

| File | Description |
|------|-------------|
| `02_bronze_to_silver.ipynb` | Splits mixed Bronze data into typed Silver tables (products, reviews, price history) |
| `03_silver_to_gold.ipynb` | Builds a star schema (dimensions + facts) from Silver tables |
| `04_gold_to_cosmos.ipynb` | Writes enriched product insights and category KPIs back to Cosmos DB |
| `functions/metastore_functions.py` | User Data Functions for logging data quality, profiles, and lineage to Cosmos DB |

## 🚀 Getting Started

### Step 1: Load Sample Data

1. In Fabric, create a **Cosmos DB** database (e.g., `ProductCatalog`)
2. Click **Sample data** to load 832 documents (180 products + 652 reviews)

### Step 2: Create Lakehouse Shortcut

1. Create a **Lakehouse** (e.g., `ProductCatalogLakehouse`)
2. Go to **Tables** → **New shortcut** → **Microsoft OneLake**
3. Select the auto-mirrored `SampleData` table from your Cosmos DB
4. Name the shortcut `bronze_sample_data`

### Step 3: Set Up Spark Environment

1. Create a new Spark environment, upload the two JAR files listed above
2. Publish and attach it to the `04_gold_to_cosmos` notebook

### Step 4: Deploy User Data Functions

1. Create a **User Data Functions** item named `PipelineMetadata`
2. Copy the code from `functions/metastore_functions.py`
3. Add a Cosmos DB generic connection and install `azure-cosmos` via Library Management

### Step 5: Import Notebooks and Build Pipeline

1. Import the three notebooks into your workspace
2. Create a **Data Pipeline** with three Notebook activities chained in sequence
3. Add a Functions activity at the end to call `summarize_pipeline_run`
4. Pass `@pipeline().RunId` as the `run_id` base parameter to each notebook

### Step 6: Run

Click **Run** in the pipeline toolbar and monitor progress in the **Output** tab.

## 📚 Additional Resources

- [Cosmos DB in Fabric](https://learn.microsoft.com/fabric/database/cosmos-db/)
- [Cosmos DB Spark Connector](https://learn.microsoft.com/azure/cosmos-db/nosql/tutorial-spark-connector)
- [Fabric User Data Functions](https://learn.microsoft.com/fabric/data-engineering/user-data-functions/user-data-functions-overview)
- [Fabric Data Pipelines](https://learn.microsoft.com/fabric/data-factory/activity-overview)

## 🤝 Contributing

Found an issue or have suggestions? Please open an issue in the main repository or submit a pull request.
