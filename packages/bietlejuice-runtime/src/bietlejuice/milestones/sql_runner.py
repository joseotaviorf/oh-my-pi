"""Run milestone SQL strategies against Spark with scan watermark."""

from __future__ import annotations

from os.path import join as path_join
from pathlib import Path
from typing import Any, Dict, Optional

from pyspark.sql import DataFrame, SparkSession

from bietlejuice.milestones.contract import MilestoneRunContext


def resolve_sql_path(strategies_root: str, sql_file: str) -> Path:
    """Resolve sql_file relative to the table milestones strategies directory."""
    path = Path(sql_file)
    if path.is_absolute():
        return path
    return Path(strategies_root) / path


def _apply_sql_params(sql_text: str, params: Optional[Dict[str, Any]]) -> str:
    """Replace ``{key}`` placeholders from registry params.

    String params are escaped for embedding inside SQL string literals.
    ``scan_predicate`` is a raw SQL fragment and is substituted without escaping.
    """
    if not params:
        return sql_text
    rendered = sql_text
    for key, value in params.items():
        token = "{" + str(key) + "}"
        if key == "scan_predicate":
            rendered = rendered.replace(token, str(value))
        else:
            escaped = str(value).replace("'", "''")
            rendered = rendered.replace(token, escaped)
    return rendered


def _load_sql_text(
    dag_name: str,
    sql_file: str,
    strategies_root: str,
    layer: str = "",
    table_name: str = "",
) -> str:
    """Read strategy SQL from local strategies tree, else DAG-package S3 path."""
    local = resolve_sql_path(strategies_root, sql_file)
    if local.is_file():
        return local.read_text(encoding="utf-8")

    if not (layer and table_name):
        raise FileNotFoundError(
            f"m=_load_sql_text, sql_file={sql_file}, strategies_root={strategies_root}, "
            "msg=strategy SQL not found locally and layer/table_name missing for S3 path"
        )

    from bietlejuice.base.service.dag_packages_path_service import (
        DAGPackagesPathService,
    )
    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    basename = Path(sql_file).name
    engine = "boto3" if RuntimeDetector.is_emr() else "databricks_volume"
    relative = path_join("queries", dag_name, layer, table_name, "milestones", basename)
    content = DAGPackagesPathService._read_dag_package_file_from_s3(
        sql_file_relative_path=relative,
        engine=engine,
    )
    if not content:
        raise FileNotFoundError(
            f"m=_load_sql_text, sql_file={sql_file}, relative={relative}, "
            "msg=strategy SQL not found locally or in packaged DAG path"
        )
    return content


def run_sql_strategy(
    spark: SparkSession,
    sql_file: str,
    ctx: MilestoneRunContext,
    strategies_root: str,
    dag_name: str,
    params: Optional[Dict[str, Any]] = None,
    layer: str = "",
    table_name: str = "",
) -> DataFrame:
    """Execute a milestone SQL file with ``{scan_predicate}`` substituted.

    SQL authors must include ``AND ({scan_predicate})`` in the WHERE clause.
    """
    sql_text = _load_sql_text(
        dag_name,
        sql_file,
        strategies_root,
        layer=layer,
        table_name=table_name,
    )
    merged_params: Dict[str, Any] = dict(params or {})
    merged_params["scan_predicate"] = ctx.scan_predicate
    sql_text = _apply_sql_params(sql_text, merged_params)
    if "{scan_predicate}" in sql_text:
        raise ValueError(
            f"m=run_sql_strategy, sql_file={sql_file}, "
            "msg=scan_predicate placeholder not replaced"
        )
    return spark.sql(sql_text)
