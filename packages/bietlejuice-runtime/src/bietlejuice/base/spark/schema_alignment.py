"""
Align a source DataFrame's column types to an existing Delta table's schema.

Raw JSON tables are registered on Glue with their ``timestamp`` and ``date``
columns typed as ``string``: the OpenX JsonSerDe parses those with
``Timestamp.valueOf`` / ``Date.valueOf``, which reject the ISO-8601 ``T``
separator and ``Z`` suffix our producers emit, and OpenX exposes no
``timestamp.formats`` property to configure around it.  The clean-layer Delta
tables were created before that coercion and still hold the real types, so a
consumer reading raw and writing clean now hands Spark a ``string`` where the
target holds a ``timestamp``.

Neither write path tolerates that.  ``MERGE`` with
``spark.databricks.delta.schema.autoMerge.enabled`` plus ``whenMatchedUpdateAll``
/ ``whenNotMatchedInsertAll`` aborts on the mismatch rather than casting, and an
overwrite with ``overwriteSchema`` would succeed by *replacing* the target's
``timestamp`` with ``string`` — silently degrading every downstream reader.

Deliberately narrow: only ``string`` -> ``timestamp`` / ``date`` is aligned,
because that is the only divergence the Glue JSON registration introduces.  Any
other mismatch (a genuinely wrong type, a widened decimal, a reshaped struct) is
left to Delta schema evolution or to a human, so this never quietly reshapes
data it was not written to handle.  Top-level columns only — a ``string`` field
nested inside a ``struct`` is not rewritten.
"""

from __future__ import annotations

from typing import Dict, List, Tuple

from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DataType,
    DateType,
    StringType,
    StructType,
    TimestampNTZType,
    TimestampType,
)
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("SchemaAlignment")

# Spark conf that disables the post-cast null audit. The audit costs one extra
# aggregation over the source, which is worth it by default (ANSI mode is off,
# so a bad cast yields NULL instead of raising) but is opt-out for hot jobs.
AUDIT_NULLS_CONF = "spark.bietlejuice.schemaAlignment.auditNulls"

# Target types worth aligning a ``string`` source column to. These are exactly
# the types coerce_glue_type_for_json registers as ``string``.
_ALIGNABLE_TARGET_TYPES = (DateType, TimestampType, TimestampNTZType)

AlignmentPlan = List[Tuple[str, DataType]]


def _quoted(column_name: str) -> str:
    """Backtick-quote a column name so dots in the name are not path syntax.

    Raw JSON columns really do contain dots (e.g.
    ``hra_eval_steps.action_performed_date.1``), and ``F.col("a.b")`` would read
    that as field ``b`` of struct ``a``.
    """
    escaped = column_name.replace("`", "``")
    return f"`{escaped}`"


def plan_alignment(
    source_schema: StructType, target_schema: StructType
) -> AlignmentPlan:
    """Return the ``(source_column, target_type)`` casts needed before writing.

    A column is included only when it is ``string`` in the source, present in
    the target, and ``timestamp`` / ``date`` there. Names are matched
    case-insensitively because Glue lower-cases column names while Delta keeps
    the registered spelling.

    Pure: takes two ``StructType``s, needs no ``SparkSession``.

    :param source_schema: schema of the DataFrame about to be written
    :param target_schema: schema of the existing Delta table
    :return: casts to apply, in source column order
    """
    target_by_name: Dict[str, DataType] = {}
    for field in (target_schema or StructType()).fields:
        # First spelling wins; a target with case-colliding columns is already
        # unreadable by Glue, and guessing which one is meant would be worse.
        target_by_name.setdefault(field.name.lower(), field.dataType)

    seen = set()
    ambiguous = set()
    for field in (source_schema or StructType()).fields:
        lowered = field.name.lower()
        if lowered in seen:
            ambiguous.add(lowered)
        seen.add(lowered)

    plan: AlignmentPlan = []
    for field in (source_schema or StructType()).fields:
        lowered = field.name.lower()
        if lowered in ambiguous:
            logger.warning(
                f"m=plan_alignment, column={field.name}, "
                "msg=source has case-colliding columns, skipping alignment"
            )
            continue
        if not isinstance(field.dataType, StringType):
            continue
        target_type = target_by_name.get(lowered)
        if target_type is None:
            continue
        if not isinstance(target_type, _ALIGNABLE_TARGET_TYPES):
            continue
        plan.append((field.name, target_type))
    return plan


