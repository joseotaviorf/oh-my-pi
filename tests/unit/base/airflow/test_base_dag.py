from dags import DAG_PACKAGES_ROOT
import pytest
from unittest import mock

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestBaseDAG:
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_get_dag_doc(self, mocked_get_dag_path):
        # arrange
        dag_name = "dag_name"

        mocked_get_dag_path.return_value = "path"
        DAGPackagesPathService.get_dag_path = mocked_get_dag_path

        # assert
        with pytest.raises(Exception):
            assert BaseDAG.get_dag_doc(dag_name=dag_name)

    @mock.patch.object(BaseDAG, "get_dag_doc")
    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_exception_generate_doc_md_str(
        self, mocked_get_dag_path, mocked_get_dag_doc
    ):
        # arrange
        base_dag = BaseDAG()

        mocked_get_dag_doc.return_value = "dag_doc"
        base_dag.get_dag_doc = mocked_get_dag_doc

        mocked_get_dag_path.return_value = f"{DAG_PACKAGES_ROOT}/dag_name"

        dag_name = "dag_name"
        doc_md_chart_url = "doc_md_chart_url"
        dag_owner = "dag_owner"

        # assert
        with pytest.raises(Exception):
            assert base_dag.generate_doc_md_str(
                dag_name=dag_name,
                doc_md_chart_url=doc_md_chart_url,
                dag_owner=dag_owner,
            )

    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    @mock.patch.object(DAGPackagesPathService, "list_queries_files_in_composer")
    @mock.patch("bietlejuice.base.airflow.base_dag.listdir")
    def test_generate_doc_md_str(
        self, mocked_get_dag_path, mocked_list_queries_files_in_composer, BaseDAGListDir
    ):
        # arrange

        mocked_get_dag_path.return_value = "path"
        DAGPackagesPathService.get_dag_path = mocked_get_dag_path

        mocked_list_queries_files_in_composer.return_value = ["table"]
        DAGPackagesPathService.list_queries_files_in_composer = (
            mocked_list_queries_files_in_composer
        )

        BaseDAGListDir.return_value = None

        dag_name = "dag_name"
        doc_md_chart_url = "doc_md_chart_url"
        dag_owner = "dag_owner"
        schedule_interval = "30 2 * * *"
        trigger_interval = "At 02:30 AM"

        doc_md = BaseDAG.generate_doc_md_str(
            dag_name=dag_name,
            doc_md_chart_url=doc_md_chart_url,
            dag_owner=dag_owner,
            schedule_interval=schedule_interval,
        )

        # assert
        assert dag_name in doc_md
        assert doc_md_chart_url in doc_md
        assert dag_owner in doc_md
        assert trigger_interval in doc_md
