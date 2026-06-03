from __future__ import annotations

import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.query_view_sync import normalize_query_view_sync_config
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.pipeline.query_view_creator_pipeline import QueryViewCreatorPipeline

JOB_NAME = "create_query_view"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _parse_sync_arg(sync_arg: str | None) -> list[str] | None:
    if sync_arg is None:
        return None

    try:
        parsed_sync = json.loads(sync_arg)
    except json.JSONDecodeError:
        parsed_sync = [target.strip() for target in sync_arg.split(",")]

    if isinstance(parsed_sync, str):
        return [parsed_sync]
    return parsed_sync


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "layer", type=str, help="layer where the view will be created (dw/enrich)"
    )
    parser.add_argument("schema", type=str, help="schema name for the view")
    parser.add_argument(
        "relative_query_path",
        type=str,
        help="relative query path for sql file to create view (DAG name)",
    )
    parser.add_argument("table_name", type=str, help="view name that will be created")
    parser.add_argument("execution_date", help="execution date")
    parser.add_argument(
        "spark_session_configs",
        type=str,
        help="custom config parameters to be set in spark session",
    )
    parser.add_argument(
        "extra_query_template_params", type=str, help="extra query template parameters"
    )
    parser.add_argument("execution_date_2", help="second execution date parameter")
    parser.add_argument(
        "--table-privileges",
        type=str,
        help="json string mapping each principal to a list of permissions for the view",
        required=False,
        dest="table_privileges",
    )
    parser.add_argument(
        "--sync",
        type=str,
        default=None,
        help="json list or comma-separated list of sync targets",
        required=False,
        dest="sync",
    )
    parser.add_argument(
        "--sql-dialect",
        type=str,
        default=None,
        help="source SQL dialect for the view query",
        required=False,
        dest="sql_dialect",
    )

    args = parser.parse_args()

    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    sync_config = normalize_query_view_sync_config(
        {
            "sync": _parse_sync_arg(args.sync),
            "sql_dialect": args.sql_dialect,
        }
    )

    env = args.env
    datalake_bucket = args.datalake_bucket
    layer = args.layer
    schema = args.schema
    table_name = args.table_name
    relative_query_path = args.relative_query_path
    execution_date = args.execution_date
    query_template_params = json.loads(
        args.extra_query_template_params.replace("'", '"')
    )
    spark_session_configs = json.loads(args.spark_session_configs)

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer}, "
        + f"schema={schema}, table_name={table_name}, "
        + f"relative_query_path={relative_query_path}, "
        + f"execution_date={execution_date}, "
        + f"sync={list(sync_config.sync)}, "
        + f"sql_dialect={sync_config.sql_dialect}, "
        + "msg=Job execution started"
    )

    metastore_mapping = MetastoreMappingFactory.get_mapper_by_layer(
        LayerEnum(layer), schema, datalake_bucket
    )
    database_name = metastore_mapping.get_full_database_name(LayerEnum(layer))

    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, f"{database_name}.{table_name}"
        )
    else:
        table_privileges = TablePrivileges.from_environment_default_for_view(
            f"{database_name}.{table_name}"
        )

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=relative_query_path,
        layer=layer,
        intermediate_path=None,  # For views, we don't need intermediate paths
        table_name=table_name,
    )

    query_view_creator_pipeline = QueryViewCreatorPipeline(
        database_name=database_name,
        view_name=table_name,
        layer=layer,
        query=query,
        query_template_params=query_template_params,
        spark_session_configs=spark_session_configs,
        env=env,
        spark=None,  # spark parameter is not used in the pipeline
        table_privileges=table_privileges,
        sync=list(sync_config.sync),
        sql_dialect=sync_config.sql_dialect,
    )

    query_view_creator_pipeline.run()
