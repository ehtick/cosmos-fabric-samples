import fabric.functions as fn
import logging
from datetime import datetime, timezone
from typing import Any
from azure.cosmos import CosmosClient

COSMOS_URI = "YOUR_COSMOS_DB_URI_HERE"
DB_NAME = "ClinicalTrialDB"
CONTAINER_NAME = "ClinicalTrialData"

udf = fn.UserDataFunctions()

@udf.connection(argName="cosmosClient", audienceType="CosmosDB", cosmos_endpoint=COSMOS_URI)
@udf.function()
def triage_adverse_event(
    cosmosClient: CosmosClient,
    trialId: str,
    eventId: str,
    eventType: str,
    reviewerName: str,
    decision: str,
    notes: str
) -> list[dict[str, Any]]:
    """
    Writes back a triage decision for an adverse event.

    The key differentiator from a SQL write-back: the follow-up protocol
    appended to reviewLog is shaped differently for each eventType.
    A relational database would require a wide nullable table or multiple
    junction tables to store these varying structures. Cosmos DB stores
    each naturally as a nested subdocument within the same container,
    with no schema migration required when new event types are introduced.

    Parameters:
        trialId     - Partition key (maps to the trialId field)
        eventId     - Document ID of the adverse event
        eventType   - Type of event: cardiac | neurological | allergic | lab_anomaly
        reviewerName - Name of the medical reviewer
        decision    - Triage decision: monitor | escalate | hold_drug | close
        notes       - Free-text reviewer notes
    """
    try:
        db = cosmosClient.get_database_client(DB_NAME)
        container = db.get_container_client(CONTAINER_NAME)

        # Build the type-specific follow-up protocol.
        # This is the schema-agnostic core of the sample: each eventType
        # produces a structurally different subdocument. There is no
        # single fixed schema — Cosmos DB stores whatever shape is needed.
        follow_up_protocol = _build_follow_up_protocol(eventType, decision)

        # Construct the full review entry to append
        review_entry = {
            "reviewedBy": reviewerName,
            "reviewedAt": datetime.now(timezone.utc).isoformat(),
            "decision": decision,
            "notes": notes,
            "followUpProtocol": follow_up_protocol
        }

        # Use Cosmos DB Partial Document Update (patch) to APPEND to the
        # reviewLog array without reading or replacing the entire document.
        # SQL has no equivalent atomic array-append operation.
        patch_operations = [
            {"op": "add", "path": "/reviewLog/-", "value": review_entry},
            {"op": "replace", "path": "/status", "value": _map_decision_to_status(decision)}
        ]

        updated = container.patch_item(
            item=eventId,
            partition_key=trialId,
            patch_operations=patch_operations
        )

        logging.info(f"Triage write-back successful for event {eventId} (type: {eventType})")

        return [{
            "eventId": updated["id"],
            "status": updated["status"],
            "reviewCount": len(updated.get("reviewLog", [])),
            "lastReviewedBy": reviewerName,
            "lastDecision": decision
        }]

    except Exception as e:
        logging.error(f"Error triaging event {eventId}: {str(e)}")
        raise


def _build_follow_up_protocol(event_type: str, decision: str) -> dict[str, Any]:
    """
    Returns a type-specific follow-up protocol subdocument.

    Each branch returns a completely different structure — this is the
    schema-agnostic behavior that differentiates Cosmos DB from SQL.
    Adding a new event type here requires zero database schema changes.
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    if event_type == "cardiac":
        return {
            "type": "cardiac_follow_up",
            "ecgRepeatRequired": decision in ["escalate", "monitor"],
            "cardiologyReferral": decision == "escalate",
            "troponinRepeatDays": 2 if decision == "escalate" else 7,
            "activityRestriction": decision in ["escalate", "hold_drug"],
            "scheduledFollowUpDate": today,
            "holdStudyDrug": decision == "hold_drug"
        }

    elif event_type == "neurological":
        return {
            "type": "neurological_follow_up",
            "neurologistReferral": decision == "escalate",
            "mriRequired": decision in ["escalate", "monitor"],
            "nihssMonitoring": decision == "escalate",
            "gcsMonitoringFrequencyHours": 4 if decision == "escalate" else 24,
            "seizurePrecautions": decision == "escalate",
            "holdStudyDrug": decision in ["escalate", "hold_drug"]
        }

    elif event_type == "allergic":
        return {
            "type": "allergic_follow_up",
            "allergySpecialistReferral": decision == "escalate",
            "epiPenPrescribed": decision in ["escalate", "monitor"],
            "skinTestRequired": decision in ["escalate", "monitor"],
            "rechallengeForbidden": decision in ["escalate", "hold_drug"],
            "antihistamineContinued": True,
            "holdStudyDrug": decision in ["escalate", "hold_drug"],
            "safetyReportingRequired": decision == "escalate"
        }

    elif event_type == "lab_anomaly":
        return {
            "type": "lab_follow_up",
            "repeatLabDays": 3 if decision == "escalate" else 7,
            "additionalPanelsRequired": decision == "escalate",
            "hepatologyReferral": decision == "escalate",
            "doseReduction": decision == "monitor",
            "holdStudyDrug": decision == "hold_drug",
            "fastingRequired": True,
            "patientDietaryGuidance": decision in ["escalate", "monitor"]
        }

    else:
        # Graceful fallback for future event types — no schema change needed
        return {
            "type": "general_follow_up",
            "scheduledFollowUpDate": today,
            "holdStudyDrug": decision == "hold_drug"
        }


def _map_decision_to_status(decision: str) -> str:
    return {
        "monitor":    "under_review",
        "escalate":   "escalated",
        "hold_drug":  "drug_hold",
        "close":      "closed"
    }.get(decision, "under_review")
