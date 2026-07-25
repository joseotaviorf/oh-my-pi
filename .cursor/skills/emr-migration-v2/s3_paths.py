"""S3 path conventions for migration metric exchange."""

from __future__ import annotations


def run_prefix(run_id: str) -> str:
    return f"emr-migration/runs/{run_id}"


def twin_metric_key(run_id: str, domain: str, dag_name: str, table_name: str) -> str:
    return f"{run_prefix(run_id)}/twin/{domain}/{dag_name}/{table_name}.json"


def emr_metric_key(run_id: str, domain: str, dag_name: str, table_name: str) -> str:
    return f"{run_prefix(run_id)}/emr/{domain}/{dag_name}/{table_name}.json"


def verdict_key(run_id: str, domain: str, dag_name: str, table_name: str) -> str:
    return f"{run_prefix(run_id)}/verdicts/{domain}/{dag_name}/{table_name}.json"


def summary_key(run_id: str, domain: str, dag_name: str) -> str:
    return f"{run_prefix(run_id)}/verdicts/{domain}/{dag_name}/summary.json"


def manifest_key(run_id: str) -> str:
    return f"{run_prefix(run_id)}/manifest.json"


def twin_dataset_uri(scope_id: str) -> str:
    return f"migration:twin-{scope_id}-complete"


def emr_dataset_uri(scope_id: str) -> str:
    return f"migration:emr-{scope_id}-complete"
