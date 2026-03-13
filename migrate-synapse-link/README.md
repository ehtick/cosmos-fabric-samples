<!--
---
page_type: sample
languages:
- python
products:
- fabric
- fabric-database-cosmos-db
name: |
   Migrate Synapse Link to Mirroring
urlFragment: migrate-synapse-link
description: Automate the migration of historical data from Azure Synapse Link analytical store to Cosmos DB mirroring in Microsoft Fabric with schema alignment and cutover filtering.
---
-->

# 🔄 Migrate Synapse Link to Mirroring

Automate the migration of historical data from Azure Synapse Link analytical store to Cosmos DB mirroring in Microsoft Fabric.

## 📋 Overview

This notebook provides an automated migration path from **Synapse Link (analytical store)** to **Cosmos DB mirroring** in Fabric. It reads historical data from the analytical store, aligns the schema to match the mirror format, applies a cutover timestamp filter, and writes the result as a Delta table — enabling a seamless transition to the mirroring architecture.

## 🎯 What You'll Learn

- **Schema Alignment** - Automatically align analytical store schema to mirror schema (nested JSON conversion, type casting, missing column handling)
- **Cutover Filtering** - Filter historical data using a Unix timestamp to avoid overlap with mirrored data
- **Delta Table Output** - Write the aligned historical dataset to OneLake as a Delta table
- **Migration Automation** - End-to-end scripted migration with minimal manual intervention

## 🚀 Getting Started

### Prerequisites

- Microsoft Fabric workspace with Spark compute
- Cosmos DB container with **Synapse Link (analytical store)** enabled
- Cosmos DB **mirroring** already configured and writing to OneLake
- A Lakehouse in Fabric to store the historical data output

### Configuration

Update the input parameters in the first cell of the notebook:

| Parameter | Description |
|-----------|-------------|
| `analytical_linked_service` | Synapse Link linked service name for the analytical store |
| `container_name` | Cosmos DB container name |
| `mirror_path` | OneLake path to the mirrored Delta table |
| `historical_data_write_path` | OneLake path to write the historical data output |
| `cutover_ts` | Unix timestamp marking the cutover point between historical and mirrored data |

### Steps

1. **Configure parameters** - Set the linked service, container, paths, and cutover timestamp
2. **Read mirror schema** - Load the current mirror Delta table schema as the target
3. **Read analytical store** - Load data from the Synapse Link analytical store
4. **Align schema** - Automatically convert nested types, cast mismatched types, and add missing columns
5. **Apply cutover filter** - Keep only records with `_ts` before the cutover timestamp
6. **Write historical data** - Save the aligned dataset as a Delta table in OneLake

## 📂 Files

| File | Description |
|------|-------------|
| `SL-To-Mirror-Migration-Automation-Notebook.ipynb` | Migration automation notebook |
