from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from delta.tables import DeltaTable

from pyspark.sql.functions import row_number
from pyspark.sql.window import Window

JOB_NAME = "load_cdc_raw"

logger = QuintoAndarLogger(JOB_NAME)

spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    parser.add_argument("table_id")

    return parser.parse_args()


def get_df_from_transactional(datalake_bucket, schema, table_name, execution_date):
    """
    Extract Delta table from Transactional layer, transforms into a
    Dataframe.
    """
    path = f"s3://{datalake_bucket}/transactional/{schema}/{table_name}/year={execution_date.year}/month={execution_date:%m}/day={execution_date:%d}"
    transactional_delta_table = DeltaTable.forPath(spark, path)

    transactional_df = transactional_delta_table.toDF()

    return transactional_df


def load_raw_delta_table(full_table_name):
    """
    Load and return raw Delta table if exists.
    """
    logger.info(
        f"m=load_raw_delta_table, table_name={full_table_name}, msg=Reading raw Delta table..."
    )
    try:
        delta_table = DeltaTable.forName(spark, full_table_name)
    except Exception as e:
        logger.info(
            f"m=load_raw_delta_table, msg=Unable to read delta table, error={e}"
        )
        return None

    return delta_table


def create_raw_delta_table(
    df, full_raw_table_name, datalake_bucket, schema, table_name
):
    """
    Create raw Delta table.
    """
    logger.info(
        f"m=create_raw_delta_table, msg=Creating raw table using Delta format..."
    )
    df.write.format("delta").option("mergeSchema", True).mode("overwrite").saveAsTable(
        full_raw_table_name,
        path=f"s3://{datalake_bucket}/raw/{schema}/{table_name}/",
    )
    raw_delta_table = DeltaTable.forName(spark, full_raw_table_name)

    return raw_delta_table


def dml_processor(transactional_df, table_id):
    """
    Applies deduplication to Transactional layer
    table by preserving the latest operation of
    a register.
    """
    logger.info(
        "m=dml_processor, msg=Applying deduplication and preserving the lasest operation on Transactional layer..."
    )
    window_spec = Window.partitionBy(transactional_df[table_id]).orderBy(
        transactional_df["ts_cdc_transaction"].desc()
    )
    transactional_df = transactional_df.withColumn(
        "row_number", row_number().over(window_spec)
    )
    transactional_df = transactional_df.where(transactional_df["row_number"] == 1)
    transactional_df = transactional_df.drop("row_number")

    return transactional_df


def merge_transactional_into_raw_table(
    transactional_df,
    table_id,
    raw_delta_table,
):
    """
    Apply merge operations to Delta table, to consolidate
    Transactional layer table DML operations.
    """
    logger.info(
        "m=merge_transactional_into_raw_table, msg=Updating Raw Delta table with Transactional table using soft-delete strategy..."
    )
    raw_delta_table.alias("raw_table").merge(
        transactional_df.alias("transactional_table"),
        f"raw_table.{table_id} = transactional_table.{table_id}",
    ).whenMatchedUpdate(
        set=dict(
            (col, f"transactional_table.{col}") for col in transactional_df.columns
        )
    ).whenNotMatchedInsert(
        values=dict(
            (col, f"transactional_table.{col}") for col in transactional_df.columns
        )
    ).execute()


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    execution_date = args.execution_date
    table_id = args.table_id

    logger.info(
        f"""
        m=__main__, environment={environment},  datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, execution_date={execution_date},
        table_id={table_id},
        msg=Starting spark job...
        """
    )

    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    transactional_df = get_df_from_transactional(
        datalake_bucket, schema, table_name, dt_execution
    )

    transactional_df = dml_processor(transactional_df, table_id)

    spark.sql(f"CREATE DATABASE IF NOT EXISTS `datalake_{schema}_raw`")
    full_raw_table_name = f"`datalake_{schema}_raw`.`{table_name}`"

    raw_delta_table = load_raw_delta_table(full_raw_table_name)

    if not raw_delta_table:
        raw_delta_table = create_raw_delta_table(
            transactional_df,
            full_raw_table_name,
            datalake_bucket,
            schema,
            table_name,
        )

    merge_transactional_into_raw_table(transactional_df, table_id, raw_delta_table)


if __name__ == "__main__":
    main()
