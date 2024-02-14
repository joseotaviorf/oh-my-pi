import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from pyspark.sql.functions import col, from_unixtime, lit

JOB_NAME = "load_cdc_transactional"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")

TRANSACTION_ID_COLUMN_NAMES = {
    "mysql": "source.gtid",
    "postgres": None,  # TO BE DEFINED
}


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source_schema")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("cdc_connector_type")
    parser.add_argument("partitions")

    return parser.parse_args()


def load_df_into_transactional(df, datalake_bucket, schema, table_name, partitions):
    """
    Load DataFrame into Transactional Layer using Delta format

    :param datalake_bucket: S3 Bucket.
    :param schema: Database schema.
    :param table_name: Table name.
    :param ts_ms: Timestamp of when the operation was made into database.
    :return:
    """
    logger.info(
        f"m=load_df_into_transactional, file_format=delta, msg=Loading DataFrame into transactional layer..."
    )

    df.write.format("delta").option("mergeSchema", True).mode("overwrite").saveAsTable(
        f"datalake_{schema}_transactional.{table_name}",
        path=f"s3://{datalake_bucket}/transactional/{schema}/{table_name}/",
        partitionBy=partitions,
    )


def get_incoming_data(datalake_bucket, environment, schema, table_name, execution_date):
    """
    Reads incoming data as a DataFrame

    :param datalake_bucket: S3 Bucket.
    :param environment: forno / prod env.
    :param schema: Database schema.
    :param table_name: Table name.
    :param execution_date: Airflow DAG execution date.
    :return df:
    """
    path = (
        f"s3://{datalake_bucket}/incoming/{environment}-{schema}.{schema}.{table_name}/"
    )

    logger.info(
        f"m=get_incoming_data, execution_date={execution_date}, path={path}, msg=reading Incoming data..."
    )
    df = (
        spark.read.option("compression", "gzip")
        .json(path)
        .filter(
            f"year = {execution_date.year} AND month = {execution_date:%m} AND day = {execution_date:%d}"
        )
    )

    return df


def format_and_deduplicate_df(df, transaction_id_column, partitions):
    """
    Extract and format informations from Debezium payload
    and Deduplicate

    :param df: Debezium payload as DataFrame
    :param transaction_id_column: Column with unique transaction id
    :param partitions: Table partitions
    :return transactional_df:
    """
    logger.info(
        f"m=format_incoming_df, msg=Transforming Debezium payload into Transactional layer table..."
    )
    df_without_delete_op = df.filter(df.op != lit("d")).select(
        col("after").alias("data"),
        "op",
        col(transaction_id_column).alias("cdc_transaction_id"),
        "ts_ms",
        *partitions,
    )

    df_deletes = df.filter(df.op == lit("d")).select(
        col("before").alias("data"),
        "op",
        col(transaction_id_column).alias("cdc_transaction_id"),
        "ts_ms",
        *partitions,
    )

    if df_without_delete_op.isEmpty():
        incoming_df = df_deletes
    elif df_deletes.isEmpty():
        incoming_df = df_without_delete_op
    else:
        incoming_df = df_without_delete_op.unionByName(
            df_deletes, allowMissingColumns=True
        )

    transactional_df = incoming_df.select(
        col("data.*"),
        col("cdc_transaction_id"),
        col("op").alias("op_cdc"),
        from_unixtime(col("ts_ms") / 1000, "yyyy-MM-dd HH:mm:ss").alias(
            "ts_cdc_transaction"
        ),
        *partitions,
    )

    transactional_df = transactional_df.dropDuplicates(["cdc_transaction_id"])

    transactional_df = transactional_df.drop("cdc_transaction_id")

    return transactional_df


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source_schema = args.source_schema
    schema = args.schema
    table_name = args.table_name
    execution_date = args.execution_date
    cdc_connector_type = args.cdc_connector_type
    partitions = json.loads(args.partitions.replace("'", '"'))

    logger.info(
        f"""
        m=__main__, environment={environment},  datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, execution_date={execution_date},
        cdc_connector_type={cdc_connector_type}, partitions={partitions}
        msg=Starting spark job...
        """
    )

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    df = get_incoming_data(
        datalake_bucket, environment, source_schema, table_name, dt_execution
    )

    if df.isEmpty():
        logger.info(
            logger.info(
                "m=__main__, msg=Incoming Dataframe is empty, there is no change to propagate."
            )
        )
        return

    transaction_id_column = TRANSACTION_ID_COLUMN_NAMES.get(cdc_connector_type)

    transactional_df = format_and_deduplicate_df(df, transaction_id_column, partitions)

    logger.info("m=__main__, msg=Load table into transactional layer...")
    spark.sql(f"CREATE DATABASE IF NOT EXISTS `datalake_cdc_{schema}_transactional`")
    load_df_into_transactional(
        transactional_df, datalake_bucket, schema, table_name, partitions
    )


if __name__ == "__main__":
    main()
