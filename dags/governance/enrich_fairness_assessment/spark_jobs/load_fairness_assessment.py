"""
Spark job: FAIR assessment — ``tables_documentation`` + ``columns_documentation`` + ``org_chart``;
Spark catalog / field names, DataHub GraphQL; writes enrich Delta.

Business rules live in :mod:`bietlejuice.governance.fairness_assessment`; this module is
orchestration and PySpark I/O. PySpark imports stay in ``main()`` and ``_eval_partition`` so the
bietlejuice package under test does not need the JVM.
"""

from __future__ import annotations

import argparse
import ast
import json
import os
from datetime import datetime, timezone
from typing import Any, Mapping, Optional

from bietlejuice.governance.fairness_assessment.adapters.spark_catalog import (
    resolve_spark_physical_field_names_lower,
    resolve_spark_table_exists_map,
)
from bietlejuice.governance.fairness_assessment.constants import (
    COLUMNS_DOC,
    JOB_NAME,
    ORG_CHART,
    TABLES_DOC,
    TIERING_RULES_VERSION,
    graphql_url_for_environment,
)
from bietlejuice.governance.fairness_assessment.datahub_graphql import (  # noqa: E501
    compute_f4_pass_and_reason_by_fqn,
    compute_has_data_contract_by_fqn,
    compute_i3_lineage_pass_and_totals_by_fqn,
    compute_i3_ownership_pass_by_fqn,
    resolve_datahub_urn_flags,
)
from bietlejuice.governance.fairness_assessment.checks.evaluation import (  # noqa: E501
    evaluate_mvp_checks_from_row,
)
from bietlejuice.governance.fairness_assessment.description_quality import (  # noqa: E501
    assess_table_description_quality,
)
from bietlejuice.governance.fairness_assessment.schema_validation import (  # noqa: E501
    compute_f2_02_and_i1_01_for_fqn,
)
from bietlejuice.governance.fairness_assessment.tiering import (  # noqa: E501
    compute_tier_mvp,
    tier_achieved_to_classification,
)


def _build_fairness_enrich_output_dict(d: Mapping[str, Any]) -> dict[str, Any]:
    """ETL-coupled row shape: map one joined input row to Delta column values (no PySpark)."""
    desc_quality = assess_table_description_quality(
        d.get("database_name"),
        d.get("table_name"),
        d.get("table_description"),
    )
    checks = evaluate_mvp_checks_from_row(d)
    tier = compute_tier_mvp(checks)
    checks_payload: dict[str, Any] = {
        k: {"passed": v.passed, "reason": v.reason} for k, v in checks.items()
    }
    if "I3-02" in checks_payload and d.get("datahub_lineage_upstream_total") is not None:
        checks_payload["I3-02"]["detail"] = {
            "upstream_total": int(d.get("datahub_lineage_upstream_total") or 0),
            "downstream_total": int(d.get("datahub_lineage_downstream_total") or 0),
        }
    if "I1-01" in checks_payload and d.get("i1_01_undocumented_json") is not None:
        raw = d.get("i1_01_undocumented_json") or ""
        if raw:
            try:
                uj: Any = json.loads(raw)
            except (json.JSONDecodeError, TypeError, ValueError):
                uj = None
            if uj is not None:
                detail: dict[str, Any] = {}
                if isinstance(uj, list) and uj:
                    detail["undocumented_column_names"] = uj
                elif isinstance(uj, dict):
                    bus = uj.get("undocumented_business_names") or []
                    part = uj.get("undocumented_partition_names") or []
                    warns = uj.get("warnings")
                    if bus:
                        detail["undocumented_column_names"] = bus
                    if part:
                        detail["undocumented_partition_column_names"] = part
                    if warns:
                        detail["warnings"] = warns
                if detail:
                    checks_payload["I1-01"]["detail"] = detail
    ts = datetime.now(timezone.utc)
    return {
        "database_name": d.get("database_name"),
        "table_name": d.get("table_name"),
        "checks_result_json": json.dumps(checks_payload),
        "tier_achieved": tier.tier_achieved,
        "fqn_occurrence_count": int(d.get("fqn_occurrence_count") or 0),
        "is_active_employee": bool(d.get("is_active_employee")),
        "has_data_contract": bool(d.get("has_data_contract")),
        "table_description_is_substantive": bool(desc_quality.is_substantive),
        "columns_description_is_substantive": bool(
            d.get("columns_description_is_substantive")
        ),
        "tiering_rules_version": TIERING_RULES_VERSION,
        "ts_assessed": ts,
        "year": int(d["year"]) if d.get("year") is not None else None,
        "month": int(d["month"]) if d.get("month") is not None else None,
        "day": int(d["day"]) if d.get("day") is not None else None,
    }


