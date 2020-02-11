from datetime import datetime

import pendulum
from airflow.models import DAG, Variable
from airflow.operators.quintoandar_databricks import (
    QuintoAndarDatabricksCreateClusterOperator,
    QuintoAndarDatabricksSubmitRunOperator,
    QuintoAndarDatabricksTerminateClusterOperator,
)

from bietlejuice.jobs.composer.base.airflow import BaseDAG, BaseSubDAG

# DAG params
DAG_ID = "ebdb"
FULL_DAG_ID = "bietlejuice.{}".format(DAG_ID)
ENV = Variable.get("environment")
local_tz = pendulum.timezone("America/Sao_Paulo")  # use cron expressions in local time
MAIN_START_DATE = datetime(2019, 5, 31, 0, 0, 0, tzinfo=local_tz)
MAIN_SCHEDULE_INTERVAL = "0 22 * * *"

# Job params
SOURCE = "ebdb"
DW_SCHEMA = "public_spark"

# s3 path setup
S3_PREFIX = Variable.get("databricks_bietlejuice_s3_prefix")
SPARK_JOBS_PATH = S3_PREFIX + "/spark_jobs/{}/".format(DAG_ID)
LOGS_OUTPUT_PATH = "s3://{}/logs/jobs/{}".format(
    Variable.get("databricks_s3_bucket"), DAG_ID
)
ARTIFACTS_S3_BUCKET = Variable.get("artifacts_s3_bucket")

# cluster params
CLUSTER_DESCRIPTION = Variable.get("databricks_default_cluster", deserialize_json=True)
CLUSTER_DESCRIPTION["cluster_log_conf"]["s3"]["destination"] = LOGS_OUTPUT_PATH
CLUSTER_DESCRIPTION["num_workers"] = 6

# cluster libraries
DEFAULT_LIBRARIES = Variable.get("bietlejuice_default_libraries", deserialize_json=True)
CUSTOM_LIBRARIES = [
    {
        "jar": f"{ARTIFACTS_S3_BUCKET}/mysql-connector-java/mysql-connector-java-5.1"
        f".47.jar"
    }
]
LIBRARIES_DESCRIPTION = DEFAULT_LIBRARIES + CUSTOM_LIBRARIES


# methods to create tasks and subdags
def create_clean_table_in_datalake_task(local_dag, table_name, source, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-clean-{}-in-datalake".format(table_name.replace("_", "-")),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_clean_table_in_datalake.py",
                "parameters": [table_name, source, env, dag_name],
            }
        },
    )


def create_dw_table_in_datalake_task(local_dag, table_name, schema, env, dag_name):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_dw_table_in_datalake.py",
                "parameters": [table_name, schema, env, dag_name],
            }
        },
    )


def load_dw_table_into_redshift_task(local_dag, table_name, schema, env):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="load-dw-{}-{}-in-datalake".format(
            schema, table_name.replace("_", "-")
        ),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "load_dw_table_into_redshift.py",
                "parameters": [table_name, schema, env],
            }
        },
    )


def create_all_external_tables_task(local_dag, env, datalake_layer, source):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-all-{}-{}-external-tables".format(source, datalake_layer),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [env, datalake_layer, source, "--all"],
            }
        },
    )


def create_external_tables_task(local_dag, env, datalake_layer, source, tables):
    return QuintoAndarDatabricksSubmitRunOperator(
        task_id="create-{}-external-tables".format(datalake_layer),
        dag=local_dag,
        json={
            "spark_python_task": {
                "python_file": SPARK_JOBS_PATH + "create_external_tables.py",
                "parameters": [env, datalake_layer, source, "--tables"] + tables,
            }
        },
    )


def create_clean_tables_sub_dag(sub_dag_name, source, clean_table):
    local_sub_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=FULL_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()
    clean_table_task = create_clean_table_in_datalake_task(
        local_sub_dag, clean_table, source, ENV, DAG_ID
    )
    create_clean_external_tables_task = create_external_tables_task(
        local_sub_dag, ENV, "clean", source, [clean_table]
    )
    clean_table_task >> create_clean_external_tables_task

    return local_sub_dag


def create_clean_and_dim_tables_sub_dag(
    sub_dag_name, source, clean_table, dw_schema, dim_table
):
    local_dag = BaseSubDAG(
        sub_dag_name=sub_dag_name,
        dag_name=FULL_DAG_ID,
        schedule_interval=MAIN_SCHEDULE_INTERVAL,
        start_date=MAIN_START_DATE,
    )._build_local_dag()
    clean_table_task = create_clean_table_in_datalake_task(
        local_dag, clean_table, source, ENV, DAG_ID
    )
    create_clean_external_tables_task = create_external_tables_task(
        local_dag, ENV, "clean", source, [clean_table]
    )
    dim_table_task = create_dw_table_in_datalake_task(
        local_dag, dim_table, dw_schema, ENV, DAG_ID
    )
    load_dim_table_task = load_dw_table_into_redshift_task(
        local_dag, dim_table, dw_schema, ENV
    )
    clean_table_task >> create_clean_external_tables_task
    clean_table_task >> dim_table_task >> load_dim_table_task

    return local_dag


