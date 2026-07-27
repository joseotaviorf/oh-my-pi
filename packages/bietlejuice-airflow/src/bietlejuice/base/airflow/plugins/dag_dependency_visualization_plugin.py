from airflow.plugins_manager import AirflowPlugin
from flask_admin.menu import MenuLink

ml = MenuLink(
    category="QuintoAndar",
    name="DAG Dependencies",
    url="/admin/airflow/graph?dag_id=airflow.dag_dependency_visualization",
)


class QuintoAndarDagDependencyVisualizationPlugin(AirflowPlugin):
    name = "quintoandar_dag_dependency_visualization"
    menu_links = [ml]
