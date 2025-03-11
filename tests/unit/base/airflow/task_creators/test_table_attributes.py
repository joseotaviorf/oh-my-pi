from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestTableAttributes:
    def test_should_save_layer_and_table_name(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.layer == layer
        assert table_attributes.table_name == table_name

    def test_should_get_table_customization_from_workflow_args_if_not_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {
            "tables_customization": {"table_name": {"custom_schema": "custom_schema"}}
        }
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert (
            table_attributes.table_customization
            == workflow_args["tables_customization"]["table_name"]
        )

    def test_should_infer_schema_from_dag_name_if_not_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.schema == "dag_name"

    def test_should_infer_schema_from_dag_name_removing_enrich_prefix_if_not_informed(
        self
    ):
        # arrange
        dag_args = {"name": "enrich_dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.schema == "dag_name"

    def test_should_use_schema_from_workflow_args_if_nothing_else_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"custom_schema": "custom_schema"}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.schema == "custom_schema"

    def test_should_use_table_specific_schema_instead_of_default(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"custom_schema": "custom_schema"}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"custom_schema": "table_custom_schema"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.schema == "table_custom_schema"

    def test_should_have_full_extraction_type_if_not_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.extraction_type == "full"

    def test_should_use_default_extraction_type_arg_if_nothing_else_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"default_extraction_type": "<default_extraction_type>"}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.extraction_type == "<default_extraction_type>"

    def test_should_use_table_specific_extraction_type_instead_of_default(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"default_extraction_type": "<default_extraction_type>"}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"extraction_type": "<table_specific_extraction_type>"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.extraction_type == "<table_specific_extraction_type>"

    def test_should_use_default_of_layer_instead_of_default_for_extraction_type(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {
            "default_extraction_type": "<default_extraction_type>",
            "default_clean_extraction_type": "<default_clean_extraction_type>",
        }
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.extraction_type == "<default_clean_extraction_type>"

    def test_should_use_table_specific_extraction_type_instead_of_default_for_layer(
        self
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {
            "default_extraction_type": "<default_extraction_type>",
            "default_clean_extraction_type": "<default_clean_extraction_type>",
        }
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {
            "clean_extraction_type": "<table_specific_extraction_type>"
        }

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.extraction_type == "<table_specific_extraction_type>"

    def test_should_have_empty_partitions_if_not_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.partitions == []

    def test_should_use_default_partitions_arg_if_nothing_else_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"default_partitions": ["<default_partition>"]}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.partitions == ["<default_partition>"]

    def test_should_use_table_specific_partitions_instead_of_default(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"default_partitions": ["<default_partition>"]}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"partitions": ["<table_specific_partition>"]}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.partitions == ["<table_specific_partition>"]

    def test_should_use_default_of_layer_instead_of_default_for_partitions(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {
            "default_partitions": ["<default_partition>"],
            "default_raw_partitions": ["<default_raw_partition>"],
        }
        layer = LayerEnum.RAW
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.partitions == ["<default_raw_partition>"]

    def test_should_use_table_specific_partitions_instead_of_default_for_layer(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {
            "default_partitions": ["<default_partition>"],
            "default_raw_partitions": ["<default_raw_partition>"],
        }
        layer = LayerEnum.RAW
        table_name = "table_name"
        table_customization = {"raw_partitions": ["<table_specific_partition>"]}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.partitions == ["<table_specific_partition>"]

    def test_has_custom_spark_job_should_return_false_if_not_informed(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert not table_attributes.has_custom_spark_job

    def test_has_custom_spark_job_should_return_true_if_load_spark_job_is_set_in_workflow_args(
        self
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"load_spark_job": "abc.py"}
        layer = LayerEnum.CLEAN
        table_name = "table_name"

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
        )

        # assert
        assert table_attributes.has_custom_spark_job

    def test_has_custom_spark_job_should_return_true_if_load_spark_job_is_set_in_table_customization(
        self
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"load_spark_job": "abc.py"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.has_custom_spark_job
