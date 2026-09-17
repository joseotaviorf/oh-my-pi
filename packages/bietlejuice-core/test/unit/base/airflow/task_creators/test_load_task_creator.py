from unittest import mock

from bietlejuice.base.airflow.task_creators.load_task_creator import LoadTaskCreator
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class DummyLoadTaskCreator(LoadTaskCreator):
    def _create_base_load_task(self, table_attributes: TableAttributes):
        task = mock.MagicMock()
        task.params = {}
        return task


class TestLoadTaskCreator:
    @mock.patch(
        "bietlejuice.base.airflow.task_creators.load_task_creator.dataset_adder.DatasetAdder.attach_dataset_to_task"
    )
    def test_create_task_puts_criticality_in_task_params_when_produce_datasets_true(
        self, mock_attach_dataset
    ):
        # arrange
        context = mock.MagicMock()
        context.is_validation = False
        context.bucket = "test-bucket"

        creator = DummyLoadTaskCreator(
            dag_execution_context=context,
            produce_datasets=True,
        )

        table_attributes = TableAttributes(
            dag_args={"name": "test_dag", "criticality": "Critical"},
            workflow_args={},
            layer=LayerEnum.CLEAN,
            table_name="test_table",
        )

        # act
        task = creator.create_task(table_attributes)

        # assert
        assert task.params["criticality"] == "Critical"

    @mock.patch(
        "bietlejuice.base.airflow.task_creators.load_task_creator.dataset_adder.DatasetAdder.attach_dataset_to_task"
    )
    def test_create_task_puts_owner_in_task_params_when_produce_datasets_true(
        self, mock_attach_dataset
    ):
        # arrange
        context = mock.MagicMock()
        context.is_validation = False
        context.bucket = "test-bucket"

        creator = DummyLoadTaskCreator(
            dag_execution_context=context,
            produce_datasets=True,
        )

        table_attributes = TableAttributes(
            dag_args={"name": "test_dag"},
            workflow_args={},
            layer=LayerEnum.CLEAN,
            table_name="test_table",
        )
        table_attributes.owner = "someone@quintoandar.com.br"

        # act
        task = creator.create_task(table_attributes)

        # assert
        assert task.params["owner"] == "someone@quintoandar.com.br"
