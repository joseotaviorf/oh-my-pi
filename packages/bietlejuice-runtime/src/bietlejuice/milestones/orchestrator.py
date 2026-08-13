"""Orchestrate milestone strategies into incremental merge batches for one table."""

from __future__ import annotations

from typing import Any, Callable, Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.milestones.contract import (
    MilestoneRunContext,
    MilestoneTableSpec,
    build_scan_predicate,
)
from bietlejuice.milestones.merge import aggregate_events, prepare_merge_batch
from bietlejuice.milestones.registry import resolve_milestones_for_run
from bietlejuice.milestones.sql_runner import run_sql_strategy

logger = QuintoAndarLogger("load_milestone_dimension.orchestrator")


def dim_schema(spec: MilestoneTableSpec) -> StructType:
    """Build an empty-dim schema for the configured grain + sticky carries."""
    fields: List[StructField] = [
        StructField(key, LongType(), False) for key in spec.entity_keys
    ]
    for sticky in spec.sticky_columns:
        fields.append(StructField(sticky, LongType(), True))
    fields.extend(
        [
            StructField("milestone_type", StringType(), False),
            StructField("ts_first", TimestampType(), False),
            StructField("ts_last", TimestampType(), False),
            StructField("sk_entity_first", LongType(), True),
            StructField("sk_entity_last", LongType(), True),
            StructField("entity_type", StringType(), True),
            StructField("ts_row_updated", TimestampType(), False),
        ]
    )
    return StructType(fields)


def empty_dim_df(spark_session: SparkSession, spec: MilestoneTableSpec) -> DataFrame:
    return spark_session.createDataFrame([], dim_schema(spec))


def read_existing_milestone(
    spark_session: SparkSession,
    full_table: str,
    milestone_type: str,
    spec: MilestoneTableSpec,
) -> DataFrame:
    """Load current dim rows for one milestone_type.

    First run (table absent) or unresolved relation → empty in-memory frame so
    watermark logic never runs ``agg`` against a missing table plan.
    """
    try:
        if not spark_session.catalog.tableExists(full_table):
            logger.info(
                "m=read_existing_milestone, table=%s, milestone_type=%s, "
                "msg=table missing; empty existing",
                full_table,
                milestone_type,
            )
            return empty_dim_df(spark_session, spec)
        existing = spark_session.table(full_table).filter(
            F.col("milestone_type") == F.lit(milestone_type)
        )
        _ = existing.schema
        return existing
    except AnalysisException:
        logger.info(
            "m=read_existing_milestone, table=%s, milestone_type=%s, "
            "msg=table unreadable; empty existing",
            full_table,
            milestone_type,
        )
        return empty_dim_df(spark_session, spec)


def _validate_event_columns(events: DataFrame, spec: MilestoneTableSpec) -> None:
    missing = [col for col in spec.required_event_columns if col not in events.columns]
    if missing:
        raise ValueError(
            f"m=_validate_event_columns, msg=Missing event columns: {missing}"
        )


def run_strategy(
    spark_session: SparkSession,
    defn: Dict[str, Any],
    ctx: MilestoneRunContext,
    strategies_root: str,
    dag_name: str,
    layer: str = "",
    table_name: str = "",
) -> DataFrame:
    return run_sql_strategy(
        spark_session,
        str(defn["sql_file"]),
        ctx,
        strategies_root,
        dag_name=dag_name,
        params=defn.get("params"),
        layer=layer,
        table_name=table_name,
    )


def build_merge_batch(
    events: DataFrame,
    existing: DataFrame,
    milestone_type: str,
    spec: MilestoneTableSpec,
    bootstrap: bool = False,
) -> DataFrame:
    _validate_event_columns(events, spec)
    aggregated = aggregate_events(events, spec).withColumn(
        "milestone_type", F.lit(milestone_type)
    )
    inserts, updates = prepare_merge_batch(
        existing, aggregated, spec, bootstrap=bootstrap
    )
    return inserts.unionByName(updates).withColumn(
        "ts_row_updated", F.current_timestamp()
    )


def process_milestone(
    spark_session: SparkSession,
    name: str,
    defn: Dict[str, Any],
    full_table: str,
    strategies_root: str,
    dag_name: str,
    spec: MilestoneTableSpec,
    strategy_runner: Callable[..., DataFrame] = run_strategy,
    layer: str = "",
    table_name: str = "",
) -> DataFrame:
    milestone_type = defn["milestone_type"]
    bootstrap = bool(defn["bootstrap"])
    existing = read_existing_milestone(spark_session, full_table, milestone_type, spec)
    scan_predicate = build_scan_predicate(
        existing,
        bootstrap=bootstrap,
        scan=defn.get("scan"),
    )
    ctx = MilestoneRunContext(
        milestone_type=milestone_type,
        scan_predicate=scan_predicate,
    )
    events = strategy_runner(
        spark_session,
        defn,
        ctx,
        strategies_root,
        dag_name,
        layer=layer,
        table_name=table_name,
    )
    batch = build_merge_batch(
        events, existing, milestone_type, spec, bootstrap=bootstrap
    )
    logger.info(
        "m=process_milestone, milestone=%s, milestone_type=%s, "
        "bootstrap=%s, scan_predicate=%s",
        name,
        milestone_type,
        bootstrap,
        scan_predicate,
    )
    return batch


def run_all_milestones(
    spark_session: SparkSession,
    registry: Dict[str, Dict[str, Any]],
    full_table: str,
    strategies_root: str,
    dag_name: str,
    spec: MilestoneTableSpec,
    strategy_runner: Callable[..., DataFrame] = run_strategy,
    milestones_to_run: Optional[list] = None,
    bootstrap_milestones: Optional[list] = None,
    layer: str = "",
    table_name: str = "",
) -> tuple[DataFrame, list]:
    """Run selected milestones for one target table; return merge batch + bootstrap types.

    All strategy SQLs contribute rows to the **same** ``full_table`` (entity keys ×
    milestone_type). Fail-fast: any strategy error aborts the whole load.
    """
    due = resolve_milestones_for_run(
        registry,
        milestones_to_run=milestones_to_run,
        bootstrap_milestones=bootstrap_milestones,
    )
    if not due:
        raise RuntimeError(
            "m=run_all_milestones, msg=No milestones selected for this run"
        )

    batches = []
    bootstrap_types: list = []
    for name, defn in due.items():
        batch = process_milestone(
            spark_session,
            name,
            defn,
            full_table,
            strategies_root,
            dag_name=dag_name,
            spec=spec,
            strategy_runner=strategy_runner,
            layer=layer,
            table_name=table_name,
        )
        batches.append(batch)
        if defn.get("bootstrap"):
            bootstrap_types.append(defn["milestone_type"])

    combined = batches[0]
    for extra in batches[1:]:
        # Strategies may omit optional entity columns; aggregate_events pads
        # them, but allowMissingColumns keeps unions resilient to schema drift.
        combined = combined.unionByName(extra, allowMissingColumns=True)
    return combined, bootstrap_types