def _eval_partition(row: Any) -> Any:
    from pyspark.sql import Row

    d = row.asDict()
    payload = _build_fairness_enrich_output_dict(d)
    return Row(**payload)


def _build_column_descriptions_by_fqn_from_collected_rows(
    rows: list[Any],
) -> dict[tuple[str, str], dict[str, Optional[str]]]:
    """Driver: ``columns_documentation`` rows from ``collect()`` → FQN → column_name → description."""
    m: dict[tuple[str, str], dict[str, Optional[str]]] = {}
    for r in rows:
        db, tbl = r["database_name"], r["table_name"]
        if db is None or tbl is None:
            continue
        db_s, tb_s = str(db).strip(), str(tbl).strip()
        if not db_s or not tb_s:
            continue
        col = r.get("column_name")
        if col is None or not str(col).strip():
            continue
        cname = str(col).strip()
        key = (db_s, tb_s)
        m.setdefault(key, {})[cname] = r.get("column_description")
    return m


def main() -> None:
    from pyspark.sql import functions as F
    from pyspark.sql.types import (
        BooleanType,
        IntegerType,
        LongType,
        StringType,
        StructField,
        StructType,
        TimestampType,
    )
    from pyspark.sql.window import Window
    from quintoandar_logger import QuintoAndarLogger

    from bietlejuice.base.db import DatalakeMetastoreService
    from bietlejuice.base.spark import BaseDBUtils, BaseSparkContext
    from bietlejuice.loaders.delta_loader import DeltaLoader

    def parse_args() -> argparse.Namespace:
        logger = QuintoAndarLogger(JOB_NAME)
        parser = argparse.ArgumentParser(JOB_NAME)
        parser.add_argument("environment")
        parser.add_argument("datalake_bucket")
        parser.add_argument("schema")
        parser.add_argument("table_name")
        parser.add_argument("load_start_date")
        parser.add_argument("load_end_date")
        parser.add_argument("partitions")
        parser.add_argument("dag_name")
        args = parser.parse_args()
        logger.info(
            f"m=parse_args,environment={args.environment},schema={args.schema},"
            f"table_name={args.table_name},load_start_date={args.load_start_date},"
            f"load_end_date={args.load_end_date}"
        )
        return args

    def _output_schema() -> StructType:
        return StructType(
            [
                StructField("database_name", StringType(), True),
                StructField("table_name", StringType(), True),
                StructField("checks_result_json", StringType(), True),
                StructField("tier_achieved", IntegerType(), True),
                StructField("fqn_occurrence_count", IntegerType(), True),
                StructField("is_active_employee", BooleanType(), True),
                StructField("has_data_contract", BooleanType(), True),
                StructField("table_description_is_substantive", BooleanType(), True),
                StructField("columns_description_is_substantive", BooleanType(), True),
                StructField("tiering_rules_version", StringType(), True),
                StructField("ts_assessed", TimestampType(), True),
                StructField("year", IntegerType(), True),
                StructField("month", IntegerType(), True),
                StructField("day", IntegerType(), True),
            ]
        )

    args = parse_args()
    logger = QuintoAndarLogger(JOB_NAME)
    if args.table_name == "fairness_classification":
        # Written in the same run as ``fairness_assessment``; this task only satisfies DAG wiring.
        logger.info(
            "m=skip_redundant_fairness_classification_spark,msg=classification upsert "
            "runs with load-enrich-fairness-assessment-fairness-assessment"
        )
        return
    spark = BaseSparkContext.spark
    partition_cols = ast.literal_eval(args.partitions) if args.partitions else []

    datahub_graphql = os.environ.get("DATAHUB_GRAPHQL_URL", "").strip()
    if not datahub_graphql:
        datahub_graphql = graphql_url_for_environment(args.environment)
    datahub_graphql = datahub_graphql.rstrip("/")

    token: Optional[str] = None
    try:
        dbutils = BaseDBUtils().get_dbutils()
        raw_key = dbutils.secrets.get(scope="quintoandar", key="DATAHUB_API_KEY")
        if raw_key is not None and str(raw_key).strip():
            token = str(raw_key).strip()
    except Exception:
        token = None
    if not token:
        token = os.environ.get("DATAHUB_API_KEY", "").strip() or None
    if not token:
        token = os.environ.get("DATAHUB_API_TOKEN", "").strip() or None

    doc_dt = F.make_date(
        F.col("year").cast("int"),
        F.col("month").cast("int"),
        F.col("day").cast("int"),
    )
    load_start = F.to_date(F.lit(args.load_start_date))
    load_end = F.to_date(F.lit(args.load_end_date))

    td_all = spark.table(TABLES_DOC).withColumn("doc_dt", doc_dt)
    td = td_all.filter(F.col("doc_dt") >= load_start).filter(F.col("doc_dt") <= load_end)
    per_fqn_max_dt = td.groupBy("database_name", "table_name").agg(
        F.max("doc_dt").alias("max_doc_dt"),
    )
    cd_all = spark.table(COLUMNS_DOC).withColumn("doc_dt", doc_dt)
    cd_f = (
        cd_all.filter(F.col("doc_dt") >= load_start)
        .filter(F.col("doc_dt") <= load_end)
        .join(per_fqn_max_dt, on=["database_name", "table_name"], how="inner")
        .filter(F.col("doc_dt") == F.col("max_doc_dt"))
        .drop("max_doc_dt")
    )
    td = (
        td.join(per_fqn_max_dt, on=["database_name", "table_name"], how="inner")
        .filter(F.col("doc_dt") == F.col("max_doc_dt"))
        .drop("max_doc_dt")
    )

    w = Window.partitionBy("database_name", "table_name")
    td = td.withColumn("fqn_occurrence_count", F.count(F.lit(1)).over(w))
    td = td.withColumn(
        "owner_email_normalized",
        F.lower(F.trim(F.col("owner"))),
    )

    active_emails = (
        spark.table(ORG_CHART)
        .filter(F.col("assignment_status_type") == F.lit("ACTIVE"))
        .select(F.lower(F.trim(F.col("work_email"))).alias("active_email"))
        .where(F.col("active_email").isNotNull() & (F.col("active_email") != F.lit("")))
        .distinct()
    )

    td = td.join(
        active_emails,
        td.owner_email_normalized == active_emails.active_email,
        how="left",
    ).withColumn(
        "is_active_employee",
        F.col("active_email").isNotNull(),
    )
    td = td.drop("active_email")

    td = td.withColumn("contract_server_databricks", F.lit(True)).withColumn(
        "contract_server_trino",
        F.lit(True),
    )

    exists_map, spark_probe_status_map = resolve_spark_table_exists_map(spark, td)
    cd_rows = (
        cd_f.select("database_name", "table_name", "column_name", "column_description")
        .collect()
    )
    col_by_fqn = _build_column_descriptions_by_fqn_from_collected_rows(cd_rows)
    phys_map = resolve_spark_physical_field_names_lower(spark, exists_map)
    f2_i1_by_fqn: dict[
        tuple[str, str],
        dict[str, Any],
    ] = {}
    for r in td.select("database_name", "table_name").distinct().collect():
        k = (str(r["database_name"] or "").strip(), str(r["table_name"] or "").strip())
        cdesc = col_by_fqn.get(k, {})
        ex = bool(exists_map.get(k, False))
        ph = phys_map.get(k, frozenset())
        f2r, i1r, i1_json, cols_sub = compute_f2_02_and_i1_01_for_fqn(
            k[0],
            k[1],
            cdesc,
            spark_table_exists=ex,
            physical_field_names_lower=ph,
        )
        f2_i1_by_fqn[k] = {
            "f2_02_pass": f2r.passed,
            "f2_02_failure_reason": f2r.reason,
            "i1_01_pass": i1r.passed,
            "i1_01_failure_reason": i1r.reason,
            "i1_01_undocumented_json": i1_json,
            "columns_description_is_substantive": cols_sub,
        }

    bc_exists = spark.sparkContext.broadcast(exists_map)
    bc_spark_probe_status = spark.sparkContext.broadcast(spark_probe_status_map)
    bc_f2_i1 = spark.sparkContext.broadcast(f2_i1_by_fqn)

    def _lookup_spark_table_exists(db: Any, tbl: Any) -> bool:
        if db is None or tbl is None:
            return False
        key = (str(db).strip(), str(tbl).strip())
        return bool(bc_exists.value.get(key, False))

    def _lookup_spark_catalog_probe_status(db: Any, tbl: Any) -> Any:
        if db is None or tbl is None:
            return None
        key = (str(db).strip(), str(tbl).strip())
        return bc_spark_probe_status.value.get(key)

    exists_udf = F.udf(_lookup_spark_table_exists, BooleanType())
    td = td.withColumn("spark_table_exists", exists_udf(F.col("database_name"), F.col("table_name")))
    probe_status_udf = F.udf(_lookup_spark_catalog_probe_status, StringType())
    td = td.withColumn(
        "spark_catalog_probe_status",
        probe_status_udf(F.col("database_name"), F.col("table_name")),
    )

    f2i1_struct = StructType(
        [
            StructField("f2_02_pass", BooleanType(), False),
            StructField("f2_02_failure_reason", StringType(), True),
            StructField("i1_01_pass", BooleanType(), False),
            StructField("i1_01_failure_reason", StringType(), True),
            StructField("i1_01_undocumented_json", StringType(), True),
            StructField("columns_description_is_substantive", BooleanType(), False),
        ]
    )

    def _lookup_f2_i1_row(db: Any, tbl: Any) -> Any:
        if db is None or tbl is None:
            return (False, None, False, None, "{}", False)
        key = (str(db).strip(), str(tbl).strip())
        m = bc_f2_i1.value.get(key)
        if m is None:
            return (False, None, False, None, "{}", False)
        return (
            bool(m["f2_02_pass"]),
            m.get("f2_02_failure_reason"),
            bool(m["i1_01_pass"]),
            m.get("i1_01_failure_reason"),
            m.get("i1_01_undocumented_json") or "{}",
            bool(m.get("columns_description_is_substantive", False)),
        )

    f2i1_udf = F.udf(_lookup_f2_i1_row, f2i1_struct)
    td = (
        td.withColumn("_f2i1", f2i1_udf(F.col("database_name"), F.col("table_name")))
        .withColumn("f2_02_pass", F.col("_f2i1.f2_02_pass"))
        .withColumn("f2_02_failure_reason", F.col("_f2i1.f2_02_failure_reason"))
        .withColumn("i1_01_pass", F.col("_f2i1.i1_01_pass"))
        .withColumn("i1_01_failure_reason", F.col("_f2i1.i1_01_failure_reason"))
        .withColumn("i1_01_undocumented_json", F.col("_f2i1.i1_01_undocumented_json"))
        .withColumn(
            "columns_description_is_substantive",
            F.col("_f2i1.columns_description_is_substantive"),
        )
        .drop("_f2i1")
    )

    distinct_for_dh = td.select(
        "database_name",
        "table_name",
        "contract_server_databricks",
        "contract_server_trino",
    ).distinct()

    collected = distinct_for_dh.collect()
    contract_fqn_map: dict[tuple[str, str], bool] = {}
    i3_own_map: dict[tuple[str, str], bool] = {}
    i3_lin_pass_map: dict[tuple[str, str], bool] = {}
    i3_up_tot_map: dict[tuple[str, str], int] = {}
    i3_down_tot_map: dict[tuple[str, str], int] = {}
    if not datahub_graphql:
        logger.warning(
            "m=datahub_skip,msg=datahub GraphQL URL empty; F4-01 will fail closed"
        )
        f4_map, f4_reason_map = compute_f4_pass_and_reason_by_fqn(
            collected,
            {},
            {},
            datahub_host_configured=False,
        )
    else:
        (
            urn_hit,
            urn_contract,
            urn_diag,
            urn_ownership,
            urn_upstream_total,
            urn_downstream_total,
        ) = resolve_datahub_urn_flags(datahub_graphql, token, collected)
        f4_map, f4_reason_map = compute_f4_pass_and_reason_by_fqn(
            collected,
            urn_hit,
            urn_diag,
            datahub_host_configured=True,
        )
        contract_fqn_map = compute_has_data_contract_by_fqn(collected, urn_contract)
        i3_own_map = compute_i3_ownership_pass_by_fqn(collected, urn_ownership)
        i3_lin_pass_map, i3_up_tot_map, i3_down_tot_map = compute_i3_lineage_pass_and_totals_by_fqn(
            collected,
            urn_upstream_total,
            urn_downstream_total,
        )
        if not token:
            logger.info(
                "m=datahub_token_optional,msg=no Bearer token "
                "(secret quintoandar/DATAHUB_API_KEY or env DATAHUB_API_KEY / DATAHUB_API_TOKEN); "
                "GraphQL calls proceed without Authorization header"
            )

    bc_f4 = spark.sparkContext.broadcast(f4_map)
    bc_f4_reason = spark.sparkContext.broadcast(f4_reason_map)
    bc_contract = spark.sparkContext.broadcast(contract_fqn_map)
    bc_i3_own = spark.sparkContext.broadcast(i3_own_map)
    bc_i3_lin = spark.sparkContext.broadcast(i3_lin_pass_map)
    bc_i3_up = spark.sparkContext.broadcast(i3_up_tot_map)
    bc_i3_down = spark.sparkContext.broadcast(i3_down_tot_map)
    use_dh_contract = bool(datahub_graphql)

    def _resolve_has_contract(db: Any, tbl: Any) -> bool:
        if db is None or tbl is None:
            return False
        key = (str(db).strip(), str(tbl).strip())
        if not use_dh_contract:
            return False
        return bool(bc_contract.value.get(key, False))

    contract_udf = F.udf(_resolve_has_contract, BooleanType())
    td = td.withColumn(
        "has_data_contract",
        contract_udf(F.col("database_name"), F.col("table_name")),
    )

    def _lookup_f4(db: Any, tbl: Any) -> bool:
        if db is None or tbl is None:
            return False
        key = (str(db).strip(), str(tbl).strip())
        return bool(bc_f4.value.get(key, False))

    def _lookup_f4_failure_reason(db: Any, tbl: Any) -> Any:
        if db is None or tbl is None:
            return None
        key = (str(db).strip(), str(tbl).strip())
        return bc_f4_reason.value.get(key)

    f4_udf = F.udf(_lookup_f4, BooleanType())
    td = td.withColumn("f4_01_pass", f4_udf(F.col("database_name"), F.col("table_name")))
    f4_reason_udf = F.udf(_lookup_f4_failure_reason, StringType())
    td = td.withColumn(
        "f4_01_failure_reason",
        f4_reason_udf(F.col("database_name"), F.col("table_name")),
    )

    bc_gql_enabled = spark.sparkContext.broadcast(bool(datahub_graphql))

    def _lookup_i3_01(db: Any, tbl: Any) -> Any:
        if not bc_gql_enabled.value:
            return None
        if db is None or tbl is None:
            return False
        key = (str(db).strip(), str(tbl).strip())
        return bool(bc_i3_own.value.get(key, False))

    def _lookup_i3_02(db: Any, tbl: Any) -> Any:
        if not bc_gql_enabled.value:
            return None
        if db is None or tbl is None:
            return False
        key = (str(db).strip(), str(tbl).strip())
        return bool(bc_i3_lin.value.get(key, False))

    def _lookup_lineage_up(db: Any, tbl: Any) -> Any:
        if not bc_gql_enabled.value:
            return None
        if db is None or tbl is None:
            return 0
        key = (str(db).strip(), str(tbl).strip())
        return int(bc_i3_up.value.get(key, 0) or 0)

    def _lookup_lineage_down(db: Any, tbl: Any) -> Any:
        if not bc_gql_enabled.value:
            return None
        if db is None or tbl is None:
            return 0
        key = (str(db).strip(), str(tbl).strip())
        return int(bc_i3_down.value.get(key, 0) or 0)

    i3_01_udf = F.udf(_lookup_i3_01, BooleanType())
    i3_02_udf = F.udf(_lookup_i3_02, BooleanType())
    lineage_up_udf = F.udf(_lookup_lineage_up, LongType())
    lineage_down_udf = F.udf(_lookup_lineage_down, LongType())
    td = td.withColumn("i3_01_pass", i3_01_udf(F.col("database_name"), F.col("table_name")))
    td = td.withColumn("i3_02_pass", i3_02_udf(F.col("database_name"), F.col("table_name")))
    td = td.withColumn(
        "datahub_lineage_upstream_total",
        lineage_up_udf(F.col("database_name"), F.col("table_name")),
    )
    td = td.withColumn(
        "datahub_lineage_downstream_total",
        lineage_down_udf(F.col("database_name"), F.col("table_name")),
    )

    out_rdd = td.rdd.map(_eval_partition)
    out_df = spark.createDataFrame(out_rdd, _output_schema())

    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.schema, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    full_table = f"{database_name}.{args.table_name}"
    path = f"{database_location}/{args.table_name}"

    merge_on = ["database_name", "table_name", "year", "month", "day"]
    loader = DeltaLoader(spark=spark)
    loader.load_table(
        table_name=full_table,
        path=path,
        source_df=out_df,
        partition_by=partition_cols or None,
        merge_on=merge_on,
    )

    w_latest = Window.partitionBy("database_name", "table_name").orderBy(
        F.col("ts_assessed").desc(),
        F.col("year").desc(),
        F.col("month").desc(),
        F.col("day").desc(),
    )

    def _udf_tier_to_class(tier: Any) -> str:
        if tier is None:
            return tier_achieved_to_classification(0)
        return tier_achieved_to_classification(int(tier))

    class_udf = F.udf(_udf_tier_to_class, StringType())
    class_df = (
        out_df.withColumn("_rn", F.row_number().over(w_latest))
        .filter(F.col("_rn") == 1)
        .drop("_rn")
        .select(
            "database_name",
            "table_name",
            class_udf(F.col("tier_achieved")).alias("classification"),
            "ts_assessed",
        )
    )
    class_full = f"{database_name}.fairness_classification"
    class_path = f"{database_location}/fairness_classification"
    loader.load_table(
        table_name=class_full,
        path=class_path,
        source_df=class_df,
        merge_on=["database_name", "table_name"],
    )


if __name__ == "__main__":
    main()
