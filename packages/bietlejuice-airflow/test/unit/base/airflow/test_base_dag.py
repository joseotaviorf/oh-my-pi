from unittest import mock

import pytest

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestBaseDAG:
    def setup_method(self):
        BaseDAG.get_dag_doc.cache_clear()

    def teardown_method(self):
        BaseDAG.get_dag_doc.cache_clear()

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

        mocked_get_dag_path.return_value = "/tmp/dags/dag_name"

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

    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_get_dag_doc_lru_serves_cached_result(self, mock_get_dag_path, tmp_path):
        # arrange — write a real markdown file so open() succeeds
        dag_name = "cache_test_dag"
        doc_content = "# Cache Test Doc"
        dag_dir = tmp_path / dag_name
        dag_dir.mkdir()
        doc_file = dag_dir / f"{dag_name}.md"
        doc_file.write_text(doc_content)
        mock_get_dag_path.return_value = str(dag_dir)

        # act — call twice with the same arguments
        result_1 = BaseDAG.get_dag_doc(dag_name=dag_name)
        result_2 = BaseDAG.get_dag_doc(dag_name=dag_name)

        # assert — same content returned; get_dag_path called only once because
        # the second call is served from the LRU cache
        assert result_1 == result_2 == doc_content
        mock_get_dag_path.assert_called_once()

    @mock.patch.object(DAGPackagesPathService, "get_dag_path")
    def test_get_dag_doc_cache_clear_forces_reread(self, mock_get_dag_path, tmp_path):
        # arrange
        dag_name = "cache_clear_dag"
        dag_dir = tmp_path / dag_name
        dag_dir.mkdir()
        (dag_dir / f"{dag_name}.md").write_text("initial content")
        mock_get_dag_path.return_value = str(dag_dir)

        # act — prime cache, clear it, call again
        BaseDAG.get_dag_doc(dag_name=dag_name)
        BaseDAG.get_dag_doc.cache_clear()
        BaseDAG.get_dag_doc(dag_name=dag_name)

        # assert — get_dag_path called twice because the LRU cache was invalidated
        assert mock_get_dag_path.call_count == 2
