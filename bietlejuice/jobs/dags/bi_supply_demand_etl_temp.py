import os
from datetime import datetime, timedelta

import bietlejuice.jobs.base.new_base_etl as utils
from airflow.operators.dagrun_operator import TriggerDagRunOperator
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags import (
    SOURCE_QUERIES_DIR,
    DW_QUERIES_DIR,
    DATALAKE_QUERIES_DIR,
)
from bietlejuice.jobs.dags.supply_demand_funnel import (
    ListingFlowsTempSubDag
)
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.dags.util import xcom as xcom
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger("bi-supply-demand-temp-etl")

env.set_airflow_var_to_local_env("BI_DW", "BI_ODS", "EBDB", "GODFATHER", "DATA_ACC_AWS_ACCESS_KEY_ID",
                                 "DATA_ACC_AWS_SECRET_ACCESS_KEY")
bucket = env.get_airflow_env_var("bi-datalake-s3-bucket")

MAIN_DAG_NAME = "bi-supply-demand-temp-etl"
MAIN_START_DATE = datetime(2020, 8, 10, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = "0 13 * * *"

# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description="ETL pipeline for the entire BI funnel",
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
)


def extract_query_dim_from_ebdb_to_ods(**kwargs):
    file_path = "{}/ebdb/supply_demand_funnel/{}.sql".format(
        SOURCE_QUERIES_DIR, kwargs["table_name"]
    )
    query = BaseETL.get_query_from_file_name(file_name=file_path)

    if "execution_date" in kwargs:
        query = query.format(str(kwargs["execution_date"]))

    utils.extract_query_dim_from_ebdb_to_ods(
        dim_name=kwargs["table_name"],
        bucket=bucket,
        command=query,
        table_name=None if "table_name" not in kwargs else kwargs["table_name"],
    )


def load_dim_from_ods_to_dw(**kwargs):
    if "post_command_file" in kwargs:
        file_path = "{}/public/post_command_{}.sql".format(
            DW_QUERIES_DIR, kwargs["dim_name"]
        )
        post_command = BaseETL.get_query_from_file_name(file_name=file_path)
    else:
        post_command = None if "post_command" not in kwargs else kwargs["post_command"]

    utils.load_dim_from_ods_to_dw(
        dim_name=kwargs["dim_name"],
        bucket=bucket,
        insert_dummy=True if "insert_dummy" not in kwargs else kwargs["insert_dummy"],
        is_fact=False if "is_fact" not in kwargs else kwargs["is_fact"],
        pre_command=None if "pre_command" not in kwargs else kwargs["pre_command"],
        post_command=post_command,
        schema_dest="public" if "schema_dest" not in kwargs else kwargs["schema_dest"],
        schema_source="public"
        if "schema_source" not in kwargs
        else kwargs["schema_source"],
    )


@logger(exclude="kwargs")
def xcom_dependencies(task_id, dag_id, **kwargs):
    exec_date = str(datetime.date(kwargs["execution_date"]))

    status = xcom.xcom_pull(
        task_instance=kwargs["ti"], key=exec_date, task_id=task_id, dag_id=dag_id
    )
    if not status:
        raise ValueError(
            "m=xcom_dependencies, exec_date={}, dag_id={}, task_id={}, msg=The process have not finished yet".format(
                exec_date, dag_id, task_id
            )
        )

    logger.info(
        "m=xcom_dependencies, exec_date={}, dag_id={}, task_id={}, msg=REQUIREMENT MET".format(
            exec_date, dag_id, task_id
        )
    )


@logger(exclude=["kwargs", "query_params"])
def create_table_in_db_from_datalake(table_name, query_params, **kwargs):
    # setting variables
    file_path = "{}/{}{}.sql".format(
        DATALAKE_QUERIES_DIR, kwargs.get("file_path", ""), table_name
    )
    data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
    data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')
    athena_client = AthenaClient(bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)

    # executing methods
    df = athena_client.execute_file_query_and_return_dataframe(
        filename=file_path, query_params=query_params
    )

    if len(df.index) == 0:
        raise ValueError(
            "m=create_table_in_db_from_datalake, filename={}, msg=Query returned empty df".format(
                file_path
            )
        )

    BaseETL.dataframe_to_db(
        df=df,
        table_name=table_name,
        enum_db=kwargs.get("enum_db", EnumDB.BI_DW),
        encoding="utf-8",
        append=False,
    )

    
def listing_flows_temp_sub_dag(sub_dag_name):
    sub_dag = ListingFlowsTempSubDag(
        bucket=bucket,
        sub_dag_name=sub_dag_name,
        dag_name=MAIN_DAG_NAME,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )
    return sub_dag.build_listing_flows_temp()


# flow
listing_flows_temp_dag = BaseSubDag.get_sub_dag_operator(
    dag=main_dag, sub_dag_func=listing_flows_temp_sub_dag, sub_dag_name="ListingFlowsTemp"
)
