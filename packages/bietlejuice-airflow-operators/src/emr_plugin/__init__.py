from airflow.plugins_manager import AirflowPlugin

from emr_plugin.links import QuintoAndarEmrClusterLogsLink, QuintoAndarEmrStepLogsLink
from emr_plugin.operators.create_cluster import QuintoAndarEmrCreateClusterOperator
from emr_plugin.operators.submit_steps import QuintoAndarEmrSubmitStepsOperator
from emr_plugin.operators.terminate_cluster import (
    QuintoAndarEmrTerminateClusterOperator,
)


class QuintoAndarEmrPlugin(AirflowPlugin):
    name = "emr_plugin"
    operators = [
        QuintoAndarEmrCreateClusterOperator,
        QuintoAndarEmrSubmitStepsOperator,
        QuintoAndarEmrTerminateClusterOperator,
    ]
    operator_extra_links = [
        QuintoAndarEmrClusterLogsLink(),
        QuintoAndarEmrStepLogsLink(),
    ]
