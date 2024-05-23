import logging
import json
from argparse import ArgumentParser, Namespace
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.pipeline.delta_table_loader_pipeline import DeltaTableLoaderPipeline


JOB_NAME = "load_delta_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def main():
    args = parse_arguments()

    logger.info(
        f"m={JOB_NAME}, env={args.env}, bucket={args.bucket}, layer={args.layer}, "
        + f"database_base_name={args.database_base_name}, relative_query_path={args.relative_query_path}, "
        + f"table_name={args.table_name}, extraction_type={args.extraction_type}, merge_on={args.merge_on}, "
        + f"when_not_matched_insert_condition={args.when_not_matched_insert_condition}, "
        + f"when_matched_update_condition={args.when_matched_update_condition}, when_matched_delete_condition={args.when_matched_delete_condition}, msg=Job execution started"
    )

    merge_on = json.loads(args.merge_on)

    query_template_params = get_query_template_params(
        execution_date=args.execution_date,
        additional_query_template_params=json.loads(args.additional_query_template_params),
    )

    spark_ms = SparkMetastoreHelper(args.bucket, args.layer, args.database_base_name, args.table_name, all_tables=False)
    database_name = spark_ms.spark_database_name
    database_location = spark_ms.database_location.replace("s3a://", "s3://") # Seems to be faster

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=args.relative_query_path,
        layer=args.layer,
        table_name=args.table_name,
    )

    table_loader_pipeline = DeltaTableLoaderPipeline(
        database_name=database_name,
        table_name=args.table_name,
        database_location=database_location,
        layer=args.layer,
        query=query,
        partitions=json.loads(args.partitions),
        query_template_params=query_template_params,
        spark_session_configs=json.loads(args.spark_session_configs),
        merge_schema=(args.extraction_type == "incremental"),
        merge_on=merge_on,
        when_not_matched_insert_condition=json.loads(args.when_not_matched_insert_condition),
        when_matched_update_condition=json.loads(args.when_matched_update_condition),
        when_matched_delete_condition=json.loads(args.when_matched_delete_condition)
    )
    table_loader_pipeline.run()

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
    parser.add_argument("partitions", type=str, help="JSON string with list of partitions")
    parser.add_argument("execution_date", type=str, help="execution date in format YYYY-MM-DD")
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

    return parser.parse_args()

def get_query_template_params(execution_date: str, additional_query_template_params: dict) -> dict:
    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    query_template_params = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }
    query_template_params.update(additional_query_template_params)
    return query_template_params

if __name__ == "__main__":
    main()
