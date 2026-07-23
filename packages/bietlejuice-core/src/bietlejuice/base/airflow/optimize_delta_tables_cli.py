"""CLI argument encoding for optimize_delta_table Spark job (EMR-safe).

Lives under base.airflow (not base.spark) so importing task creators does not
execute spark/__init__.py, which initializes PySpark and breaks Airflow DAG parsing.
"""

from __future__ import annotations

import base64
import json
from typing import Any, Callable, Dict, List, Sequence

# Prefix must stay in sync with OptimizeDeltaTableTaskCreator (EMR path only).
EMR_TABLES_B64_PREFIX = "B64:"

# AWS EMR AddJobFlowSteps HadoopJarStep.Args per-element length limit.
EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH = 10280


def encode_tables_json_for_emr_cli(tables_json: str) -> str:
    """Wrap JSON so EMR/YARN spark-submit does not split or mangle a multi-token string."""
    return EMR_TABLES_B64_PREFIX + base64.standard_b64encode(
        tables_json.encode("utf-8")
    ).decode("ascii")


def decode_tables_config_from_cli(tables_arg: str) -> Dict[str, Any]:
    """Inverse of encode_tables_json_for_emr_cli; accepts raw JSON (Databricks) or B64:… (EMR)."""
    stripped = tables_arg.strip()
    if stripped.startswith(EMR_TABLES_B64_PREFIX):
        raw = base64.standard_b64decode(
            stripped[len(EMR_TABLES_B64_PREFIX) :].encode("ascii")
        )
        return json.loads(raw.decode("utf-8"))
    return json.loads(stripped)


def build_and_validate_emr_tables_cli_arg(tables_config: Dict[str, Any]) -> str:
    """Encode tables config for EMR spark-submit and validate integrity at DAG parse time.

    Ensures the argument fits the EMR per-arg length limit and round-trips through
    decode without mutation (no truncated JSON or partial table entries).
    """
    tables_json = json.dumps(tables_config, separators=(",", ":"))
    encoded = encode_tables_json_for_emr_cli(tables_json)
    if len(encoded) > EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH:
        table_names = ", ".join(sorted(tables_config))
        raise ValueError(
            "Encoded optimize tables config exceeds EMR AddJobFlowSteps arg limit "
            f"({len(encoded)} > {EMR_HADOOP_JAR_STEP_ARG_MAX_LENGTH} characters) "
            f"for tables: {table_names}"
        )
    decoded = decode_tables_config_from_cli(encoded)
    if decoded != tables_config:
        raise ValueError("Encoded optimize tables config failed round-trip validation")
    return encoded


def assert_optimize_batches_partition_tables(
    table_attributes: Sequence[Any],
    chunks: Sequence[Sequence[Any]],
) -> None:
    """Verify batching covers every table exactly once, in original order."""
    original_names = [table.table_name for table in table_attributes]
    batched_names: List[str] = []
    for chunk in chunks:
        batched_names.extend(table.table_name for table in chunk)
    if batched_names != original_names:
        raise ValueError(
            "Optimize table batching must partition tables without loss, "
            f"duplication, or reordering; expected {original_names!r}, "
            f"got {batched_names!r}"
        )


def _chunk_items(items: Sequence[Any], batch_size: int) -> List[List[Any]]:
    if batch_size < 1:
        raise ValueError("batch_size must be at least 1")
    return [list(items[i : i + batch_size]) for i in range(0, len(items), batch_size)]


def _all_fixed_batches_fit_emr_limit(
    table_attributes: Sequence[Any],
    batch_size: int,
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
) -> bool:
    for chunk in _chunk_items(table_attributes, batch_size):
        try:
            build_and_validate_emr_tables_cli_arg(build_tables_config(chunk))
        except ValueError:
            return False
    return True


def _validate_single_table_emr_limit(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
) -> None:
    for table in table_attributes:
        tables_config = build_tables_config([table])
        try:
            build_and_validate_emr_tables_cli_arg(tables_config)
        except ValueError as exc:
            raise ValueError(
                f"Table {table.table_name!r} optimize config exceeds EMR arg limit "
                "and cannot be batched"
            ) from exc


def max_tables_per_emr_optimize_batch(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
) -> int:
    """Return the largest fixed batch size where every equal-sized chunk fits.

    Per-table payload sizes vary, so validity is **not** monotonic in batch size
    (a failing size-2 boundary can disappear at size 3). Scan downward from ``n``
    instead of binary search. Prefer :func:`chunk_table_attributes_for_emr_limit`
    for EMR auto-batching — greedy packing minimizes steps.
    """
    n = len(table_attributes)
    if n == 0:
        return 1

    _validate_single_table_emr_limit(table_attributes, build_tables_config)

    for batch_size in range(n, 0, -1):
        if _all_fixed_batches_fit_emr_limit(
            table_attributes, batch_size, build_tables_config
        ):
            return batch_size

    raise ValueError(
        "No EMR-safe optimize batch size found; at least one table exceeds "
        "the AddJobFlowSteps arg limit"
    )


def chunk_table_attributes_for_emr_limit(
    table_attributes: Sequence[Any],
    build_tables_config: Callable[[Sequence[Any]], Dict[str, Any]],
) -> List[List[Any]]:
    """Greedy first-fit chunking: pack tables in order until the next one overflows."""
    if not table_attributes:
        return []

    _validate_single_table_emr_limit(table_attributes, build_tables_config)

    chunks: List[List[Any]] = []
    current: List[Any] = []

    for table in table_attributes:
        candidate = current + [table]
        try:
            build_and_validate_emr_tables_cli_arg(build_tables_config(candidate))
        except ValueError:
            if not current:
                raise ValueError(
                    f"Table {table.table_name!r} optimize config exceeds EMR arg "
                    "limit and cannot be batched"
                ) from None
            chunks.append(current)
            current = [table]
            build_and_validate_emr_tables_cli_arg(build_tables_config(current))
        else:
            current = candidate

    if current:
        chunks.append(current)
    return chunks
