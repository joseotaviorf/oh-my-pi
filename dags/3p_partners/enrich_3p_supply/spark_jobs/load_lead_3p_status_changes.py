from argparse import ArgumentParser, Namespace

from pyspark.sql import DataFrame
from pyspark.sql.functions import (
    col,
    current_timestamp,
    dayofmonth,
    from_json,
    get_json_object,
    lead,
    lit,
    map_filter,
    map_keys,
    month,
    when,
    year,
)
from pyspark.sql.window import Window

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_lead_3p_status_changes"

FINAL_COLUMNS = [
    "id_lead_3p", 
    "id_file", 
    "id_duplicated_house",
    "business_context", 
    "status", 
    "status_reasons",
    "status_reasons_not_eligible", 
    "status_reasons_pending",
    "has_3p_access_control",
    "ts_start", 
    "ts_end", 
    "ts_created", 
    "ts_load",
    "year", 
    "month", 
    "day",
]


def main():
    args = parse_args()
    config = ConfigurationService(args.relative_query_path)
    source_df = load_source_data(config)
    result_df = build_status_changes(source_df)
    save_df(result_df, args, config)


def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("database_base_name", type=str)
    parser.add_argument("relative_query_path", type=str)
    parser.add_argument("table_name", type=str)
    return parser.parse_args()


def load_source_data(config: ConfigurationService) -> DataFrame:
    bcda = spark.read.table(config.get_config("BUSINESS_CONTEXT_DETAIL_AUD_TABLE"))
    bcd = spark.read.table(config.get_config("BUSINESS_CONTEXT_DETAIL_TABLE"))
    ri = spark.read.table(config.get_config("REV_INFO_TABLE"))

    return (
        bcda.alias("bcda")
        .join(bcd.alias("bcd"), col("bcda.id") == col("bcd.id"))
        .join(ri.alias("ri"), col("bcda.rev") == col("ri.rev"))
        .select(
            col("bcd.id_lead").alias("id_lead_3p"),
            col("bcd.business_context"),
            col("bcd.id_file"),
            col("bcda.status"),
            col("bcda.status_reason"),
            col("ri.ts_created").alias("ts_revision"),
            col("bcd.has_3p_access_control"),
            col("bcd.ts_created"),
        )
    )


def build_status_changes(df: DataFrame) -> DataFrame:
    """Build status change timeline with parsed reasons."""
    window = Window.partitionBy("id_lead_3p", "business_context").orderBy(
        col("ts_revision").asc()
    )

    df = df.withColumn(
        "ts_start", col("ts_revision")
    ).withColumn(
        "ts_end", lead("ts_revision").over(window)
    )

    df = parse_status_reasons(df)

    df = (
        df.withColumn("ts_load", current_timestamp())
        .withColumn("year", year(col("ts_start")))
        .withColumn("month", month(col("ts_start")))
        .withColumn("day", dayofmonth(col("ts_start")))
    )

    return df.select([col(c) for c in FINAL_COLUMNS])


def parse_status_reasons(df: DataFrame) -> DataFrame:
    """Extract structured reason data from the status_reason JSON column.

    The status_reason JSON has two shapes:
    - Flat map: {"reasonA": "true", "reasonB": "false", ...}  with special
      keys listOfNotEligibleReasonsMessages and listOfPendingReasonsMessages
    - The lists distinguish not-eligible vs pending/eligible reasons.
    """
    status_map = from_json(col("status_reason"), "map<string, string>")
    df = df.withColumn(
        "status_reasons",
        map_keys(map_filter(status_map, lambda k, v: v == lit("true"))),
    )

    not_eligible_raw = get_json_object(
        col("status_reason"), "$.listOfNotEligibleReasonsMessages"
    )
    df = df.withColumn(
        "status_reasons_not_eligible",
        from_json(
            when(not_eligible_raw != "", not_eligible_raw),
            "array<string>",
        ),
    )

    pending_raw = get_json_object(
        col("status_reason"), "$.listOfPendingReasonsMessages"
    )
    df = df.withColumn(
        "status_reasons_pending",
        from_json(
            when(pending_raw != "", pending_raw),
            "array<string>",
        ),
    )

    duplicate_id_raw = get_json_object(col("status_reason"), "$.duplicateId")
    duplicate_house_raw = get_json_object(
        col("status_reason"), "$.duplicateHouse"
    )
    df = df.withColumn(
        "id_duplicated_house",
        when(
            (duplicate_id_raw.cast("int") != 0)
            & (duplicate_house_raw != "false"),
            duplicate_id_raw.cast("int"),
        ),
    )

    return df


def save_df(df: DataFrame, args: Namespace, config: ConfigurationService) -> None:
    spark_client = SparkClient()
    loader = DeltaLoader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(
        args.env, args.database_base_name, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    spark_metastore_service.create_database(database_name)
    s3_path = database_location + args.table_name
    full_table_name = f"{database_name}.{args.table_name}"

    table_config = config.get_config("tables")[args.table_name]
    loader.load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=df,
        partition_by=["year", "month", "day"],
        merge_on=table_config.get("merge_on"),
        when_matched_update_condition=table_config.get(
            "when_matched_update_condition"
        ),
    )
    spark_metastore_service.refresh_table(database_name, args.table_name)

    table_privileges = TablePrivileges.from_environment_default(full_table_name)
    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()


if __name__ == "__main__":
    main()