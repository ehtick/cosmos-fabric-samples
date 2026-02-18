import fabric.functions as fn
udf = fn.UserDataFunctions()

import logging
from typing import Any
from datetime import datetime, timezone
from fabric.functions.cosmosdb import get_cosmos_client
from azure.cosmos import exceptions


@udf.generic_connection(argName="cosmosDb", audienceType="CosmosDB")
@udf.function()
def log_data_quality(cosmosDb: fn.FabricItem, datasetId: str, runId: str,
                     totalInput: int, totalOutput: int, rejected: int,
                     rulesResults: list[dict[str, Any]]) -> dict[str, Any]:

    '''
    Summary: Log data quality validation results for a dataset.
    Description: Records validation rule results, rejection counts, and quality metrics
        for a dataset produced by a pipeline step. Complements Fabric's built-in pipeline
        monitoring (which tracks run status and timing) by capturing data-level quality
        that Fabric cannot see. Documents are stored in the pipeline-metadata container
        with 90-day TTL.

    Args:
    - cosmosDb (fn.FabricItem): The Cosmos DB connection information.
    - datasetId: Name of the dataset (e.g., "silver_products").
    - runId: Pipeline run identifier for correlating metadata across steps.
    - totalInput: Total rows read from source.
    - totalOutput: Total rows written to output.
    - rejected: Number of rows rejected by validation rules.
    - rulesResults: List of rule results, e.g. [{"ruleId": "S001", "name": "NonNull", "passed": True}].

    Returns:
    - dict[str, Any]: The upserted Cosmos DB document.
    '''

    COSMOS_DB_URI = "{my-cosmos-artifact-uri}"
    DB_NAME = "{my-cosmos-artifact-name}"
    CONTAINER_NAME = "pipeline-metadata"

    try:
        cosmosClient = get_cosmos_client(cosmosDb, COSMOS_DB_URI)
        container = cosmosClient.get_database_client(DB_NAME).get_container_client(CONTAINER_NAME)

        doc = {
            "id": f"dq-{runId}-{datasetId}",
            "type": "DataQuality",
            "datasetId": datasetId,
            "runId": runId,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "summary": {
                "totalRowsInput": totalInput,
                "totalRowsOutput": totalOutput,
                "rowsRejected": rejected,
                "rejectionRate": round(rejected / max(totalInput, 1), 4)
            },
            "rules": rulesResults,
            "ttl": 7776000  # 90 days
        }
        return container.upsert_item(doc)

    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Cosmos error in log_data_quality: {e}")
        raise
    except Exception as e:
        logging.error(f"Unexpected error in log_data_quality: {e}")
        raise


@udf.generic_connection(argName="cosmosDb", audienceType="CosmosDB")
@udf.function()
def log_dataset_profile(cosmosDb: fn.FabricItem, datasetId: str, runId: str,
                        rowCount: int, columnProfiles: list[dict[str, Any]],
                        notes: str) -> dict[str, Any]:

    '''
    Summary: Log statistical profile of a dataset.
    Description: Records row counts, column-level statistics (null rates, value distributions),
        and optional notes for a dataset produced by a pipeline step. Enables tracking of
        dataset evolution over time — something Fabric's built-in monitoring cannot provide.
        Documents are stored in the pipeline-metadata container with 90-day TTL.

    Args:
    - cosmosDb (fn.FabricItem): The Cosmos DB connection information.
    - datasetId: Name of the dataset (e.g., "dim_products").
    - runId: Pipeline run identifier for correlating metadata across steps.
    - rowCount: Total number of rows in the dataset.
    - columnProfiles: List of column stats, e.g. [{"column": "price", "nullRate": 0.0, "min": 9.99}].
    - notes: Optional free-text notes about this dataset snapshot.

    Returns:
    - dict[str, Any]: The upserted Cosmos DB document.
    '''

    COSMOS_DB_URI = "{my-cosmos-artifact-uri}"
    DB_NAME = "{my-cosmos-artifact-name}"
    CONTAINER_NAME = "pipeline-metadata"

    try:
        cosmosClient = get_cosmos_client(cosmosDb, COSMOS_DB_URI)
        container = cosmosClient.get_database_client(DB_NAME).get_container_client(CONTAINER_NAME)

        doc = {
            "id": f"prof-{runId}-{datasetId}",
            "type": "DatasetProfile",
            "datasetId": datasetId,
            "runId": runId,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "rowCount": rowCount,
            "columns": columnProfiles,
            "notes": notes or None,
            "ttl": 7776000  # 90 days
        }
        return container.upsert_item(doc)

    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Cosmos error in log_dataset_profile: {e}")
        raise
    except Exception as e:
        logging.error(f"Unexpected error in log_dataset_profile: {e}")
        raise


