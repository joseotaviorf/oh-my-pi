import logging
import json
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_treatment import (
    MySqlCdcSchemaTreatment,
)

from pyspark.sql.functions import col, from_unixtime, lit, make_date

JOB_NAME = "load_cdc_transactional"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("incoming_bucket")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source_schema")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
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


def get_incoming_data(
    incoming_bucket, environment, schema, table_name, start_date, end_date
):
    """
    Reads incoming data as a DataFrame

    :param datalake_bucket: S3 Bucket.
    :param environment: forno / prod env.
    :param schema: Database schema.
    :param table_name: Table name.
    :param start_date: Airflow DAG start date.
    :param end_date: Airflow DAG end date.
    :return df:
    """
    path = (
        f"s3://{incoming_bucket}/{schema}/{environment}-{schema}.{schema}.{table_name}/"
    )

    logger.info(
        f"m=get_incoming_data, start_date={start_date}, end_date={end_date}, path={path}, msg=reading Incoming data..."
    )
    df = (
        spark.read.option("compression", "gzip")
        .json(path)
        .filter(
            make_date(col("year"), col("month"), col("day")).between(
                start_date, end_date
            )
        )
    )

    return df


def format_and_deduplicate_df(df, partitions):
    """
    Extract and format informations from Debezium payload
    and Deduplicate

    :param df: Debezium payload as DataFrame
    :param partitions: Table partitions
    :return transactional_df:
    """
    logger.info(
        f"m=format_incoming_df, msg=Transforming Debezium payload into Transactional layer table..."
    )
    df_without_delete_op = df.filter(df.op != lit("d")).select(
        col("after").alias("data"), "op", "ts_ms", *partitions
    )

    df_deletes = df.filter(df.op == lit("d")).select(
        col("before").alias("data"), "op", "ts_ms", *partitions
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
        col("op").alias("op_cdc"),
        from_unixtime(col("ts_ms") / 1000, "yyyy-MM-dd HH:mm:ss").alias(
            "ts_cdc_transaction"
        ),
        *partitions,
    )

    transactional_df = transactional_df.dropDuplicates()

    return transactional_df


def main():
    args = parse_arguments()
    environment = args.env
    incoming_bucket = args.incoming_bucket
    datalake_bucket = args.datalake_bucket
    source_schema = args.source_schema
    schema = args.schema
    table_name = args.table_name
    start_date = args.start_date
    end_date = args.end_date
    partitions = json.loads(args.partitions.replace("'", '"'))

    logger.info(
        f"""
        m=__main__, environment={environment},  datalake_bucket={datalake_bucket},
        incoming_bucket={incoming_bucket}, schema={schema}, table_name={table_name},
        start_date={start_date}, end_date={end_date}, partitions={partitions}
        msg=Starting spark job...
        """
    )

    df = get_incoming_data(
        incoming_bucket, environment, source_schema, table_name, start_date, end_date
    )

    if df.isEmpty():
        logger.info(
            logger.info(
                "m=__main__, msg=Incoming Dataframe is empty, there is no change to propagate."
            )
        )
        return

    transactional_df = format_and_deduplicate_df(df, partitions)

    logger.info("m=__main__, msg=Applying schema pre treatment...")

    # Hardcoded for now, while we don't have other sources such as Postgres
    pre_treatment = MySqlCdcSchemaTreatment(
        MySqlCdcSchemaFinder(
            f"s3://{incoming_bucket}/{source_schema}/{environment}-{source_schema}/"
        )
    )
    transactional_df = pre_treatment.treat_dataframe(
        source_schema, table_name, transactional_df
    )

    logger.info("m=__main__, msg=Load table into transactional layer...")
    spark.sql(f"CREATE DATABASE IF NOT EXISTS `datalake_cdc_{schema}_transactional`")
    load_df_into_transactional(
        transactional_df, datalake_bucket, schema, table_name, partitions
    )


if __name__ == "__main__":
    main()
