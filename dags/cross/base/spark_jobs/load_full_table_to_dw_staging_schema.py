import json
from argparse import ArgumentParser


from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DWMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.pipeline import FullTableLoaderPipeline

JOB_NAME = "load_full_table_to_dw_staging_schema"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("dw_bucket")
    parser.add_argument("dw_schema")
    parser.add_argument("relative_query_path")
    parser.add_argument("table_name")
    parser.add_argument("cluster_config_params")
    parser.add_argument("tree_path")

    args = parser.parse_args()

    env = args.env
    dw_bucket = args.dw_bucket
    dw_schema = args.dw_schema
    relative_query_path = args.relative_query_path
    table_name = args.table_name
    cluster_config_params = json.loads(args.cluster_config_params)
    tree_path = args.tree_path

    logger.info(
        f"m={JOB_NAME}, env={env}, dw_bucket={dw_bucket},  dw_schema={dw_schema}, "
        f"relative_query_path={relative_query_path}, table_name={table_name}, "
        f"tree_path={tree_path} msg=Job execution started"
    )

    dw_staging_db_name, dw_staging_db_location = DWMetastoreService.get_layer_info(
        env=env, schema=dw_schema, bucket=dw_bucket, layer=LayerEnum.DW_STAGING.value
    )

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=relative_query_path,
        layer=LayerEnum.DW.value,
        intermediate_path=tree_path,
        table_name=table_name,
    )

    table_loader_pipeline = FullTableLoaderPipeline(
        database_name=dw_staging_db_name,
        table_name=table_name,
        database_location=dw_staging_db_location,
        layer=LayerEnum.DW_STAGING.value,
        query=query,
        cluster_config_params=cluster_config_params,
    )
    table_loader_pipeline.run()
