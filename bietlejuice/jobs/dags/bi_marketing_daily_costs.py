import json
import os
from datetime import datetime

from airflow.models import DAG
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.base.base_test import BaseTest
from qa_python_utils.aws.athena import AthenaClient
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from bietlejuice.jobs.wrappers.GoogleDrive import GoogleSheets

# Credentials setup
S3_BUCKET = env.get_airflow_env_var('bi-datalake-s3-bucket')
env.set_airflow_var_to_local_env('BI_DW', 'DATA_ACC_AWS_ACCESS_KEY_ID',
                                 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
GOOGLE_S_A_CREDENTIALS = json.loads(
    env.get_airflow_env_var('GOOGLE_SERVICE_ACCOUNT_CREDENTIALS'))
GOOGLE_API_SCOPE = env.get_airflow_env_var('GOOGLE_API_SCOPE')

# Files setup
COST_SHARE_FILES = json.loads(
    env.get_airflow_env_var('MARKETING_COST_SHARE_GSHEETS_FILES'))
AUX_COST_SHARE_FILES = json.loads(
    env.get_airflow_env_var('MARKETING_AUX_COST_SHARE_GSHEETS_FILES'))
YAML_PATH = env.get_airflow_env_var("MARKETING_COSTS_SHARING_RULES_PATH")
SHARING_RULES_TABLE = "sharing_rules_marketing_daily_costs"

# DAG setup
MAIN_DAG_NAME = 'bi-marketing-daily-costs'
MAIN_START_DATE = datetime(2019, 1, 1)
MAIN_SCHEDULE_INTERVAL = env.convert_to_utc_schedule("0 6,11 * * *")

logger = QuintoAndarLogger(MAIN_DAG_NAME)


@logger
def load_marketing_daily_costs_rules(yaml_path, schema, dw_queries_path,
                                     sharing_rules_table):
    """
    This method loads marketing costs rules on specified DW schema
    :param yaml_path: path to yaml file with rules
    :param schema: the DW schema, e.g: public, staging.
    :param dw_queries_path: path to DW queries dir
    :param sharing_rules_table: sharing rules table name
    """
    logger.info(
        """m=load_marketing_daily_costs_rules, file_path={}, msg=Reading YAML rules file""".format(
            yaml_path
        )
    )
    sharing_rules = BaseETL.get_dict_from_yaml_file(yaml_path)
    merge_rules = ["select * from head where rule_id <> 'HEAD'"]
    ctes = [
        """with head as (
                select
                    'HEAD'::VARCHAR as rule_id,
                    0::INTEGER as sk_date,
                    ''::VARCHAR as city_group,
                    ''::VARCHAR as funnel_side,
                    0::FLOAT as share)"""
    ]

    try:
        for rule_id, config in sharing_rules.items():
            logger.info(
                "m=load_marketing_daily_costs_rules, msg=Getting {} config".format(
                    rule_id))
            if validate_config(config,
                               required_fields=["query", "funnel_side"]):
                merge_rules.append("union all select * from {}".format(rule_id))
                rule_query = BaseETL.get_query_from_file_name(
                    file_name="{}/{}".format(dw_queries_path,
                                             config.get("query"))
                )
                rule_cte = """{rule} as (
                                    with {rule}_raw as ({rule_query})
                                        select
                                            '{rule}' as rule_id,
                                            sk_date,
                                            city_group,
                                            '{funnel_side}' as funnel_side,
                                            share
                                        from {rule}_raw )
                           """.format(
                    rule=rule_id,
                    rule_query=rule_query,
                    funnel_side=config.get("funnel_side"),
                )
                ctes.append(rule_cte)
            rules_query = "{ctes} {merge_rules}".format(
                ctes=",".join(ctes), merge_rules=" ".join(merge_rules)
            )
            logger.info(
                "m=load_marketing_daily_costs_rules, msg=Parsing CTE rules query done")

            rules_table = BaseETL.from_db_query(db_enum=EnumDB.BI_DW,
                                                query=rules_query)
            if len(rules_table) == 0:
                raise RuntimeError("""m=load_marketing_daily_costs_rules,
                    query={}, msg=Rules table is empty, please verify the query """).format(rules_query)

            BaseETL.bulk_insert(
                table=rules_table,
                table_name="{}.{}".format(schema, sharing_rules_table),
                db_enum=EnumDB.BI_DW,
                encoding="UTF-8",
                append=False,
            )
    except Exception as error:
        raise RuntimeError("""m=load_marketing_daily_costs_rules, msg=Error while loading YAML rules into DW,
            exception_name={},exception_message={}""".format(
            type(error).__name__, error))


def validate_config(config, required_fields):
    return all(
        [BaseTest.validate_dict_keys(config, required_fields=required_fields),
         BaseTest.validate_dict_values(config, fields=required_fields)]
    )


def move_file_query_data_to_dw(schema, file_name):
    query = BaseETL.get_query_from_file_name(
        file_name="{}/{}/{}.sql".format(DW_QUERIES_DIR, schema, file_name)
    )

    table = BaseETL.from_db_query(db_enum=EnumDB.BI_DW, query=query)

    BaseETL.bulk_insert(
        table=table,
        table_name="{}.{}".format(schema, file_name),
        db_enum=EnumDB.BI_DW,
        encoding="UTF-8",
        append=False,
    )


def load_google_sheet_files_to_datalake(files, create_athena_table=None):
    """
    Loads all shared cost files into the data lake. If create_athena_table is
    True, then also creates its tables on Athena

    :param files: the files list to be loaded in the data lake
    :param create_athena_table: toggle to create table on Athena automatically
    """
    athena_client = None
    if create_athena_table:
        aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
        aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
        athena_client = AthenaClient(S3_BUCKET, aws_access_key_id,
                                     aws_secret_access_key)

    gs = GoogleSheets(
        s3_bucket=S3_BUCKET,
        google_s_a_credentials=GOOGLE_S_A_CREDENTIALS,
        google_api_scope=GOOGLE_API_SCOPE,
    )
    for file in files:
        gs.move_sheets_data_to_destination(
            google_sheets_file=file,
            enumdb_destination=EnumDB.QuintoAndar_datalake,
            athena_client=athena_client,
        )


# DAG definition
main_dag = DAG(
    dag_id=MAIN_DAG_NAME,
    description="ETL Pipeline for unifying marketing costs from various sources",
    default_args={
        "owner": BaseDAG.DEFAULT_OWNER,
        "wait_for_downstream": False,
        "depends_on_past": False,
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False,
)

load_cost_share_rules_into_dw_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="load_cost_share_rules_into_dw",
    python_callable=load_marketing_daily_costs_rules,
    op_kwargs={
        "yaml_path": YAML_PATH,
        "sharing_rules_table": SHARING_RULES_TABLE,
        "dw_queries_path": DW_QUERIES_DIR,
        "schema": "staging"
    },
)

load_shared_manual_costs_to_datalake_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="load_shared_manual_costs_to_datalake",
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={"files": COST_SHARE_FILES["files"]},
)

