import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH, DWMetastoreService
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.pipeline import IncrementalTableLoaderPipeline
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "load_incremental_table_to_dw_staging_schema"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("dw_bucket", type=str, help="dw bucket")
    parser.add_argument("dw_schema", type=str, help="dw schema")
    parser.add_argument(
        "relative_query_path",
        type=str,
        help="relative query path for sql file to create table",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("partitions")
    parser.add_argument("execution_date")
    parser.add_argument("additional_query_template_params")
    parser.add_argument(
        "cluster_config_params",
        type=str,
        help="custom config parameters to be set in spark cluster",
    )
    parser.add_argument("tree_path", type=str, help="path to reach the query place")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    relative_query_path = args.relative_query_path
    table_name = args.table_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    execution_date = args.execution_date
    query_template_params = json.loads(args.additional_query_template_params)
    cluster_config_params = json.loads(args.cluster_config_params)
    tree_path = args.tree_path

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket},  dw_schema={dw_schema}, "
        + f"relative_query_path={relative_query_path}, table_name={table_name}, tree_path={tree_path} msg=Job execution started"
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_dict = {
        "year": dt_datetime.year,
        "month": dt_datetime.month,
        "day": dt_datetime.day,
    }
    query_template_params.update(dt_dict)

    schema_database_name, schema_database_location = DWMetastoreService.get_layer_info(
        env, dw_schema, dw_bucket, "staging"
    )

    query_path = f"{QUERIES_DATALAKE_PATH}{relative_query_path}/dw/{tree_path}/{table_name}.sql".replace(
        "//", "/"
    )

    query = FileService.get_query_from_file_name(query_path)

    table_loader_pipeline = IncrementalTableLoaderPipeline(
        database_name=schema_database_name,
        table_name=table_name,
        database_location=schema_database_location,
        layer=LayerEnum.DW_STAGING.value,
        query=query,
        cluster_config_params=cluster_config_params,
        partitions=partitions,
        query_template_params=query_template_params,
    )
    table_loader_pipeline.run()
