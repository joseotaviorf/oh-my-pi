from airflow.plugins_manager import AirflowPlugin

from databricks_plugin.hooks.databricks_hook import QuintoAndarDatabricksHook
from databricks_plugin.operators.check_job_task import (
    QuintoAndarDatabricksCheckJobTaskOperator,
)
from databricks_plugin.operators.create_cluster import (
    QuintoAndarDatabricksCreateClusterOperator,
)
from databricks_plugin.operators.execute_job_cluster import (
    QuintoAndarDatabricksExecuteJobClusterOperator,
)
from databricks_plugin.operators.submit_run import (
    QuintoAndarDatabricksSubmitRunOperator,
)
from databricks_plugin.operators.terminate_cluster import (
    QuintoAndarDatabricksTerminateClusterOperator,
)


class QuintoAndarDatabricksPlugin(AirflowPlugin):
    name = "databricks_plugin"
    operators = [
        QuintoAndarDatabricksCheckJobTaskOperator,
        QuintoAndarDatabricksCreateClusterOperator,
        QuintoAndarDatabricksExecuteJobClusterOperator,
        QuintoAndarDatabricksTerminateClusterOperator,
        QuintoAndarDatabricksSubmitRunOperator,
    ]
    hooks = [QuintoAndarDatabricksHook]
