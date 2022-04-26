"""
This script creates dinamically in airflow each datamart DAG configured in the file
dw_datamarts_spark_[env]_conf.yml, using a DAG factory.
"""
import os
from bietlejuice.jobs.composer.services import ConfigurationService, FileService
from bietlejuice.jobs.composer.dags.dw_datamarts_spark.datamarts_factory import (
    DatamartsDAGFactory,
)

SOURCE = "dw_datamarts_spark"

dag_factory = DatamartsDAGFactory(source=SOURCE)
dag_configs = ConfigurationService(dag_name=SOURCE).get_config("dags")

for dag_context, dag_details in dag_configs.items():
    dag_id = f"bietlejuice.{SOURCE}.{dag_context}"
    datamart_config_path = os.path.join(
        os.path.dirname(os.path.realpath(__file__)), dag_context, f"{dag_context}.yml"
    )
    datamart_configs = FileService.get_dict_from_yaml_file(datamart_config_path)

    globals()[dag_id] = dag_factory.build_dag(
        dag_context, dag_details, datamart_configs
    )
