from argparse import ArgumentParser
from datetime import datetime
import re
from pyspark.sql.functions import col
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService

from quintoandar_logger import QuintoAndarLogger

from delta.tables import DeltaTable

JOB_NAME = "load_cdc_clean"

logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
    parser.add_argument("table_id")

    return parser.parse_args()


def insert_columns_into_query(query, columns):
    """
    Insert CDC columns to persist those informations
    through clean table.
    """
    logger.info(
        f"m=insert_columns_into_query, columns={columns}, msg=Inserting CDC columns into query..."
    )
    split_values_in_from = re.split(
        r"(FROM\s+`?\w+\`?\.`?\w+`?)", query, flags=re.IGNORECASE
    )
    split_values_in_from[-3] += "".join([f",{column}\n" for column in columns])
    rejoined_query = "".join(split_values_in_from)
    return rejoined_query


def load_clean_delta_table(full_table_name):
    """
    Load and return Clean Delta table if exists.
    """
    logger.info(
        f"m=load_clean_delta_table, table_name={full_table_name}, msg=Reading Clean Delta table..."
    )
    try:
        delta_table = DeltaTable.forName(spark, full_table_name)
    except Exception as e:
        logger.info(
            f"m=load_clean_delta_table, msg=Unable to read delta table, error={e}"
        )
        return None

    return delta_table


def create_clean_delta_table(
    df, full_clean_table_name, datalake_bucket, schema, table_name
):
    """
    Create Clean Delta table.
    """
    logger.info(
        f"m=create_clean_delta_table, msg=Creating clean table using Delta format..."
    )
    df.write.format("delta").option("mergeSchema", True).mode("overwrite").saveAsTable(
        full_clean_table_name,
        path=f"s3://{datalake_bucket}/clean/{schema}/{table_name}/",
    )
    clean_delta_table = DeltaTable.forName(spark, full_clean_table_name)

    return clean_delta_table


def apply_deletes_to_clean_table(clean_delta_table, table_id, clean_updates):
    """
    Updates clean table based on raw modifications by applying
    deletes.
    """
    logger.info(
        f"m=consolidate_clean_table, msg=Updating clean table based on raw modifications"
    )
    clean_delta_table.alias("clean_table").merge(
        clean_updates.alias("clean_updates"),
        f"clean_table.{table_id} = clean_updates.{table_id}",
    ).whenMatchedDelete(condition=f"clean_updates.op_cdc = 'd'").whenMatchedUpdate(
        condition=f"clean_updates.ts_cdc_transaction >= clean_table.ts_cdc_transaction",
        set=dict((col, f"clean_updates.{col}") for col in clean_updates.columns),
    ).whenNotMatchedInsert(
        condition="clean_updates.op_cdc != 'd'",
        values=dict((col, f"clean_updates.{col}") for col in clean_updates.columns),
    ).execute()


def main():
    args = parse_arguments()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    start_date = args.start_date
    end_date = args.end_date
    table_id = args.table_id

    logger.info(
        f"""
        m=__main__, environment={environment}, dag_name={dag_name}
        datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, start_date={start_date}, end_date={end_date},
        clean_table_id={table_id}
        msg=Starting spark job...
        """
    )

    clean_query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=dag_name,
        layer="clean",
        table_name=table_name,
    )

    cdc_columns = ["op_cdc", "ts_cdc_transaction"]

    query_with_cdc_columns = insert_columns_into_query(clean_query, cdc_columns)
    clean_updates_df = spark.sql(query_with_cdc_columns).filter(col("ts_cdc_transaction").cast("date").between(start_date, end_date))

    spark.sql(f"CREATE DATABASE IF NOT EXISTS `datalake_{schema}_clean`")
    full_clean_table_name = f"`datalake_{schema}_clean`.`{table_name}`"

    clean_delta_table = load_clean_delta_table(full_clean_table_name)

    if not clean_delta_table:
        clean_updates_without_deletes = clean_updates_df.filter(
            clean_updates_df.op_cdc != "d"
        )
        clean_delta_table = create_clean_delta_table(
            clean_updates_without_deletes,
            full_clean_table_name,
            datalake_bucket,
            schema,
            table_name,
        )

    apply_deletes_to_clean_table(clean_delta_table, table_id, clean_updates_df)


if __name__ == "__main__":
    main()