# dag definition
dag = DAG(
    dag_id=FULL_DAG_ID,
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

# tasks and subdags definitions
create_cluster_task = QuintoAndarDatabricksCreateClusterOperator(
    dag=dag,
    task_id="create-cluster",
    cluster_configuration=CLUSTER_DESCRIPTION,
    libraries=LIBRARIES_DESCRIPTION,
)

ebdb_to_datalake_raw_task = QuintoAndarDatabricksSubmitRunOperator(
    task_id="ebdb-to-datalake-raw",
    dag=dag,
    json={
        "spark_python_task": {
            "python_file": SPARK_JOBS_PATH + "load_ebdb_into_datalake.py",
            "parameters": [ENV],
        }
    },
)

create_raw_external_tables_task = create_all_external_tables_task(
    dag, ENV, "raw", "ebdb"
)

condo_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="condo",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="condo",
    dw_schema=DW_SCHEMA,
    dim_table="dim_condo",
)

region_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="region",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="region",
    dw_schema=DW_SCHEMA,
    dim_table="dim_region",
)

visit_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="visit",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="visit",
    dw_schema=DW_SCHEMA,
    dim_table="dim_visit",
)

# TO DO: dim_contract
# contract_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
#     dag=dag,
#     sub_dag_name="contract",
#     sub_dag_func=create_clean_and_dim_tables_sub_dag,
#     source=SOURCE,
#     clean_table="contract",
#     dw_schema=DW_SCHEMA,
#     dim_table="dim_contract",
# )

visit_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="visit_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="visit_aud",
)

inspection_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="inspection",
    sub_dag_func=create_clean_and_dim_tables_sub_dag,
    source=SOURCE,
    clean_table="inspection",
    dw_schema=DW_SCHEMA,
    dim_table="dim_inspection",
)

access_type_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="access_type",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="access_type",
)

access_authorization_type_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="access_authorization_type",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="access_authorization_type",
)

ownerlead_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="ownerlead",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="ownerlead",
)

agent_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="agent",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="agent",
)

conversion_lead_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="conversion_lead",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="conversion_lead",
)

visitor_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="visitor",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="visitor",
)

user_revision_entity_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="user_revision_entity",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="user_revision_entity",
)

keytype_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="keytype",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="keytype",
)

contract_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="contract",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="contract",
)

contract_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="contract_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="contract_aud",
)

full_contract_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="full_contract",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="full_contract",
)

lead_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="lead",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="lead",
)

lead_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="lead_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="lead_aud",
)

real_estate_agency_lead_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="real_estate_agency_lead",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="real_estate_agency_lead",
)

account_transaction_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="account_transaction",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="account_transaction",
)

polygon_region_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="polygon_region",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="polygon_region",
)

bank_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="bank",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="bank",
)

house_guarantees_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_guarantees_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_guarantees_aud",
)

affiliate_data_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="affiliate_data",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="affiliate_data",
)

affiliate_data_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="affiliate_data_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="affiliate_data_aud",
)

leads_grouped_by_phone_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="leads_grouped_by_phone",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="leads_grouped_by_phone",
)

house_registration_status_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_registration_status",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_registration_status",
)

house_registration_status_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_registration_status_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_registration_status_aud",
)

portability_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="portability",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="portability",
)

portability_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="portability_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="portability_aud",
)

visit_origin_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="visit_origin",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="visit_origin",
)

house_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house",
)

house_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_aud",
)

appointment_change_reason_category_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="appointment_change_reason_category",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="appointment_change_reason_category",
)

follow_up_details_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="follow_up_details",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="follow_up_details",
)

house_visit_information_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_visit_information",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_visit_information",
)

offer_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="offer",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="offer",
)

offer_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="offer_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="offer_aud",
)

rent_flow_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="rent_flow",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="rent_flow",
)

house_special_condition_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_special_condition",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_special_condition",
)

local_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="local",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="local",
)

occupant_type_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="occupant_type",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="occupant_type",
)

device_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="device",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="device",
)

sales_rep_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="sales_rep",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="sales_rep",
)

pre_proposal_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="pre_proposal",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="pre_proposal",
)

pre_proposal_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="pre_proposal_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="pre_proposal_aud",
)

pre_proposal_condition_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="pre_proposal_condition",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="pre_proposal_condition",
)

proposal_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="proposal",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="proposal",
)

proposal_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="proposal_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="proposal_aud",
)

account_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="account",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="account",
)

proposal_condition_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="proposal_condition",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="proposal_condition",
)

proposal_condition_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="proposal_condition_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="proposal_condition_aud",
)

state_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="state",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="state",
)

