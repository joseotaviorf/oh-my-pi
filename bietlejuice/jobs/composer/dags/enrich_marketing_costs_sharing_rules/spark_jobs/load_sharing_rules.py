import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import (
    DatalakeMetastoreService,
    QUERIES_DATALAKE_PATH,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.pipeline.full_table_loader_pipeline import (
    FullTableLoaderPipeline,
)

JOB_NAME = "load_sharing_rules_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


cte_template = """
{rule} as (
    with {rule}_raw as ({rule_query})
    select
        '{rule}' as id_rule,
        id_date,
        city_group,
        {third_column},
        share
    from {rule}_raw )
"""


def build_query(sql_file_list, rule_type):

    third_column = "funnel_side" if rule_type == "online" else "center_cost"
    ctes = []
    union = []
    for query_path in sql_file_list:

        rule_name_raw = query_path.split("/")[-1]
        rule_name = FileService.remove_file_extension(rule_name_raw)

        rule_query = FileService.get_query_from_file_name(query_path)

        rule_cte = cte_template.format(
            rule=rule_name, rule_query=rule_query, third_column=third_column
        )
        ctes.append(rule_cte)
        union.append(f"select * from {rule_name}")

    query = "WITH " + ",\n".join(ctes) + "\nUNION ALL".join(union)

    return query


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("rule_type", type=str, help="table name that will be created")

    layer = LayerEnum.ENRICH
    partitions = []

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    database_base_name = args.database_base_name
    rule_type = args.rule_type

    logger.info(
        f"""
            m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer},
            database_base_name={database_base_name}, table_name={rule_type},  msg=Job execution started
        """
    )

    (
        database_clean_name,
        database_location,
        database_name,
    ) = DatalakeMetastoreService.get_layer_info(
        env, database_base_name, datalake_bucket, layer.value
    )

    rule_path = (
        f"{QUERIES_DATALAKE_PATH}enrich_{database_base_name}/{rule_type}/{layer.value}"
    )

    try:
        sql_file_list_raw = FileService.list_files(rule_path)
        nbr_files = len(sql_file_list_raw)
    except (RuntimeError):
        nbr_files = 0
        logger.info("no rules in {rule_type} rule types, skipping session")

    if nbr_files > 0:
        sql_file_list_paths = [
            f"{rule_path}/{file_name}" for file_name in sql_file_list_raw
        ]

        query = build_query(sql_file_list_paths, rule_type)

        table_loader_pipeline = FullTableLoaderPipeline(
            database_name=database_name,
            table_name=rule_type,
            database_location=database_location,
            layer=layer.value,
            query=query,
            partitions=partitions,
        )
        table_loader_pipeline.run()
