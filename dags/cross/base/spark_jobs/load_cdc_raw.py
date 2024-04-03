from argparse import ArgumentParser

from bietlejuice.base.cdc.primary_key_identifiers.mysql_primary_key_identifier import (
    MySqlPrimaryKeyIdentifier,
)
from bietlejuice.base.cdc.schema_treatment.mysql_cdc_schema_finder import (
    MySqlCdcSchemaFinder,
)
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper
from bietlejuice.loaders.delta_loader import DeltaLoader
from quintoandar_logger import QuintoAndarLogger

from delta.tables import DeltaTable

from pyspark.sql.functions import row_number, col, make_date
from pyspark.sql.window import Window
from pyspark.sql.utils import AnalysisException

JOB_NAME = "load_cdc_raw"

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
    parser.add_argument("primary_keys", help="Comma separated list of primary keys")

    return parser.parse_args()


def get_df_from_transactional(
    datalake_bucket, schema, table_name, start_date, end_date
):
    """
    Extract Delta table from Transactional layer, transforms into a
    Dataframe.
    """
    path = f"s3://{datalake_bucket}/transactional/{schema}/{table_name}"
    try:
        transactional_delta_table = DeltaTable.forPath(spark, path)
        transactional_df = transactional_delta_table.toDF().filter(
            make_date(col("year"), col("month"), col("day")).between(
                start_date, end_date
            )
        )
    except AnalysisException as e:
        logger.info(
            f"m=get_df_from_transactional, msg=Unable to read delta table from transactional layer, error={e}"
        )
        return None

    return transactional_df


def dml_processor(transactional_df, primary_keys):
    """
    Applies deduplication to Transactional layer
    table by preserving the latest operation of
    a register.
    """
    logger.info(
        "m=dml_processor, msg=Applying deduplication and preserving the lasest operation on Transactional layer..."
    )
    window_spec = Window.partitionBy(*primary_keys).orderBy(
        transactional_df["ts_cdc_transaction"].desc(), transactional_df["cdc_binlog_position"].desc()
    )
    transactional_df = transactional_df.withColumn(
        "row_number", row_number().over(window_spec)
    )
    transactional_df = transactional_df.where(transactional_df["row_number"] == 1)
    transactional_df = transactional_df.drop("row_number")
    transactional_df = transactional_df.drop("cdc_binlog_position")

    return transactional_df


def main():
    args = parse_arguments()
    environment = args.env
    incoming_bucket = args.incoming_bucket
    datalake_bucket = args.datalake_bucket
    source_schema = args.source_schema
    schema = args.schema
    table_name = args.table_name.lower()
    start_date = args.start_date
    end_date = args.end_date
    if args.primary_keys:
        primary_keys = [key.strip() for key in args.primary_keys.split(",")]
    else:
        # Hardcoded for now, while we don't have other sources such as Postgres
        pk_identifier = MySqlPrimaryKeyIdentifier(
            MySqlCdcSchemaFinder(
                f"s3://{incoming_bucket}/{source_schema}/{environment}_{source_schema}.data/",
                start_date=start_date,
                end_date=end_date,
            ),
            datalake_table_schema=f"datalake_{schema}_raw",
        )
        primary_keys = pk_identifier.find_primary_keys(source_schema, args.table_name) # We don't use the table name in lowercase, because this is case sensitive

    logger.info(
        f"""
        m=__main__, environment={environment},  incoming_bucket={incoming_bucket}, datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, start_date={start_date}, end_date={end_date},
        primary_keys={primary_keys},
        msg=Starting spark job...
        """
    )

    transactional_df = get_df_from_transactional(
        datalake_bucket, schema, table_name, start_date, end_date
    )

    if not transactional_df:
        logger.info(
            f"""
            m=__main__, msg=Transactional Dataframe is empty, there is no changes to propagate.
            """
        )
        return

    transactional_df = dml_processor(transactional_df, primary_keys)

    full_raw_table_name = f"datalake_{schema}_raw.{table_name}"

    loader = DeltaLoader()
    loader.load_table(
        table_name=full_raw_table_name,
        path=f"s3://{datalake_bucket}/raw/{schema}/{table_name}/",
        source_df=transactional_df,
        merge_on=primary_keys,
        when_matched_update_condition="source.ts_cdc_transaction >= target.ts_cdc_transaction"
    )
    SparkTablePropertyHelper.set_property(full_raw_table_name, "primary_keys", ",".join(primary_keys))


if __name__ == "__main__":
    main()
