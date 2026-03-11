from argparse import ArgumentParser

from pyspark.sql.functions import col, concat, lit, split, when

import yaml

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
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

DEPENDENCIES_S3_PATH = "astronomer/dags/dags/dependencies.yaml"

logger = QuintoAndarLogger(JOB_NAME)


def _fetch_dependencies_file(dbutils, environment):
    config_service = ConfigurationService(JOB_NAME)
    artifacts_bucket = config_service.get_config("artifacts_bucket")
    s3_path = f"{artifacts_bucket}/{DEPENDENCIES_S3_PATH}"

    logger.info(f"m=_fetch_dependencies_file, msg=Reading from {s3_path}")
    content = dbutils.fs.head(s3_path, 1024 * 1024)

    data = yaml.safe_load(content)
    if not data:
        return []

    rows = []
    for dependent, deps in data.items():
        dep_list = deps if isinstance(deps, list) else [deps]
        for dependency in dep_list:
            rows.append((dependent, dependency))

    return rows


def _build_dependencies_spark_df(spark, dependency_rows):
    if not dependency_rows:
        return None

    df = spark.createDataFrame(
        dependency_rows,
        schema="dependent:string, dependency:string",
    )

    dep_split = split(col("dependency"), ":")
    dep_col = split(col("dependent"), ":")

    return df.select(
        dep_col.getItem(0).alias("level_dag_dependency"),
        dep_split.getItem(0).alias("up_level_dag_dependency"),
        when(
            dep_split.getItem(1).isNotNull(),
            dep_split.getItem(1),
        ).otherwise(lit("terminate-cluster")).alias("up_level_task_dependency"),
    ).distinct()


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
    dependency_rows = _fetch_dependencies_file(dbutils, environment)

    if len(dependency_rows) < 1:
        raise Exception(
            "Some problem with dependencies.yaml file ingestion. Schema doesn't match."
        )

    dependencies = _build_dependencies_spark_df(spark, dependency_rows)
    if dependencies is None:
        raise Exception(
            "Some problem with dependencies.yaml file ingestion. No data parsed."
        )

    n_rows = dependencies.count()
    n_cols = len(dependencies.columns)
    if n_rows <= 1 or n_cols != 3:
        raise Exception(
            "Some problem transforming dependencies. Schema doesn't match."
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
