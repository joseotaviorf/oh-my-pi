from argparse import ArgumentParser, Namespace

from pyspark.sql import DataFrame
from pyspark.sql.functions import (
    coalesce,
    col,
    count,
    current_timestamp,
    dayofmonth,
    greatest,
    min as spark_min,
    month,
    row_number,
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

JOB_NAME = "load_listing_draft_events"


def main():
    args = parse_args()
    config = ConfigurationService(args.relative_query_path)
    bcd_df = load_business_context_detail(config)
    lbc_df = load_listing_business_context(config)
    lbc_aud_df = load_listing_business_context_aud(config)
    house_df = load_house(config)

    result_df = build_listing_draft_events(bcd_df, lbc_df, lbc_aud_df, house_df)
    save_df(result_df, args, config)


def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("database_base_name", type=str)
    parser.add_argument("relative_query_path", type=str)
    parser.add_argument("table_name", type=str)
    return parser.parse_args()


def load_business_context_detail(config: ConfigurationService) -> DataFrame:
    return (
        spark.read.table(config.get_config("BUSINESS_CONTEXT_DETAIL_TABLE"))
        .filter(col("id_listing").isNotNull())
        .select(
            col("id_lead").alias("id_lead_3p"),
            col("business_context"),
            col("id_listing"),
            col("has_3p_access_control"),
            col("ts_created"),
        )
    )


def load_listing_business_context(config: ConfigurationService) -> DataFrame:
    return spark.read.table(
        config.get_config("LISTING_BUSINESS_CONTEXT_TABLE")
    ).select(
        col("id"),
        col("id_house"),
        col("business_context"),
        col("status"),
        col("ownership"),
        col("ts_created"),
        col("ts_first_publication"),
        col("ts_last_status_changed"),
    )


def load_listing_business_context_aud(config: ConfigurationService) -> DataFrame:
    return spark.read.table(
        config.get_config("LISTING_BUSINESS_CONTEXT_AUD_TABLE")
    ).select(
        col("id_listing_business_context"),
        col("id_house"),
        col("rev"),
        col("rev_type"),
        col("status"),
        col("ownership"),
        col("ts_created"),
    )


def load_house(config: ConfigurationService) -> DataFrame:
    return (
        spark.read.table(config.get_config("HOUSE_TABLE"))
        .filter(col("has_3p_access_control"))
        .select(
            col("id").alias("id_house"),
            col("has_3p_access_control"),
        )
    )


def build_listing_draft_events(
    bcd_df: DataFrame,
    lbc_df: DataFrame,
    lbc_aud_df: DataFrame,
    house_df: DataFrame,
) -> DataFrame:
    house_mapping = _build_house_mapping(bcd_df, lbc_df, house_df)
    listing_events = _build_listing_events(bcd_df, lbc_df)
    cdi_ownership = _build_cdi_ownership(bcd_df, lbc_aud_df)

    result = house_mapping.alias("hm")

    result = result.join(
        listing_events.alias("le"),
        (col("hm.id_lead_3p") == col("le.id_lead_3p"))
        & (col("hm.business_context") == col("le.business_context")),
        "left",
    )

    result = result.join(
        cdi_ownership.alias("co"),
        (col("hm.id_lead_3p") == col("co.id_lead_3p"))
        & (col("hm.business_context") == col("co.business_context")),
        "left",
    )

    result = result.withColumn("ts_load", current_timestamp())

    result = result.withColumn(
        "ts_updated",
        coalesce(
            greatest(
                col("le.ts_availability_check"),
                col("le.ts_availability_check_resolution"),
                col("le.ts_first_listing"),
            ),
            col("ts_load"),
        ),
    )

    result = (
        result.withColumn("year", year(col("ts_updated")))
        .withColumn("month", month(col("ts_updated")))
        .withColumn("day", dayofmonth(col("ts_updated")))
    )

    return result.select(
        col("hm.id_lead_3p"),
        col("hm.id_house"),
        col("hm.id_listing"),
        col("hm.business_context"),
        col("hm.is_lead_house_conflict"),
        col("co.is_first_listing_through_cdi"),
        col("hm.has_3p_access_control"),
        col("le.ts_availability_check"),
        col("le.ts_availability_check_resolution"),
        col("le.ts_first_listing"),
        col("ts_updated"),
        col("ts_load"),
        col("year"),
        col("month"),
        col("day"),
    )


def _build_house_mapping(
    bcd_df: DataFrame, lbc_df: DataFrame, house_df: DataFrame
) -> DataFrame:
    """Map leads to EBDB houses, handling 1:N conflicts with ROW_NUMBER."""
    lead_listing = bcd_df.alias("bcd").join(
        lbc_df.alias("lbc"),
        col("bcd.id_listing") == col("lbc.id"),
        "inner",
    ).join(
        house_df.alias("h"),
        col("lbc.id_house") == col("h.id_house"),
        "inner",
    ).select(
        col("bcd.id_lead_3p"),
        col("bcd.business_context"),
        col("bcd.id_listing"),
        col("lbc.id_house").alias("id_house"),
        col("bcd.has_3p_access_control"),
    )

    conflict_counts = lead_listing.groupBy(
        "id_lead_3p", "business_context"
    ).agg(
        count("*").alias("house_count")
    )

    window = Window.partitionBy(
        "id_lead_3p", "business_context"
    ).orderBy("id_house")
    lead_listing = lead_listing.withColumn("rn", row_number().over(window))

    deduped = lead_listing.filter(col("rn") == 1).drop("rn")

    return deduped.join(
        conflict_counts,
        ["id_lead_3p", "business_context"],
        "left",
    ).withColumn(
        "is_lead_house_conflict", col("house_count") > 1
    ).drop("house_count")


def _build_listing_events(
    bcd_df: DataFrame, lbc_df: DataFrame
) -> DataFrame:
    """Extract availability and listing milestone timestamps."""
    joined = bcd_df.alias("bcd").join(
        lbc_df.alias("lbc"),
        col("bcd.id_listing") == col("lbc.id"),
        "inner",
    )

    return joined.groupBy(
        col("bcd.id_lead_3p"),
        col("bcd.business_context"),
    ).agg(
        spark_min(col("lbc.ts_created")).alias("ts_availability_check"),
        spark_min(col("lbc.ts_first_publication")).alias(
            "ts_availability_check_resolution"
        ),
        spark_min(
            when(
                col("lbc.status").isin("PUBLISHED", "EDITING"),
                col("lbc.ts_first_publication"),
            )
        ).alias("ts_first_listing"),
    )


def _build_cdi_ownership(
    bcd_df: DataFrame, lbc_aud_df: DataFrame
) -> DataFrame:
    """Determine if the first listing version was created through CDI (by 3P partner)."""
    joined = bcd_df.alias("bcd").join(
        lbc_aud_df.alias("aud"),
        col("bcd.id_listing") == col("aud.id_listing_business_context"),
        "inner",
    )

    window = Window.partitionBy(
        col("bcd.id_lead_3p"), col("bcd.business_context")
    ).orderBy(col("aud.rev").asc())

    first_rev = joined.withColumn(
        "rn", row_number().over(window)
    ).filter(col("rn") == 1).drop("rn")

    return first_rev.select(
        col("bcd.id_lead_3p"),
        col("bcd.business_context"),
        (col("aud.ownership") == "THREE_P").alias(
            "is_first_listing_through_cdi"
        ),
    )


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