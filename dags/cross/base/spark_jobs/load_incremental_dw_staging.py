import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.dw_metastore_service import DWMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.pipeline.incremental_table_loader_pipeline import (
    IncrementalTableLoaderPipeline,
)

JOB_NAME = "load_incremental_dw_staging"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("table_name")
    parser.add_argument("partitions")
    parser.add_argument("execution_date")
    parser.add_argument("extra_query_template_params")
    parser.add_argument("relative_query_path")
    parser.add_argument("spark_session_configs")
    parser.add_argument("tree_path")
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

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    table_name = args.table_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    execution_date = args.execution_date
    extra_query_template_params = json.loads(args.extra_query_template_params)
    relative_query_path = args.relative_query_path
    spark_session_configs = json.loads(args.spark_session_configs)
    tree_path = args.tree_path

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket},  dw_schema={dw_schema}, "
        f"relative_query_path={relative_query_path}, table_name={table_name}, "
        f"tree_path={tree_path}, msg=Job execution started"
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_dict = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }
    extra_query_template_params.update(dt_dict)

    dw_staging_db_name, dw_staging_db_location = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW_STAGING.value
    )

    source_table_name = table_name
    write_table_name = table_name
    target_database_name = dw_staging_db_name
    target_database_location = dw_staging_db_location
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_dw_database_location,
        )

        target_database_name = args.target_database_name
        write_table_name = args.target_table_name
        target_database_location = validation_dw_database_location(
            dw_bucket, dw_staging_db_name
        )

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=relative_query_path,
        layer=LayerEnum.DW.value,
        intermediate_path=tree_path,
        table_name=source_table_name,
    )

    table_loader_pipeline = IncrementalTableLoaderPipeline(
        database_name=dw_staging_db_name,
        table_name=write_table_name,
        database_location=dw_staging_db_location,
        layer=LayerEnum.DW_STAGING.value,
        query=query,
        spark_session_configs=spark_session_configs,
        partitions=partitions,
        query_template_params=extra_query_template_params,
        target_database_name=target_database_name,
        target_database_location=target_database_location,
    )
    table_loader_pipeline.run()