state_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="state_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="state_aud",
)

special_condition_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="special_condition",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="special_condition",
)

special_condition_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="special_condition_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="special_condition_aud",
)

restriction_type_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="restriction_type",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="restriction_type",
)

restriction_type_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="restriction_type_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="restriction_type_aud",
)

booking_status_change_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="booking_status_change",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="booking_status_change",
)

photographer_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="photographer",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="photographer",
)

city_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="city",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="city",
)

partner_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="partner",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="partner",
)

partner_agent_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="partner_agent",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="partner_agent",
)

user_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="user",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="user",
)

entrance_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="entrance",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="entrance",
)

doorman_affiliate_data_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="doorman_affiliate_data",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="doorman_affiliate_data",
)

doorman_affiliate_occupation_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="doorman_affiliate_occupation",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="doorman_affiliate_occupation",
)

photographer_job_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="photographer_job",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="photographer_job",
)

photographer_job_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="photographer_job_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="photographer_job_aud",
)

booking_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="booking",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="booking",
)

booking_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="booking_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="booking_aud",
)

map_region_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="map_region",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="map_region",
)

house_maintenance_condition_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="house_maintenance_condition_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="house_maintenance_condition_aud",
)

info_amenities_aud_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="info_amenities_aud",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="info_amenities_aud",
)

amenities_sub_dag_task = BaseSubDAG.get_sub_dag_operator(
    dag=dag,
    sub_dag_name="amenities",
    sub_dag_func=create_clean_tables_sub_dag,
    source=SOURCE,
    clean_table="amenities",
)

terminate_cluster_task = QuintoAndarDatabricksTerminateClusterOperator(
    dag=dag, task_id="terminate-cluster"
)
# tasks dependencies
create_cluster_task >> ebdb_to_datalake_raw_task
ebdb_to_datalake_raw_task >> [
    create_raw_external_tables_task,
    condo_sub_dag_task,
    region_sub_dag_task,
    visit_sub_dag_task,
    visit_aud_sub_dag_task,
    contract_sub_dag_task,
    contract_aud_sub_dag_task,
    full_contract_sub_dag_task,
    inspection_sub_dag_task,
    access_type_sub_dag_task,
    access_authorization_type_sub_dag_task,
    ownerlead_sub_dag_task,
    agent_sub_dag_task,
    conversion_lead_sub_dag_task,
    visitor_sub_dag_task,
    user_revision_entity_sub_dag_task,
    keytype_sub_dag_task,
    lead_sub_dag_task,
    lead_aud_sub_dag_task,
    real_estate_agency_lead_sub_dag_task,
    bank_sub_dag_task,
    house_guarantees_aud_sub_dag_task,
    affiliate_data_sub_dag_task,
    affiliate_data_aud_sub_dag_task,
    leads_grouped_by_phone_sub_dag_task,
    house_registration_status_sub_dag_task,
    house_registration_status_aud_sub_dag_task,
    portability_sub_dag_task,
    portability_aud_sub_dag_task,
    visit_origin_sub_dag_task,
    house_sub_dag_task,
    house_aud_sub_dag_task,
    appointment_change_reason_category_sub_dag_task,
    follow_up_details_sub_dag_task,
    house_visit_information_sub_dag_task,
    offer_sub_dag_task,
    offer_aud_sub_dag_task,
    rent_flow_sub_dag_task,
    house_special_condition_sub_dag_task,
    local_sub_dag_task,
    occupant_type_sub_dag_task,
    device_sub_dag_task,
    polygon_region_sub_dag_task,
    sales_rep_sub_dag_task,
    pre_proposal_sub_dag_task,
    pre_proposal_aud_sub_dag_task,
    pre_proposal_condition_sub_dag_task,
    proposal_sub_dag_task,
    proposal_aud_sub_dag_task,
    account_sub_dag_task,
    proposal_condition_sub_dag_task,
    proposal_condition_aud_sub_dag_task,
    state_sub_dag_task,
    state_aud_sub_dag_task,
    special_condition_sub_dag_task,
    special_condition_aud_sub_dag_task,
    restriction_type_sub_dag_task,
    restriction_type_aud_sub_dag_task,
    booking_status_change_sub_dag_task,
    photographer_sub_dag_task,
    account_transaction_sub_dag_task,
    city_sub_dag_task,
    partner_sub_dag_task,
    partner_agent_sub_dag_task,
    user_sub_dag_task,
    entrance_sub_dag_task,
    doorman_affiliate_data_sub_dag_task,
    doorman_affiliate_occupation_sub_dag_task,
    photographer_job_sub_dag_task,
    photographer_job_aud_sub_dag_task,
    booking_sub_dag_task,
    booking_aud_sub_dag_task,
    map_region_sub_dag_task,
    house_maintenance_condition_aud_sub_dag_task,
    info_amenities_aud_sub_dag_task,
    amenities_sub_dag_task,
] >> terminate_cluster_task