load_aux_cost_share_files_into_datalake_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_aux_cost_share_files_into_datalake',
    python_callable=load_google_sheet_files_to_datalake,
    op_kwargs={"files": AUX_COST_SHARE_FILES["aux_files"],
               "create_athena_table": True}

)

load_fact_marketing_daily_costs_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="load_fact_marketing_daily_costs",
    python_callable=move_file_query_data_to_dw,
    op_kwargs={"schema": "marketing",
               "file_name": "fact_marketing_daily_costs"},
)

load_temp_fact_marketing_daily_costs_task = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id="load_temp_fact_marketing_daily_costs",
    python_callable=move_file_query_data_to_dw,
    op_kwargs={"schema": "marketing",
               "file_name": "temp_fact_marketing_daily_costs"},
)

# trigger bi-marketing-funnels-conversions after all tasks have been successfully completed
trigger_bi_marketing_funnels_conversions_task = TriggerDagRunOperator(
    dag=main_dag,
    task_id="trigger_bi_marketing_funnels_conversions",
    trigger_dag_id="bi-marketing-funnels-conversions",
    execution_date="{{ execution_date }}",
)

load_aux_cost_share_files_into_datalake_task >> load_cost_share_rules_into_dw_task

load_fact_marketing_daily_costs_task.set_upstream([
    load_cost_share_rules_into_dw_task,
    load_shared_manual_costs_to_datalake_task
])

load_temp_fact_marketing_daily_costs_task.set_upstream([
    load_cost_share_rules_into_dw_task,
    load_shared_manual_costs_to_datalake_task
])

load_fact_marketing_daily_costs_task >> trigger_bi_marketing_funnels_conversions_task
