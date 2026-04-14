import ast
import json
import logging

from argparse import ArgumentParser
import pyspark.sql.functions as F

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.loaders.delta_loader import DeltaLoader


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_jira_ops_data_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="")
    parser.add_argument("load_start_date", help="start execution date in str format")
    parser.add_argument("load_end_date", help="end execution date in str format")
    parser.add_argument("partitions", help="")
    parser.add_argument("table_name", help="")
    parser.add_argument("extra_args", help="")

    args = parser.parse_args()
    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    table_name = args.table_name
    partition_cols = ast.literal_eval(args.partitions)
    extra_args = json.loads(args.extra_args)

    feedback_config = json.loads(extra_args.get("feedback_config", "{}"))
    source_table_name = feedback_config.get("table_name")
    date_column = feedback_config.get("date_column_filter")
    select_columns = date_column, *partition_cols

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment}, source={args.source}, load_start_date={args.load_start_date},
            load_end_date={args.load_end_date}, datalake_bucket={args.datalake_bucket}, partition_cols={args.partitions}, 
            table_name={args.table_name}, extra_args={args.extra_args}, msg=print spark jobs args"
        """
    )

    df = (
        BaseSparkContext.spark.table(source_table_name)
        .where(
            F.col(date_column)
            .between(load_start_date, load_end_date)
        )
    )

    df_base_responders = (
        df.select(
            F.explode("baseTimeline.rotations").alias("rotation"),
            *select_columns
        )
        .select(
            F.explode("rotation.periods").alias("period"),
            *select_columns
        )
        .filter(F.col("period.responder.type") == "user")
        .select(
            F.col("period.responder.id").alias("id_account"),
            *select_columns
        )
    )

    df_final_period = (
        df.select(
            F.explode("finalTimeline.rotations").alias("rotation"),
            *select_columns
        )
        .select(
            F.explode("rotation.periods").alias("period"),
            *select_columns
        )
    )

    df_final_responders = (
        df_final_period.filter(F.col("period.responder.type") == "user")
        .select(
            F.col("period.responder.id").alias("id_account"),
            *select_columns
        )
    )

    if "flattenedResponders" in df_final_period.select("period.*").columns:
        df_final_responders = df_final_responders.unionByName(
            df_final_period.select(
                F.explode_outer("period.flattenedResponders").alias("responder"),
                *select_columns
            ).filter(F.col("responder.type") == "user")
            .select(
                F.col("responder.id").alias("id_account"),
                *select_columns
            )
        )

    df_responders = df_final_responders.unionByName(df_base_responders)

    df_final = (
        df_responders.filter(
            (F.col("id_account").isNotNull())
        )
        .distinct()
    )

    db_info = DatalakeMetastoreService.get_db_info(
        environment, source, datalake_bucket
    )
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}{table_name}",
        source_df=df_final,
        partition_by=partition_cols,
    )
