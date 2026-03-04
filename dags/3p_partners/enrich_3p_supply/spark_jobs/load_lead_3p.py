import os
from argparse import ArgumentParser, Namespace

import yaml
from pyspark.sql import DataFrame
from pyspark.sql.functions import (
    col,
    current_timestamp,
    dayofmonth,
    get_json_object,
    month,
    trim,
    when,
    year,
)

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_lead_3p"

SOURCE_COLUMNS = [
    "id",
    "uuid_lead",
    "uuid_company",
    "cnpj",
    "id_by_real_estate",
    "lead_hash",
    "is_sent_to_main",
    "location",
    "pricing",
    "blueprint",
    "owner",
    "owner_agent",
    "access",
    "brokers",
    "details",
    "photos",
    "has_3p_access_control",
    "ts_created",
    "ts_updated",
]

FINAL_COLUMNS = [
    "id_lead_3p", 
    "uuid_lead", 
    "uuid_company", 
    "id_by_real_estate",
    "cnpj", 
    "lead_hash",
    "address", 
    "number", 
    "floor", 
    "complement", 
    "neighborhood", 
    "city",
    "state_acronym", 
    "country", 
    "country_code", 
    "zip_code", 
    "lat", 
    "lng",
    "region_id", 
    "region_slug", 
    "reference_point",
    "rent", 
    "sale_price", 
    "condo_price",
    "total_area", 
    "bedrooms", 
    "suites", 
    "bathrooms", 
    "garages", 
    "house_type",
    "owner_email", 
    "owner_name", 
    "owner_phone", 
    "owner_person_type",
    "owner_agent_person_uuid", 
    "owner_agent_external_id", 
    "owner_agent_name",
    "owner_agent_email", 
    "owner_agent_phone", 
    "owner_agent_relationship",
    "access_type", 
    "authorization_type", 
    "occupant_type",
    "condominium", 
    "construction_year", 
    "block", 
    "tower",
    "details", 
    "photos",
    "is_sent_to_main", 
    "is_out_of_area", 
    "is_iptu_not_paid",
    "has_restriction", 
    "has_balcony", 
    "is_furnished", 
    "is_habitat",
    "has_agency_key", 
    "has_concierge",
     "has_3p_access_control",
    "ts_created", 
    "ts_updated", 
    "ts_load",
    "year", 
    "month", 
    "day",
]


def main():
    args = parse_args()
    config = load_config(args.env)
    source_df = load_source_data(config)
    enriched_df = extract_json_fields(source_df, config)
    save_df(enriched_df, args, config)


def parse_args() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("database_base_name", type=str)
    parser.add_argument("relative_query_path", type=str)
    parser.add_argument("table_name", type=str)
    return parser.parse_args()


def load_config(env: str) -> dict:
    config_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        f"{env}_conf.yml",
    )
    with open(config_path) as f:
        return yaml.safe_load(f)


def load_source_data(config: dict) -> DataFrame:
    return spark.read.table(config["SOURCE_TABLE"]).select(
        [col(c) for c in SOURCE_COLUMNS]
    )


def extract_json_fields(df: DataFrame, config: dict) -> DataFrame:
    """Dynamically extract JSON fields based on YAML configuration.

    The source table stores structured data as JSON strings in columns like
    ``location``, ``pricing``, ``blueprint``, ``owner``, ``owner_agent``,
    ``access`` and ``brokers``.  Instead of hard-coding each extraction, the
    field mapping is driven by the ``lead_3p_json_fields`` section in
    prod_conf.yml / forno_conf.yml.  Each entry maps a *source JSON column*
    to one or more output columns with their JSONPath and optional cast type.
    To add, remove or rename an extracted field, edit the config file only —
    no changes to this script are needed.
    """
    json_fields = config["lead_3p_json_fields"]

    for json_col, fields in json_fields.items():
        for output_name, field_config in fields.items():
            json_path = field_config["path"]
            cast_type = field_config.get("cast")

            extracted = get_json_object(col(json_col), json_path)
            value = when(trim(extracted) != "", extracted)

            if cast_type:
                value = value.cast(cast_type)

            df = df.withColumn(output_name, value)

    df = (
        df.withColumn("id_lead_3p", col("id"))
        .withColumn("ts_load", current_timestamp())
        .withColumn("year", year(col("ts_updated")))
        .withColumn("month", month(col("ts_updated")))
        .withColumn("day", dayofmonth(col("ts_updated")))
    )

    return df.select([col(c) for c in FINAL_COLUMNS])


def save_df(df: DataFrame, args: Namespace, config: dict) -> None:
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

    table_config = config["tables"][args.table_name]
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
