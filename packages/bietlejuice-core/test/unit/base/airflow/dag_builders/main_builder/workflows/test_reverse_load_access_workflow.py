from unittest import mock

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.reverse_load_access_workflow import (
    ReverseLoadAccessWorkflow,
)
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService


class TestReverseLoadAccessWorkflowGetTables:
    def test_get_tables_merges_tuple_query_names_with_customization(self):
        """Regression: list_queries_files_in_composer returns a tuple (lru_cache)."""
        workflow = ReverseLoadAccessWorkflow.__new__(ReverseLoadAccessWorkflow)
        workflow.dag_name = "reverse_sale_listings_report"
        workflow.dag_args = {"name": "reverse_sale_listings_report"}
        workflow.workflow_args = {
            "tables_customization": {"extra_table": {"load_spark_job": "export.py"}}
        }

        with mock.patch.object(
            DAGPackagesPathService,
            "list_queries_files_in_composer",
            return_value=("query_table",),
        ):
            tables, tables_with_queries = workflow._get_tables()

        assert {table.table_name for table in tables} == {
            "query_table",
            "extra_table",
        }
        assert tables_with_queries == ["query_table"]
