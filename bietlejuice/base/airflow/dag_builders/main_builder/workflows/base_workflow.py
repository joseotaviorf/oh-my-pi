from datetime import datetime

from airflow import DAG
from pendulum import timezone

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.builder_interface import (
    BuilderInterface,
)
from bietlejuice.services.configuration_service import ConfigurationService


class BaseWorkflow(BuilderInterface):
    def __init__(self, dag_args, workflow_args, cluster_args) -> None:
        """
        This class must be a component that all workflows must inherit to have the dag instance.
        :param dag_args: A dictionary containing the definition of the dag with parameters received from each dag yaml file.
        :param workflow_args: A dictionary containing arguments that will be used to decide which tasks to define in the dag.
        :param cluster_args: A dictionary containing arguments that will be used for the cluster definition that the dag processes will make.
        """
        super().__init__()
        self.dag_args = dag_args
        self.workflow_args = workflow_args
        self.cluster_args = cluster_args

        self.dag_name = self.dag_args["name"]
        self.dag_id = f"bietlejuice.{self.dag_name}"
        self.config_service = ConfigurationService(self.dag_name)

        self.local_tz = timezone("America/Sao_Paulo")

    def dag_instance(self):
        schedule_start_date = self._get_start_date()
        doc_md = self._get_dag_documentation()

        dag = DAG(
            dag_id=self.dag_id,
            catchup=self.dag_args.get("catchup", False),
            default_args={
                "owner": self.dag_args["owner"],
                "wait_for_downstream": False,
                "depends_on_past": False,
            },
            start_date=schedule_start_date,
            schedule_interval=self.dag_args.get("schedule_interval", None),
            doc_md=doc_md,
        )

        return dag

    def _get_start_date(self):
        start_date_from_yml = self.dag_args.get("schedule_start_date", "2023,1,1")
        start_date_from_yml = start_date_from_yml.split(",")
        schedule_start_date = datetime(
            year=int(start_date_from_yml[0]),
            month=int(start_date_from_yml[1]),
            day=int(start_date_from_yml[2]),
        )

        return schedule_start_date

    def _get_dag_documentation(self):

        dag_documentation = self.dag_args.get("documentation")
        doc_md_chart_url = self.config_service.get_config("doc_md_chart_url")

        if dag_documentation:
            doc_md = BaseDAG.generate_doc_md_str(
                dag_name=self.dag_name,
                doc_md_chart_url=doc_md_chart_url,
                dag_documentation=dag_documentation,
                dag_owner=self.dag_args["owner"],
            )
        else:
            doc_md = BaseDAG.get_dag_doc(self.dag_name).format(
                chart_url=doc_md_chart_url, dag_id=self.dag_id
            )

        return doc_md
