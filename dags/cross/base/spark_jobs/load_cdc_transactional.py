import logging
import json
from argparse import ArgumentParser
from bietlejuice.base.spark.base_spark import BaseDBUtils
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.airflow.enums.database_type_enum import DatabaseTypeEnum
from bietlejuice.base.cdc.reader.date_range_partition_reader import DateRangePartitionReader
from bietlejuice.base.cdc.schema_treatment.cdc_schema_finder_factory import (
    CdcSchemaFinderFactory,
)
from bietlejuice.base.cdc.schema_treatment.cdc_schema_treatment_factory import (
    CdcSchemaTreatmentFactory,
)
from bietlejuice.base.cdc.schema_treatment.schema_changes_notifier import (
    SchemaChangesNotifier,
)
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum


from bietlejuice.loaders.delta_loader import DeltaLoader
from datetime import datetime
from pyspark.sql.functions import col, to_timestamp, lit

JOB_NAME = "load_cdc_transactional"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("incoming_bucket")
    parser.add_argument("datalake_bucket")
    parser.add_argument("database_type")
    parser.add_argument("source_database")
    parser.add_argument("source_schema")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
    parser.add_argument("partitions")
    parser.add_argument("dbutils_secret_key")

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
        partition_by=partitions,
    )


def get_incoming_data(
    incoming_bucket,
    environment,
    source_database,
    schema,
    table_name,
    start_date,
    end_date,
    dbutils,
):
    """
    Reads incoming data as a DataFrame

    :param datalake_bucket: S3 Bucket.
    :param environment: forno / prod env.
    :param source_database: Database name.
    :param schema: Database schema.
    :param table_name: Table name.
    :param start_date: Airflow DAG start date.
    :param end_date: Airflow DAG end date.
    :param dbutils: DButils reference.
    :return df:
    """
    base_path = f"s3://{incoming_bucket}/{source_database}/{environment}_{source_database}.data.{schema}.{table_name}/"
    reader = DateRangePartitionReader(spark.read.option("compression", "gzip"), dbutils)
    try:
        logger.info(
            f"m=get_incoming_data, start_date={start_date}, end_date={end_date}, path={base_path}, msg=reading Incoming data..."
        )
        return reader.load(
            base_path,
            datetime.strptime(start_date, "%Y-%m-%d"),
            datetime.strptime(end_date, "%Y-%m-%d"),
            "json",
        )
    except FileNotFoundError:
        logger.info(
            f"m=get_incoming_date, start_date={start_date}, end_date={end_date}, msg=No incoming data found in the time interval. Returning empty DataFrame."
        )
        return None


def format_and_deduplicate_df(df, partitions, database_type):
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

    if database_type == "mysql":
        cdc_binlog_position_column = "source.pos"
    elif database_type == "postgres":
        cdc_binlog_position_column = "source.lsn"
    else:
        raise ValueError(
            f"m=format_and_deduplicate_df, database_type={database_type}, msg=Database not supported."
        )

    transactional_df = incoming_df.select(
        col("data.*"),
        col("op").alias("op_cdc"),
        to_timestamp(col("ts_ms") / 1000).alias("ts_cdc_transaction"),
        col(cdc_binlog_position_column).alias("cdc_binlog_position"),
        *partitions,
        to_timestamp(col("source.ts_ms") / 1000).alias("ts_database_transaction"),
    )

    transactional_df = transactional_df.dropDuplicates()

    return transactional_df


def main():
    args = parse_arguments()
    environment = args.env
    incoming_bucket = args.incoming_bucket
    datalake_bucket = args.datalake_bucket
    database_type = args.database_type
    source_database = args.source_database
    source_schema = args.source_schema
    schema = args.schema
    table_name = args.table_name
    start_date = args.start_date
    end_date = args.end_date
    partitions = json.loads(args.partitions.replace("'", '"'))
    dbutils_secret_key = args.dbutils_secret_key
    full_table_name = f"datalake_{schema}_transactional.{table_name}"

    logger.info(
        f"""
        m=__main__, environment={environment},  datalake_bucket={datalake_bucket}, database_type={database_type},
        source_database={source_database}, source_schema={source_schema}, incoming_bucket={incoming_bucket}, schema={schema},
        table_name={table_name}, start_date={start_date}, end_date={end_date}, partitions={partitions}, dbutils_secret_key={dbutils_secret_key},
        msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    df = get_incoming_data(
        incoming_bucket,
        environment,
        source_database,
        source_schema,
        table_name,
        start_date,
        end_date,
        dbutils,
    )

    if df is None:
        if not spark.catalog.tableExists(full_table_name):
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

    transactional_df = format_and_deduplicate_df(df, partitions, database_type)

    logger.info("m=__main__, msg=Applying schema pre treatment...")

    pre_treatment = CdcSchemaTreatmentFactory(
        schema_finder=CdcSchemaFinderFactory(
            incoming_bucket=incoming_bucket,
            source_database=source_database,
            source_schema=source_schema,
            environment=environment,
            start_date=start_date,
            end_date=end_date,
            dbutils_secret_key=dbutils_secret_key,
        ).get_cdc_schema_finder(DatabaseTypeEnum(database_type)),
        datalake_table_schema=f"datalake_{schema}_transactional",
    ).get_cdc_schema_treatment(DatabaseTypeEnum(database_type))
    transactional_df = pre_treatment.treat_dataframe(table_name, transactional_df)

    SchemaChangesNotifier.alert_schema_changes(
        full_table_name,
        transactional_df,
        dbutils.secrets.get(
            scope="quintoandar", key=GchatWebhooksEnum.GCHAT_SCHEMA_CHANGES
        ),
    )

    logger.info("m=__main__, msg=Load table into transactional layer...")
    load_df_into_transactional(
        transactional_df, datalake_bucket, schema, table_name.lower(), partitions
    )


if __name__ == "__main__":
    main()