@udf.generic_connection(argName="cosmosDb", audienceType="CosmosDB")
@udf.function()
def log_transform_lineage(cosmosDb: fn.FabricItem, datasetId: str, runId: str,
                          sourceDatasets: list[str], transforms: list[str],
                          columnsAdded: list[str]) -> dict[str, Any]:

    '''
    Summary: Log transform lineage for a dataset.
    Description: Records which source datasets, transforms, and column derivations
        produced a given output dataset. Provides column-level lineage that Fabric's
        built-in monitoring (which only tracks activity-level dependencies) cannot see.
        Documents are stored in the pipeline-metadata container with 90-day TTL.

        Before running this function, go to Library Management and add the azure-cosmos
        package, version 4.14.0 or later.

    Args:
    - cosmosDb (fn.FabricItem): The Cosmos DB connection information.
    - datasetId: Name of the output dataset (e.g., "product-insights").
    - runId: Pipeline run identifier for correlating metadata across steps.
    - sourceDatasets: List of input dataset names (e.g., ["silver_products", "silver_reviews"]).
    - transforms: List of transform descriptions (e.g., ["filter(docType='product')", "add_price_change_pct"]).
    - columnsAdded: List of columns added/derived by the transforms.

    Returns:
    - dict[str, Any]: The upserted Cosmos DB document.
    '''

    COSMOS_DB_URI = "{my-cosmos-artifact-uri}"
    DB_NAME = "{my-cosmos-artifact-name}"
    CONTAINER_NAME = "pipeline-metadata"

    try:
        cosmosClient = get_cosmos_client(cosmosDb, COSMOS_DB_URI)
        container = cosmosClient.get_database_client(DB_NAME).get_container_client(CONTAINER_NAME)

        doc = {
            "id": f"lin-{runId}-{datasetId}",
            "type": "TransformLineage",
            "datasetId": datasetId,
            "runId": runId,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "sourceDatasets": sourceDatasets,
            "transforms": transforms,
            "columnsAdded": columnsAdded,
            "ttl": 7776000  # 90 days
        }
        return container.upsert_item(doc)

    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Cosmos error in log_transform_lineage: {e}")
        raise
    except Exception as e:
        logging.error(f"Unexpected error in log_transform_lineage: {e}")
        raise


@udf.generic_connection(argName="cosmosDb", audienceType="CosmosDB")
@udf.function()
def summarize_pipeline_run(cosmosDb: fn.FabricItem, runId: str) -> dict[str, Any]:

    '''
    Summary: Generate a pipeline run summary from metastore data.
    Description: Reads all DataQuality, DatasetProfile, and TransformLineage documents for a
        given pipeline run, then writes a consolidated RunSummary document back to Cosmos DB.
        Designed to be called as a Functions activity in a Fabric Data Pipeline (not from a
        notebook) — the pipeline passes the run_id as a dynamic parameter. The returned summary
        includes total datasets processed, overall quality score, and the full lineage chain.

        This function demonstrates the pipeline Functions activity pattern: the pipeline
        orchestrator calls a User Data Function directly, passing @pipeline().parameters.run_id
        as input and optionally consuming the output in downstream activities.

        Before running this function, go to Library Management and add the azure-cosmos
        package, version 4.14.0 or later.

    Args:
    - cosmosDb (fn.FabricItem): The Cosmos DB connection information.
    - runId: Pipeline run identifier (passed via pipeline parameter expression).

    Returns:
    - dict[str, Any]: The consolidated RunSummary document written to Cosmos DB.
    '''

    COSMOS_DB_URI = "{my-cosmos-artifact-uri}"
    DB_NAME = "{my-cosmos-artifact-name}"
    CONTAINER_NAME = "pipeline-metadata"

    try:
        cosmosClient = get_cosmos_client(cosmosDb, COSMOS_DB_URI)
        container = cosmosClient.get_database_client(DB_NAME).get_container_client(CONTAINER_NAME)

        # Query all metadata documents for this run across all partitions
        quality_docs = list(container.query_items(
            query="SELECT * FROM c WHERE c.type = 'DataQuality' AND c.runId = @runId",
            parameters=[{"name": "@runId", "value": runId}],
            enable_cross_partition_query=True
        ))

        profile_docs = list(container.query_items(
            query="SELECT * FROM c WHERE c.type = 'DatasetProfile' AND c.runId = @runId",
            parameters=[{"name": "@runId", "value": runId}],
            enable_cross_partition_query=True
        ))

        lineage_docs = list(container.query_items(
            query="SELECT * FROM c WHERE c.type = 'TransformLineage' AND c.runId = @runId",
            parameters=[{"name": "@runId", "value": runId}],
            enable_cross_partition_query=True
        ))

        # Compute overall quality metrics
        total_input = sum(d["summary"]["totalRowsInput"] for d in quality_docs)
        total_rejected = sum(d["summary"]["rowsRejected"] for d in quality_docs)
        datasets_with_issues = [d["datasetId"] for d in quality_docs if d["summary"]["rowsRejected"] > 0]

        # Build the lineage chain (dataset → sources)
        lineage_chain = {
            d["datasetId"]: d["sourceDatasets"] for d in lineage_docs
        }

        # Build the summary document
        summary = {
            "id": f"summary-{runId}",
            "type": "RunSummary",
            "datasetId": "_pipeline",  # partition key — special value for pipeline-level docs
            "runId": runId,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "datasetsProcessed": len(set(
                [d["datasetId"] for d in quality_docs] +
                [d["datasetId"] for d in profile_docs]
            )),
            "qualityOverview": {
                "totalRowsProcessed": total_input,
                "totalRowsRejected": total_rejected,
                "overallRejectionRate": round(total_rejected / max(total_input, 1), 4),
                "datasetsWithIssues": datasets_with_issues,
            },
            "datasetProfiles": {
                d["datasetId"]: {"rowCount": d["rowCount"]}
                for d in profile_docs
            },
            "lineageChain": lineage_chain,
            "ttl": 7776000  # 90 days
        }

        return container.upsert_item(summary)

    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Cosmos error in summarize_pipeline_run: {e}")
        raise
    except Exception as e:
        logging.error(f"Unexpected error in summarize_pipeline_run: {e}")
        raise
