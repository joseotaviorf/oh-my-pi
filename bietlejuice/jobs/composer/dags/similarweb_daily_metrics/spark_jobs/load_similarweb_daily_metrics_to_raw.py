from argparse import ArgumentParser
from functools import reduce
import json

from pyspark.sql.functions import col, lit, explode
from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger
from quintoandar_similarweb_api_client.clients import SimilarWebClient
from quintoandar_similarweb_api_client.consumers import CONSUMERS

from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.api.api_enum import APIEnum
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

from bietlejuice.jobs.composer.base.spark import (
    BaseDBUtils,
    BaseSparkContext,
    SparkTableStorageFormat,
)

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_similarweb_daily_metrics_to_raw"

logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


def create_df_from_result(
    spark_client,
    result,
    domain,
    platform,
    cols_to_select,
    cols_to_rename={},
    col_to_explode=None,
):
    sc = BaseSparkContext.sc
    df = spark_client.conn.read.json(sc.parallelize([json.dumps(result)]))

    df = df.withColumn("domain", lit(domain)).withColumn("platform", lit(platform))

    if col_to_explode:
        df = df.withColumn(col_to_explode, explode(col_to_explode))

    df = df.select(
        [
            col(c).alias(cols_to_rename[c]) if c in cols_to_rename else col(c)
            for c in cols_to_select
        ]
    )

    return df


def list_to_dict(response):
    return {key: value for result in response for key, value in result.items()}


def fetch_similarweb_metrics(consumer_instance, domain, platform, metrics):
    return consumer_instance.sync(
        domain=domain, platform=platform, metrics_list=metrics
    )


def join_list_of_dataframes(dfs_list=list, join_on_list=list):
    # For cases when there is only one metric per platform/endpoint
    if len(dfs_list) == 1:
        return dfs_list[0]
    return reduce(lambda a, b: a.join(b, join_on_list, "full"), dfs_list)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the API")
    parser.add_argument("table_name", help="table name to be created")
    parser.add_argument(
        "week_start_date",
        help="start date to filter returned dates from API in str format",
    )

    args = parser.parse_args()

    environment = args.environment
    source = args.source
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    week_start_date = args.week_start_date

    config_service = ConfigurationService(source)
    consumer_configs = config_service.get_config(f"{table_name}_configs")
    raw_partition_cols = consumer_configs["raw_partition_cols"]
    domains = consumer_configs["domains"]
    platforms = consumer_configs["platforms"]
    metrics = consumer_configs["metrics"]
    join_on_list = consumer_configs["join_on_list"]

    logger.info(
        f"""m=load_similarweb_daily_metrics_to_raw, environment={environment}, source={source}, datalake_bucket={datalake_bucket}, week_start_date={week_start_date}, table_name={table_name}, msg=Starting spark job..."""
    )

    spark_client = SparkClient()

    api_key = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.SIMILARWEB)

    sw_client = SimilarWebClient(api_key)

    consumer_instance = CONSUMERS[table_name](sw_client)

    dfs_platforms = []
    for platform in platforms:
        for domain in domains:
            metrics_list = list(metrics.keys())

            if platform == "total":
                metrics_list.remove("unique-visitors")

            response = fetch_similarweb_metrics(
                consumer_instance, domain, platform, metrics_list
            )

            if not response:
                raise Exception(
                    f"""m=load_similarweb_daily_metrics_to_raw, table_name={table_name},
          msg=Fail to retrieve data from API.""",
                    f"domain={domain}, platform={platform}, metrics={metrics_list}",
                )

            response_dict = list_to_dict(response)
            dfs_metrics_list = []

            for key in response_dict.keys():
                result = (
                    response_dict[key][domain]
                    if table_name == "traffic_sources" and key == "overview-share"
                    else response_dict[key]
                )

                cols_to_select = metrics[key]["cols_to_select"]
                cols_to_rename = (
                    metrics[key]["cols_to_rename"]
                    if "cols_to_rename" in metrics[key]
                    else {}
                )
                col_to_explode = (
                    metrics[key]["col_to_explode"]
                    if "col_to_explode" in metrics[key]
                    else None
                )

                df = create_df_from_result(
                    spark_client,
                    result,
                    domain,
                    platform,
                    cols_to_select,
                    cols_to_rename,
                    col_to_explode,
                )
                dfs_metrics_list.append(df)

            all_metrics_joined = join_list_of_dataframes(dfs_metrics_list, join_on_list)

            if platform == "total":
                """
                make it possible union all between platforms dataframes,
                because total platform doesn't have unique_visitors metric
                """
                all_metrics_joined = all_metrics_joined.withColumn(
                    "unique_visitors", lit(None)
                )

            dfs_platforms.append(all_metrics_joined)

    df_final = reduce(DataFrame.unionAll, dfs_platforms)

    # filtering dates
    df_final = df_final.filter(col("date") >= week_start_date)

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = db_info["db_raw_path"]

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)

    if df_final:
        s3_loader.load_df(
            df=df_final,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df_final,
            database_name,
            table_name,
            format_options,
            database_location,
            raw_partition_cols,
        )

        metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df_final,
            partition_cols=raw_partition_cols,
        )
    else:
        raise Exception(
            f"""m=load_similarweb_daily_metrics_to_raw, table_name={table_name},
        msg=Fail to create similarweb_daily_metrics dataframe."""
        )
