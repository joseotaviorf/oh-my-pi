import json
import logging
from argparse import ArgumentParser, Namespace
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.row_filter import RowFilter
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.base.validation.target_resolver import managed_table_fqn
from bietlejuice.pipeline.delta_table_loader_pipeline import DeltaTableLoaderPipeline

JOB_NAME = "load_delta_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def main():
    global spark
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session(JOB_NAME)
    args = parse_arguments()
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    row_filter_column_key = args.row_filter_column_key
    row_filter_function_name = args.row_filter_function_name

    logger.info(
        f"m={JOB_NAME}, env={args.env}, bucket={args.bucket}, layer={args.layer}, "
        + f"database_base_name={args.database_base_name}, relative_query_path={args.relative_query_path}, "
        + f"table_name={args.table_name}, extraction_type={args.extraction_type}, merge_on={args.merge_on}, "
        + f"when_not_matched_insert_condition={args.when_not_matched_insert_condition}, "
        + f"when_matched_update_condition={args.when_matched_update_condition}, "
        + f"when_matched_delete_condition={args.when_matched_delete_condition}, "
        + f"when_not_matched_by_source_delete_condition={args.when_not_matched_by_source_delete_condition}, "
        + f"when_matched_operation={args.when_matched_operation}, "
        + f"when_not_matched_operation={args.when_not_matched_operation}, "
        + "msg=Job execution started"
    )

    merge_on = json.loads(args.merge_on)

    query_template_params = get_query_template_params(
        execution_date=args.execution_date,
        additional_query_template_params=json.loads(
            args.additional_query_template_params
        ),
    )

    metastore_kwargs = {}
    if args.layer == "transformation":
        metastore_kwargs["transformation_grade"] = args.transformation_grade
    spark_ms = SparkMetastoreHelper(
        args.bucket,
        args.layer,
        args.database_base_name,
        args.table_name,
        all_tables=False,
        **metastore_kwargs,
    )
    database_name = spark_ms.spark_database_name
    database_location = spark_ms.database_location.replace("s3a://", "s3://")
    source_table_name = args.table_name
    write_table_name = args.table_name
    target_database_name = database_name
    target_database_location = database_location
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        target_database_name = args.target_database_name
        write_table_name = args.target_table_name
        target_database_location = validation_database_location(
            args.bucket, database_name
        ).replace("s3a://", "s3://")
    privileges_table = managed_table_fqn(
        database_name,
        source_table_name,
        args.target_database_name,
        args.target_table_name,
    )

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=args.relative_query_path, layer=args.layer, table_name=args.table_name
    )

    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, privileges_table
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(privileges_table)

    column_mapping_mode = json.loads(args.column_mapping_mode)

    table_loader_pipeline = DeltaTableLoaderPipeline(
        database_name=database_name,
        table_name=write_table_name,
        database_location=database_location,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
        layer=args.layer,
        query=query,
        partitions=json.loads(args.partitions),
        query_template_params=query_template_params,
        spark_session_configs=json.loads(args.spark_session_configs),
        merge_schema=(args.extraction_type == "incremental"),
        merge_on=merge_on,
        when_not_matched_insert_condition=json.loads(
            args.when_not_matched_insert_condition
        ),
        when_matched_update_condition=json.loads(args.when_matched_update_condition),
        when_matched_delete_condition=json.loads(args.when_matched_delete_condition),
        when_not_matched_by_source_delete_condition=json.loads(
            args.when_not_matched_by_source_delete_condition
        ),
        when_matched_operation=json.loads(args.when_matched_operation),
        when_not_matched_operation=json.loads(args.when_not_matched_operation),
        table_privileges=table_privileges,
        table_properties=json.loads(args.table_properties)
        if args.table_properties
        else None,
        column_mapping_mode=column_mapping_mode,
        spark=spark,
    )
    table_loader_pipeline.run()

    rowfilter = RowFilter(spark)

    if row_filter_column_key and not rowfilter.has_row_filter(privileges_table):
        rowfilter.apply_row_filter(
            privileges_table, row_filter_column_key, row_filter_function_name
        )


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("bucket", type=str, help="bucket name")
    parser.add_argument("layer", type=str, help="clean/enrich values to save data to")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument(
        "relative_query_path",
        type=str,
        help="relative query path for sql file to create table",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument(
        "partitions", type=str, help="JSON string with list of partitions"
    )
    parser.add_argument(
        "execution_date", type=str, help="execution date in format YYYY-MM-DD"
    )
    parser.add_argument("extraction_type", type=str, help="full/incremental")
    parser.add_argument(
        "spark_session_configs",
        type=str,
        help="custom config parameters to be set in spark session",
    )
    parser.add_argument(
        "additional_query_template_params",
        type=str,
        help="additional query parameters not including date params",
    )
    parser.add_argument(
        "merge_on",
        type=str,
        help="Column name to be used for merge operation",
    )
    parser.add_argument(
        "when_not_matched_insert_condition",
        type=str,
        help="Condition to be used for insert operation",
    )
    parser.add_argument(
        "when_matched_update_condition",
        type=str,
        help="Condition to be used for update operation",
    )
    parser.add_argument(
        "when_matched_delete_condition",
        type=str,
        help="Condition to be used for delete operation",
    )
    parser.add_argument(
        "when_not_matched_by_source_delete_condition",
        type=str,
        help="Condition to be used for delete operation when target rows don't exist in source",
    )
    parser.add_argument(
        "when_matched_operation",
        type=str,
        help="Which columns to update when there is a match, and with which values. "
        + "Should be a dictionary, with the keys being the columns to be updated, and "
        + "the values being what to update them with. You can use source.<column_name> "
        + "or target.<column_name> to disambiguate between the query result and the existing value.",
    )
    parser.add_argument(
        "when_not_matched_operation",
        type=str,
        help="Which columns to insert when there is not a match, and with which values. "
        + "Should be a dictionary, with the keys being the columns to be updated, and "
        + "the values being what to update them with. You can use source.<column_name> "
        + "or target.<column_name> to disambiguate between the query result and the existing value.",
    )
    parser.add_argument(
        "-cm",
        "--column-mapping-mode",
        type=str,
        default="null",
        help=(
            "JSON-encoded delta.columnMapping.mode. Use null for default behavior. "
            "Set to name when logical column names contain characters not allowed in Parquet "
            "(see Delta column mapping; same token as in Delta table properties)."
        ),
    )
    parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )
    parser.add_argument(
        "-tr",
        "--table-properties",
        type=lambda arg: None if not arg else arg,
        help="json string with dict of custom table properties",
        required=False,
        default=None,
    )
    parser.add_argument(
        "-rfck",
        "--row-filter-column-key",
        type=lambda arg: None if not arg else arg,
        help="Column key to be used in row filter",
        required=False,
        default=None,
    )
    parser.add_argument(
        "-rf",
        "--row-filter-function-name",
        type=lambda arg: None if not arg else arg,
        help="Name of the function to be used in row filter",
        required=False,
        default=None,
    )
    parser.add_argument(
        "-tdn",
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "-ttn",
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "--transformation-grade",
        type=str,
        choices=["clean", "curated"],
        required=False,
        default=None,
        help="Required when layer is transformation: clean or curated",
    )

    return parser.parse_args()


def get_query_template_params(
    execution_date: str, additional_query_template_params: dict
) -> dict:
    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    query_template_params = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }
    query_template_params.update(additional_query_template_params)
    return query_template_params


if __name__ == "__main__":
    from bietlejuice.base.spark.spark_session_factory import run_spark_entrypoint

    run_spark_entrypoint(main)
