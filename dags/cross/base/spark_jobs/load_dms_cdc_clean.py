import json
import re

from argparse import ArgumentParser, Namespace
from typing import List

from bietlejuice.base.cdc.primary_key_identifiers.clean_primary_key_identifier import (
    CleanPrimaryKeyIdentifier,
)
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.loaders.delta_loader import DeltaLoader

from pyspark.sql.functions import col

from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_dms_cdc_clean"

logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("data_documentation_bucket")
    parser.add_argument("schema")
    parser.add_argument("table_name")
    parser.add_argument("start_date")
    parser.add_argument("end_date")
    parser.add_argument("primary_keys", help="Comma separated list of primary keys for the clean table")
    parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )

    return parser.parse_args()


def get_primary_keys_from_args(args: Namespace) -> List[str]:
    """
    Returns the primary keys of the clean table. It is either informed manually, or identified automatically by reading
    the lineage file.
    """

    if args.primary_keys:
       return [key.strip() for key in args.primary_keys.split(",")]

    clean_pk_identifier = CleanPrimaryKeyIdentifier(
        args.data_documentation_bucket,
    )
    return clean_pk_identifier.find_primary_keys(args.schema, args.table_name)


def insert_columns_into_query(query:str, columns:List[str]) -> str:
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


def main():
    args = parse_arguments()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    start_date = args.start_date
    end_date = args.end_date
    clean_primary_keys = get_primary_keys_from_args(args)
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    logger.info(
        f"""
        m=__main__, environment={environment}, dag_name={dag_name}
        datalake_bucket={datalake_bucket},
        schema={schema}, table_name={table_name}, start_date={start_date}, end_date={end_date},
        clean_primary_keys={clean_primary_keys},
        msg=Starting spark job...
        """
    )

    clean_query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=dag_name,
        layer="clean",
        table_name=table_name,
    )

    cdc_columns = ["Op", "event_timestamp"]

    query_with_cdc_columns = insert_columns_into_query(clean_query, cdc_columns)
    clean_updates_df = spark.sql(query_with_cdc_columns).filter(col("event_timestamp").cast("date").between(start_date, end_date))

    full_clean_table_name = f"datalake_{schema}_clean.{table_name}"
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_clean_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(full_clean_table_name)

    loader = DeltaLoader()
    loader.load_table(
        table_name=full_clean_table_name,
        path=f"s3://{datalake_bucket}/clean/{schema}/{table_name}/",
        source_df=clean_updates_df,
        merge_on=clean_primary_keys,
        when_not_matched_insert_condition="source.Op != 'D'",
        when_matched_update_condition="source.event_timestamp >= target.event_timestamp",
        when_matched_delete_condition="source.Op = 'D'",
    )

    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()


if __name__ == "__main__":
    main()
