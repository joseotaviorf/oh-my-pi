# Hey, airflow! Take a look at this DAG!

import glob
from bietlejuice.airflow.dag_builders.metric_factory import MetricsDagFactory
from dags import DAG_PACKAGES_ROOT

METRICS_FOLDER_PATTERN = "/*/metric_*/queries/metric"

for dag_path in glob.iglob(DAG_PACKAGES_ROOT + METRICS_FOLDER_PATTERN):
    dag_name = dag_path.split("/")[-3]
    metrics_factory = MetricsDagFactory(dag_name=dag_name)
    dag_id = metrics_factory.dag_id
    dag = metrics_factory.build_dag()
    globals()[dag_id] = dag