def apply_alignment(source_df: DataFrame, plan: AlignmentPlan) -> DataFrame:
    """Cast the planned columns to their target types in a single projection."""
    if not plan:
        return source_df
    return source_df.withColumns(
        {name: F.col(_quoted(name)).cast(target_type) for name, target_type in plan}
    )


def audit_alignment_nulls(source_df: DataFrame, plan: AlignmentPlan) -> Dict[str, int]:
    """Count values each cast would turn from non-null into ``NULL``.

    Spark runs with ANSI mode off, so an unparseable value casts to ``NULL``
    instead of raising — exactly the silent data loss worth reporting. Counted
    in one aggregation over the source (not one per column) so the cost is a
    single extra pass regardless of how many columns are aligned.

    :return: ``{column: null_delta}`` for every aligned column, zeros included
    """
    if not plan:
        return {}
    aggregations = [
        F.count(
            F.when(
                F.col(_quoted(name)).isNotNull()
                & F.col(_quoted(name)).cast(target_type).isNull(),
                F.lit(1),
            )
        ).alias(f"align_null_delta_{index}")
        for index, (name, target_type) in enumerate(plan)
    ]
    row = source_df.agg(*aggregations).head()
    if row is None:
        return {name: 0 for name, _ in plan}
    return {name: int(row[index] or 0) for index, (name, _) in enumerate(plan)}


def align_source_to_target(
    spark, source_df: DataFrame, table_name: str, *, audit_nulls: bool = True
) -> DataFrame:
    """Cast ``source_df`` columns to the types ``table_name`` already declares.

    Returns ``source_df`` unchanged when nothing needs aligning, when the target
    schema cannot be read, or when the cast itself fails: a load must never
    break because this optimisation could not run.

    :param spark: active SparkSession, used to read the target schema
    :param source_df: DataFrame about to be written to ``table_name``
    :param table_name: fully-qualified existing Delta table
    :param audit_nulls: count values the casts turn into ``NULL`` and log them
    """
    try:
        target_schema = spark.read.table(table_name).schema
        plan = plan_alignment(source_df.schema, target_schema)
    except Exception as exc:
        logger.warning(
            f"m=align_source_to_target, table={table_name}, error={exc}, "
            "msg=could not read target schema, writing source types unchanged"
        )
        return source_df

    if not plan:
        logger.info(
            f"m=align_source_to_target, table={table_name}, aligned_count=0, "
            "msg=no string column maps to a timestamp/date target"
        )
        return source_df

    columns = ", ".join(f"{name}->{target.simpleString()}" for name, target in plan)
    logger.info(
        f"m=align_source_to_target, table={table_name}, "
        f"aligned_count={len(plan)}, aligned={columns}, "
        "msg=casting string columns to target Delta types"
    )

    try:
        aligned_df = apply_alignment(source_df, plan)
    except Exception as exc:
        logger.error(
            f"m=align_source_to_target, table={table_name}, error={exc}, "
            "msg=cast failed, writing source types unchanged"
        )
        return source_df

    if audit_nulls and _audit_enabled(spark):
        _log_null_audit(source_df, table_name, plan)

    return aligned_df


def _audit_enabled(spark) -> bool:
    try:
        return str(spark.conf.get(AUDIT_NULLS_CONF, "true")).lower() != "false"
    except Exception:
        return True


def _log_null_audit(source_df: DataFrame, table_name: str, plan: AlignmentPlan) -> None:
    """Log the null delta per aligned column; never fail the load."""
    try:
        null_deltas = audit_alignment_nulls(source_df, plan)
    except Exception as exc:
        logger.warning(
            f"m=align_source_to_target, table={table_name}, error={exc}, "
            "msg=null audit failed, proceeding with the aligned write"
        )
        return

    lossy = {name: count for name, count in null_deltas.items() if count}
    if lossy:
        logger.error(
            f"m=align_source_to_target, table={table_name}, "
            f"null_deltas={lossy}, "
            "msg=cast produced NULLs from non-null values; values were unparseable"
        )
    else:
        logger.info(
            f"m=align_source_to_target, table={table_name}, "
            f"audited_columns={len(null_deltas)}, null_deltas=0, "
            "msg=all aligned values parsed cleanly"
        )
