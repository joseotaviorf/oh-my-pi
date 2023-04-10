from argparse import ArgumentParser

from pyspark.sql.functions import *

import requests

import pandas as pd
import json
import yaml
from base64 import b64decode

import logging
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
    BaseDBUtils,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_dependency_tree_raw"

logger = QuintoAndarLogger(JOB_NAME)


def _fetch_dependencies_file(TOKEN):

    url = "https://api.github.com/repos/quintoandar/bi-etl-ejuice/contents/dags/dependencies.yaml"

    headers = {
        "accept": "application/vnd.github.v3.raw",
        "Authorization": f"Bearer {TOKEN}",
        "branch": "master"
    }

    response = requests.get(url, headers=headers)

    # fetch dependencies file
    if response.status_code == 200:
        raw_data = response.text
        data = yaml.safe_load(raw_data)

        # transform to dataframe
        dependencies_wide_df = pd.json_normalize(data)

        return dependencies_wide_df

    else:
        print("Couldn't fetch 'dependencies.yaml' file.")


def _transform_from_wide_to_long_dataframe(dependencies_wide_df):

    # transform from wide to long dataframe
    dependencies_long_df = dependencies_wide_df.transpose()
    dependencies_long_df.columns = ["dependency"]
    dependencies_long_df['dependent'] = dependencies_long_df.index
    dependencies_long_df = dependencies_long_df.reset_index(drop=True)
    dependencies_long_df = dependencies_long_df.explode("dependency")

    # apply naming patters
    dependencies_long_df['level_dag_dependency'] = [
        row.split(":")[0] for row in dependencies_long_df["dependent"].values]
    dependencies_long_df['up_level_task_dependency'] = [row.split(
        ":")[1] if ":" in row else "terminate-cluster" for row in dependencies_long_df["dependency"].values]
    dependencies_long_df['up_level_dag_dependency'] = [
        row.split(":")[0] for row in dependencies_long_df["dependency"].values]

    return dependencies_long_df


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

    """
    Fetch 'dependencies.yaml' data.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = json.loads(
        dbutils.secrets.get('quintoandar', APIEnum.GITHUB)
    )

    TOKEN = credentials["token"]

    dependencies_wide_df = _fetch_dependencies_file(TOKEN)
    n_rows, n_cols = dependencies_wide_df.shape

    if n_rows < 1 or n_cols < 1:
        raise Exception(
            "Some problem with dependencies.yaml file ingestion. Schema doesn't match.")

    dependencies_long_df = _transform_from_wide_to_long_dataframe(
        dependencies_wide_df)
    n_rows, n_cols = dependencies_long_df.shape

    if n_rows <= 1 or n_cols != 5:
        raise Exception(
            "Some problem transforming wide to long dataframe. Schema doesn't match.")

    # final raw dataframe
    dependencies_df = dependencies_long_df[
        ["level_dag_dependency", "up_level_dag_dependency", "up_level_task_dependency"]
    ].drop_duplicates()

    # transform do spark dataframe
    dependencies = spark.createDataFrame(
        dependencies_df, 
        schema="level_dag_dependency:string, up_level_dag_dependency:string, up_level_task_dependency:string"
    )

    # generate dependency tree
    dag_dependencies = dependencies \
        .select(
            col('level_dag_dependency').alias('dag'),
            '*',
            lit(0).alias('level')
        )

    # Loop Through if you dont know recusrsive depth
    level_dependencies = dependencies.withColumn(
        'dag', col('level_dag_dependency'))

    i = 1
    while True:

        next_level = dependencies \
            .withColumnRenamed('level_dag_dependency', 'dag_dependent') \
            .withColumnRenamed('up_level_dag_dependency', 'dag_dependency') \
            .withColumnRenamed('up_level_task_dependency', 'task_dependency')

        update_dag_dependency = level_dependencies \
            .select('dag', 'up_level_dag_dependency') \
            .distinct() \
            .join(next_level, on=level_dependencies['up_level_dag_dependency'] == next_level['dag_dependent'], how='left') \
            .select(
                'dag',
                col('up_level_dag_dependency').alias('level_dag_dependency'),
                col('dag_dependency').alias('up_level_dag_dependency'),
                col('task_dependency').alias('up_level_task_dependency'),
                lit(i).alias('level')
            )

        level_dependencies = update_dag_dependency.select(
            "dag",
            "level_dag_dependency",
            "up_level_dag_dependency",
            "up_level_task_dependency"
        )

        dag_dependencies = dag_dependencies.union(update_dag_dependency)

        # Check if DF is empty. Break loop if empty, Otherwise continue with next level
        if level_dependencies.where(col('up_level_dag_dependency').isNotNull()).count() == 0:
            break
        else:
            i += 1

    df = dag_dependencies \
        .where(col('level_dag_dependency').isNotNull()) \
        .withColumn("up_level_task_dependency", concat(col("up_level_dag_dependency"), lit(":"), col("up_level_task_dependency"))) \
        .distinct()

    n_rows, n_cols = (df.count(), len(df.columns))

    if n_rows <= 2 or n_cols != 5:
        raise Exception(
            "Some problem generating dependency tree. Schema doesn't match.")

    """
    Load data to datalake.
    """
    spark_client = SparkClient()
    spark_context = spark_client.conn.sparkContext
    dataframe_service = SparkDataFrameService()

    db_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket)
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

    """
    Update metastore.
    """
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        raw_table_name,
        format_options,
        database_location,
        force_recreate=True,
    )
