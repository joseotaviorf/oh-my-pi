from functools import lru_cache
from os import listdir
from os.path import join

from airflow.models.param import Param
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.documentation import COMPOSER_DOCUMENTATION_PATH
from bietlejuice.base.airflow.documentation.cron_descriptor import CronDescriptor
from bietlejuice.base.airflow.enums.dag_run_type_enum import DagRunTypeEnum
from bietlejuice.base.caching import PARSE_CACHE_MAXSIZE
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.services.file_service import FileService

logger = QuintoAndarLogger("BaseDAG")


class BaseDAG:
    @staticmethod
    @lru_cache(maxsize=PARSE_CACHE_MAXSIZE)
    def get_dag_doc(dag_name, template_path=None):
        """
        :param dag_name: dag_name or tree_path to your doc.
        :type dag_name: str
        :param template_path: Used to bypass dag package path
            and set a path to a doc template.
        :type template_path: str, optional.
        :rtype: str
        """
        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        doc_md_string = ""
        dag_path = template_path if template_path else dag_path
        doc_file_path = join(dag_path, f"{dag_name}.md")

        try:
            doc_md_string = open(doc_file_path).read()
        except Exception as e:
            logger.info(
                f"m=BaseDAG.get_dag_doc, msg=The DAG doc file could not be opened, "
                f"dag_name={dag_name}, file_path={doc_file_path}"
            )
            raise e
        finally:
            return doc_md_string

    @classmethod
    def generate_doc_md_str(
        self,
        dag_name,
        doc_md_chart_url,
        dag_owner,
        schedule_interval=None,
        dag_documentation=None,
        intermediate_path=None,
    ):
        """
        Format the documentation from a standard base template.
        @param dag_name: str. DAG name.
        @param doc_md_chart_url: str. Link to chart with total count of failed DAG tasks by day.
        @param dag_owner: str. DAG owner.
        @param schedule_interval: str. DAG trigger range in Cron format
        @param dag_documentation: dict with the description of the purpose of the DAG, additional information
            and, if required in an exception, the description of the triggering range of the DAG.
        @return: str.
        """
        dag_id = f"bietlejuice.{dag_name}"

        dag_documentation = dag_documentation or {}
        intermediate_path = intermediate_path or ""

        schedule_interval = schedule_interval or dag_documentation.get(
            "trigger_interval", "daily"
        )

        try:
            schedule_interval = CronDescriptor.get_description(schedule_interval)
        except Exception:
            from dags import (
                DAG_PACKAGES_ROOT,
            )

            dependencies_path = join(DAG_PACKAGES_ROOT, "dependencies.yaml")
            dag_dependencies = FileService.get_dict_from_yaml_file(
                dependencies_path
            ).get(dag_id)

            if dag_dependencies:
                flat_dependencies = BietlejuiceDependencyHelper.find_unique_dependencies_in_dependency_object(
                    dag_dependencies
                )
                dag_dependencies = [
                    f"- `{dependence.split(':')[0]}` \n"
                    for dependence in flat_dependencies
                ]
                schedule_interval = f"This DAG will trigger {schedule_interval} after executing the following dependencies:\n\n{''.join(set(dag_dependencies))}"
            else:
                schedule_interval = f"This DAG will trigger {schedule_interval}."

        doc_md_string = self.get_dag_doc(
            "base_dag_doc_template", COMPOSER_DOCUMENTATION_PATH
        )

        dag_purpose = dag_documentation.get("dag_purpose")
        additional_information = dag_documentation.get("additional_information")

        dag_path = DAGPackagesPathService.get_dag_path(dag_name=dag_name)

        tables_list = []

        if "queries" in listdir(dag_path):
            layer = listdir(f"{dag_path}/queries")[0]

            tables_list = DAGPackagesPathService.list_queries_files_in_composer(
                dag_name=dag_name, layer=layer, intermediate_path=intermediate_path
            )
            tables_list = [f"- `{table_name}` \n" for table_name in tables_list]

        return doc_md_string.format(
            dag_name=dag_name.upper().replace("_", " "),
            purpose=dag_purpose,
            chart_url=doc_md_chart_url,
            dag_id=dag_id,
            dag_owner=dag_owner,
            tables="".join(tables_list),
            trigger_interval=schedule_interval,
            additional_information=(
                f"\n\n### Additional Information\n\n{additional_information}"
                if additional_information
                else ""
            ),
        )

    @staticmethod
    def get_default_trigger_form_params() -> dict:
        """
        :return: dict with the default trigger form params.
        """
        return {
            "run_type": Param(
                default=DagRunTypeEnum.DEFAULT.value,
                type=["string", "null"],
                enum=[
                    DagRunTypeEnum.DEFAULT.value,
                    DagRunTypeEnum.TEST_RUN.value,
                    DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS.value,
                    DagRunTypeEnum.REPROCESSING_RUN.value,
                ],
                values_display={
                    DagRunTypeEnum.DEFAULT.value: "Select a run type. Default for manual runs: Test Run.",
                    DagRunTypeEnum.TEST_RUN.value: "Test Run - choose this to avoid impacting any dependents.",
                    DagRunTypeEnum.IMPACT_DOWNSTREAM_DEPENDENTS.value: "Impact Downstream Dependents",
                    DagRunTypeEnum.REPROCESSING_RUN.value: "Reprocessing Run - will trigger entire downstream pipeline from this DAG!",
                },
                description_md="""
                    Select one of this parameters to define which type of run:
                    **`test_run`**: Use this to create a DAG run only for testing and not impact downstream dependents. Default for manual runs.
                    **`impact_downstream_dependents`**: Use this to create a DAG run that will impact downstream dependents. Default for scheduled, dataset-triggered and mediator-triggered runs.
                        (obs: will still depends on other dependencies to run)
                    **`reprocessing_run`**: (WARNING!) Use this to trigger the entire downstream pipeline from this DAG.
                """,
            ),
            "load_start_date": Param(
                default=None,
                type=["string", "null"],
                format="date",
                description_md="""
                    Start interval that DAG will consider when filtering data. (e.g.: 'YYYY-MM-DD').
                    Default: data_interval_start of the DAG run.
                """,
            ),
            "load_end_date": Param(
                default=None,
                type=["string", "null"],
                format="date",
                description_md="""
                    End interval that DAG will consider when filtering data. (e.g.: 'YYYY-MM-DD').
                    Default: data_interval_start of the DAG run.
                """,
            ),
        }
