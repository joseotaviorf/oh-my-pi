import argparse
import ast
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from itertools import chain
from typing import Optional

from datahub.ingestion.graph.client import DatahubClientConfig, DataHubGraph
from datahub.metadata.schema_classes import DatasetKeyClass, SchemaMetadataClass
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.loaders.delta_loader import DeltaLoader

JOB_NAME = "load_datahub_datasets"

logger = QuintoAndarLogger(JOB_NAME)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("partitions")
    args = parser.parse_args()
    logger.info(
        f"m=parse_args,environment={args.environment},schema={args.schema},"
        f"table_name={args.table_name},load_start_date={args.load_start_date},"
        f"load_end_date={args.load_end_date}"
    )
    return args


def build_datahub_client(environment: str, token: str) -> DataHubGraph:
    env_subdomain = "prd" if environment == "prod" else "frn"
    return DataHubGraph(
        config=DatahubClientConfig(
            server=f"https://datahub-gms.apps.data-{env_subdomain}.habitat.zone/",
            token=token,
        )
    )


def get_lineage_flags(datahub_client: DataHubGraph, urn: str) -> tuple[bool, bool]:
    all_upstreams = list(
        chain(
            datahub_client.get_related_entities(
                entity_urn=urn,
                relationship_types=["DownstreamOf"],
                direction=DataHubGraph.RelationshipDirection.OUTGOING,
            ),
            datahub_client.get_related_entities(
                entity_urn=urn,
                relationship_types=["Produces"],
                direction=DataHubGraph.RelationshipDirection.INCOMING,
            ),
        )
    )

    has_table_lineage = any(
        e.relationship_type == "DownstreamOf" for e in all_upstreams
    )
    has_load_job_lineage = any(
        e.relationship_type == "Produces" and "load-" in e.urn and "airflow" in e.urn
        for e in all_upstreams
    )
    return has_table_lineage, has_load_job_lineage


MAX_WORKERS = 20


def process_urn(datahub_client: DataHubGraph, urn: str) -> Optional[dict]:
    try:
        entity = datahub_client.get_entity_semityped(entity_urn=urn)
        dataset_aspect = entity.get(DatasetKeyClass.ASPECT_NAME)
        schema_aspect = entity.get(SchemaMetadataClass.ASPECT_NAME)

        has_table_lineage, has_load_job_lineage = get_lineage_flags(datahub_client, urn)

        fields = schema_aspect.fields if schema_aspect else []
        platform_raw = schema_aspect.platform if schema_aspect else ""

        return {
            "urn": urn,
            "dataset_name": dataset_aspect.name if dataset_aspect else None,
            "platform_name": platform_raw.replace("urn:li:dataPlatform:", ""),
            "num_cols": len(fields),
            "has_table_lineage": has_table_lineage,
            "has_load_job_lineage": has_load_job_lineage,
        }
    except Exception as e:
        logger.warning(f"m=process_urn,urn={urn},error={e}")
        return None


def fetch_dataset_records(datahub_client: DataHubGraph) -> list[dict]:
    urns = list(
        datahub_client.get_urns_by_filter(
            entity_types=["dataset"],
            platform=["databricks", "glue", "hive", "trino"],
        )
    )
    logger.info(f"m=fetch_dataset_records,total_urns={len(urns)}")

    records = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(process_urn, datahub_client, urn): urn for urn in urns
        }
        for future in as_completed(futures):
            result = future.result()
            if result is not None:
                records.append(result)

    return records


def main() -> None:
    args = parse_args()

    logger.info(
        f"m=main,environment={args.environment},schema={args.schema},"
        f"table_name={args.table_name},load_start_date={args.load_start_date},"
        f"load_end_date={args.load_end_date}"
    )

    partition_cols = ast.literal_eval(args.partitions)
    load_date = datetime.strptime(args.load_end_date, "%Y-%m-%d")

    token = dbutils.secrets.get(scope="quintoandar", key="DATAHUB_API_KEY")
    datahub_client = build_datahub_client(args.environment, token)

    records = fetch_dataset_records(datahub_client)

    spark = SparkSession.builder.getOrCreate()

    df = (
        spark.createDataFrame(records)
        .withColumn("year", F.lit(load_date.year))
        .withColumn("month", F.lit(load_date.month))
        .withColumn("day", F.lit(load_date.day))
    )

    db_info = DatalakeMetastoreService.get_db_info(
        args.environment, args.schema, args.datalake_bucket
    )
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    full_table = f"{database_name}.{args.table_name}"
    path = f"{database_location}/{args.table_name}"

    DeltaLoader(spark=spark).load_table(
        table_name=full_table,
        path=path,
        source_df=df,
        partition_by=partition_cols,
        merge_on=["urn", "year", "month", "day"],
    )
    priv = TablePrivileges.from_environment_default(full_table)
    if priv and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        priv.apply()


main()
