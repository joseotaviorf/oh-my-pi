from argparse import ArgumentParser, Namespace
from datetime import datetime
import json
from typing import List, Any

from bietlejuice.base.cdc.reader.date_range_partition_reader import DateRangePartitionReader
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.base_spark import BaseDBUtils
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper

from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.loaders.delta_loader import DeltaLoader

from pyspark.sql import DataFrame
from pyspark.sql.window import Window
from pyspark.sql.functions import row_number

from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_dms_cdc_raw"

logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("incoming_bucket")
    parser.add_argument("datalake_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
    parser.add_argument("primary_keys", help="Comma separated list of primary keys")
    parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )

    return parser.parse_args()


def get_df_from_dms_bucket(
    incoming_bucket: str,
    table_name: str,
    start_date: str,
    end_date: str,
    dbutils: Any,
):
    """
    Extract Delta table from DMS S3 bucket, transforms into a
    Dataframe.
    """
    base_path = f"s3://{incoming_bucket}/{table_name}/"
    reader = DateRangePartitionReader(
        dataframe_reader=spark.read,
        dbutils=dbutils,
        partition_format="%Y/%m/%d"
        )
    try:
        logger.info(
            f"m=get_df_from_dms_bucket, start_date={start_date}, end_date={end_date}, path={base_path}, msg=reading DMS data..."
        )
        return reader.load(
            base_path,
            datetime.strptime(start_date, "%Y-%m-%d"),
            datetime.strptime(end_date, "%Y-%m-%d"),
            "parquet",
        )
    except FileNotFoundError:
        logger.info(
            f"m=get_df_from_dms_bucket, start_date={start_date}, end_date={end_date}, msg=No incoming data found in the time interval. Returning empty DataFrame."
        )
        return None

def get_primary_key(args: Namespace, df: DataFrame) -> List[str]:
    if args.primary_keys:
        primary_keys = [key.strip() for key in args.primary_keys.split(",")]
    else:
        primary_keys = [col_name for col_name in df.columns if col_name.startswith("pk")]
    return primary_keys

def dml_processor(df_dms: DataFrame, primary_keys: List) -> DataFrame:
    """
    Applies deduplication to DMS layer
    table by preserving the latest operation of
    a register.
    """
    logger.info(
        f"m=dml_processor, msg=Applying deduplication and preserving the latest operation of DMS Bucket..."
    )
    window_spec = Window.partitionBy(*primary_keys).orderBy(
        df_dms["event_timestamp"].desc()
    )
    df_dms = df_dms.withColumn(
        "row_number", row_number().over(window_spec)
    )
    df_dms_processor = df_dms.where(df_dms["row_number"] == 1)
    df_dms_processor = df_dms_processor.drop("row_number")

    return df_dms_processor

def main():
    args = parse_arguments()
    environment = args.env
    incoming_bucket = args.incoming_bucket
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name.lower()
    start_date = args.start_date
    end_date = args.end_date
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    logger.info(
        f"""
        m=__main__, environment={environment},  incoming_bucket={incoming_bucket}, datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, start_date={start_date}, end_date={end_date},
        msg=Starting spark job...
        """
    )

    df_dms = get_df_from_dms_bucket(
        incoming_bucket=incoming_bucket,
        table_name=table_name,
        start_date=start_date,
        end_date=end_date,
        dbutils=dbutils,
    )

    if not df_dms:
        logger.info(
            f"""
            m=__main__, msg=DMS Dataframe is empty, there is no changes to propagate.
            """
        )
        return

    primary_keys = get_primary_key(args=args, df=df_dms)

    if not primary_keys:
        raise Exception(
            f"""
            m=__main__, msg=No primary keys detected, please provide the primary keys manually in the DAG declaration file,
            or review the values informed"""
        )

    df_dms_processor = dml_processor(df_dms=df_dms, primary_keys=primary_keys)

    full_raw_table_name = f"datalake_{schema}_raw.{table_name}"
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_raw_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)

    loader = DeltaLoader()
    loader.load_table(
        table_name=full_raw_table_name,
        path=f"s3://{datalake_bucket}/raw/{schema}/{table_name}/",
        source_df=df_dms_processor,
        merge_on=primary_keys,
        when_matched_update_condition="source.event_timestamp >= target.event_timestamp"
    )
    SparkTablePropertyHelper.set_property(full_raw_table_name, "primary_keys", ",".join(primary_keys))

    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()

if __name__ == "__main__":
    main()
