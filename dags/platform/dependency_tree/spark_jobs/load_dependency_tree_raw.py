from argparse import ArgumentParser

import pandas as pd
import yaml
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_dependency_tree_raw"
DEPENDENCIES_S3_PATH = "astronomer/dags/dags/dependencies.yaml"

logger = QuintoAndarLogger(JOB_NAME)


def _fetch_dependencies_file(dbutils):
    config_service = ConfigurationService(JOB_NAME)
    artifacts_bucket = config_service.get_config("artifacts_bucket")
    s3_path = f"{artifacts_bucket}/{DEPENDENCIES_S3_PATH}"

    logger.info(f"m=_fetch_dependencies_file, msg=Reading from {s3_path}")
    content = dbutils.fs.head(s3_path, 1024 * 1024)

    data = yaml.safe_load(content)
    return pd.json_normalize(data or {})


def _explode_dependencies(wide_df):
    df = wide_df.transpose()
    df.columns = ["dependency"]
    df["dependent"] = df.index
    df = df.reset_index(drop=True).explode("dependency")

    dep_parts = df["dependency"].str.split(":", expand=True)
    df["level_dag_dependency"] = df["dependent"].str.split(":").str[0]
    df["up_level_dag_dependency"] = dep_parts[0]
    df["up_level_task_dependency"] = dep_parts[1].fillna("terminate-cluster")
    # third segment encodes run frequency modifiers (e.g. 'first-run-of-day')
    df["up_level_run_suffix"] = (
        dep_parts[2].where(dep_parts[2].notna(), other=None)
        if 2 in dep_parts.columns
        else None
    )

    return df


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("raw_table_name")

    args = parser.parse_args()

    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    raw_table_name = args.raw_table_name

    dbutils = BaseDBUtils().get_dbutils()
    spark_client = SparkClient()
    spark = spark_client.conn

    logger.info("m=main, msg=Fetching dependencies.yaml from S3...")
    dependencies_wide_df = _fetch_dependencies_file(dbutils)
    n_rows, n_cols = dependencies_wide_df.shape

    if n_rows < 1 or n_cols < 1:
        raise Exception(
            "Some problem with dependencies.yaml file ingestion. Schema doesn't match."
        )

    dependencies_long_df = _explode_dependencies(dependencies_wide_df)
    n_rows, n_cols = dependencies_long_df.shape

    if n_rows <= 1 or n_cols != 6:
        raise Exception(
            "Some problem transforming wide to long dataframe. Schema doesn't match."
        )

    dependencies_df = dependencies_long_df[
        [
            "level_dag_dependency",
            "up_level_dag_dependency",
            "up_level_task_dependency",
            "up_level_run_suffix",
        ]
    ].drop_duplicates()

    dependencies = spark.createDataFrame(
        dependencies_df,
        schema="level_dag_dependency:string, up_level_dag_dependency:string, up_level_task_dependency:string, up_level_run_suffix:string",
    )

    dag_dependencies = dependencies.select(
        F.col("level_dag_dependency").alias("dag"), "*", F.lit(0).alias("level")
    )

    # iteratively resolves transitive dependencies since recursive depth is unknown
    level_dependencies = dependencies.withColumn("dag", F.col("level_dag_dependency"))

    i = 1
    while True:
        next_level = (
            dependencies.withColumnRenamed("level_dag_dependency", "dag_dependent")
            .withColumnRenamed("up_level_dag_dependency", "dag_dependency")
            .withColumnRenamed("up_level_task_dependency", "task_dependency")
            .withColumnRenamed("up_level_run_suffix", "run_suffix")
        )

        update_dag_dependency = (
            level_dependencies.select("dag", "up_level_dag_dependency")
            .distinct()
            .join(
                next_level,
                on=level_dependencies["up_level_dag_dependency"]
                == next_level["dag_dependent"],
                how="left",
            )
            .select(
                "dag",
                F.col("up_level_dag_dependency").alias("level_dag_dependency"),
                F.col("dag_dependency").alias("up_level_dag_dependency"),
                F.col("task_dependency").alias("up_level_task_dependency"),
                F.col("run_suffix").alias("up_level_run_suffix"),
                F.lit(i).alias("level"),
            )
        )

        level_dependencies = update_dag_dependency.select(
            "dag",
            "level_dag_dependency",
            "up_level_dag_dependency",
            "up_level_task_dependency",
        )

        dag_dependencies = dag_dependencies.union(update_dag_dependency)

        if (
            level_dependencies.where(
                F.col("up_level_dag_dependency").isNotNull()
            ).count()
            == 0
        ):
            break

        i += 1

    df = (
        dag_dependencies.where(F.col("level_dag_dependency").isNotNull())
        .withColumn(
            "up_level_task_dependency",
            F.concat(
                F.col("up_level_dag_dependency"),
                F.lit(":"),
                F.col("up_level_task_dependency"),
            ),
        )
        .distinct()
    )

    n_rows, n_cols = (df.count(), len(df.columns))

    if n_rows <= 2 or n_cols != 6:
        raise Exception(
            "Some problem generating dependency tree. Schema doesn't match."
        )

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{raw_table_name}",
        format_options=format_options,
        optimize_dataframe=False,
        compression="gzip",
    )

    spark_metastore_loader.update_metastore(
        df,
        database_name,
        raw_table_name,
        format_options,
        database_location,
        force_recreate=True,
    )
