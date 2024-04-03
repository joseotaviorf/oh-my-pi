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
from bietlejuice.base.cdc.schema_treatment.schema_changes_notifier import (
    SchemaChangesNotifier,
)
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum


from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import col, to_timestamp, lit, make_date
from pyspark.sql.utils import AnalysisException

JOB_NAME = "load_cdc_transactional"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


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

    loader = DeltaLoader()
    loader.load_table(
        f"datalake_{schema}_transactional.{table_name}",
        path=f"s3://{datalake_bucket}/transactional/{schema}/{table_name}/",
        source_df=df,
        partition_by=partitions
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
        f"s3://{incoming_bucket}/{schema}/{environment}_{schema}.data.{schema}.{table_name}/"
    )

    logger.info(
        f"m=get_incoming_data, start_date={start_date}, end_date={end_date}, path={path}, msg=reading Incoming data..."
    )
    try:
        df = (
            spark.read.option("compression", "gzip")
            .json(path)
            .filter(
                make_date(col("year"), col("month"), col("day")).between(
                    start_date, end_date
                )
            )
        )
    except AnalysisException as e:
        if e.getErrorClass() != "PATH_NOT_FOUND":
            raise e
        logger.info(
            f"m=get_incoming_data, msg=Path {path} not found, returning empty DataFrame."
        )
        return None

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
        col("after").alias("data"), "op", "ts_ms", "source", *partitions
    )

    df_deletes = df.filter(df.op == lit("d")).select(
        col("before").alias("data"), "op", "ts_ms", "source", *partitions
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
        to_timestamp(col("ts_ms") / 1000).alias(
            "ts_cdc_transaction"
        ),
        col("source.pos").alias("cdc_binlog_position"),
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
    full_table_name = f"datalake_{schema}_transactional.{table_name}"

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

    if df is None:
        if not spark.catalog.tableExists(
            full_table_name
        ):
            raise FileNotFoundError(
                "No data was found in the incoming bucket, and the table does not exist in the datalake. Since this is the first execution, "
                "please make sure to trigger a snapshot of the table in the source database."
            )

        logger.info(
            f"m=__main__, msg=Incoming Dataframe is None, there is no change to propagate."
        )
        return

    if df.isEmpty():
        logger.info(
            logger.info(
                "m=__main__, msg=Incoming Dataframe is empty, there is no change to propagate."
            )
        )
        return

    transactional_df = format_and_deduplicate_df(df, partitions)

    logger.info("m=__main__, msg=Applying schema pre treatment...")

    # Hardcoded for now, while we don't have other sources such as Postgres.
    pre_treatment = MySqlCdcSchemaTreatment(
        MySqlCdcSchemaFinder(
            f"s3://{incoming_bucket}/{source_schema}/{environment}_{source_schema}.data/",
            start_date=start_date,
            end_date=end_date,
        ),
        datalake_table_schema=f"datalake_{schema}_transactional",
    )
    transactional_df = pre_treatment.treat_dataframe(
        source_schema, table_name, transactional_df
    )

    SchemaChangesNotifier.alert_schema_changes(
        full_table_name,
        transactional_df,
        dbutils.secrets.get(scope="quintoandar", key=GchatWebhooksEnum.GCHAT_SCHEMA_CHANGES)
    )

    logger.info("m=__main__, msg=Load table into transactional layer...")
    load_df_into_transactional(
        transactional_df, datalake_bucket, schema, table_name.lower(), partitions
    )


if __name__ == "__main__":
    main()
