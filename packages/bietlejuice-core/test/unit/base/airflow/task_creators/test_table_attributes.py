import pytest

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
        self,
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
        self,
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
        self,
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
        self,
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

    def test_get_has_soft_delete_should_return_true_if_set_to_true_in_table_customization(
        self,
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"has_soft_delete": "true"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.get_has_soft_delete() is True

    def test_get_has_soft_delete_should_return_false_if_set_to_false_in_table_customization(
        self,
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"has_soft_delete": "false"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.get_has_soft_delete() is False

    def test_get_has_soft_delete_should_return_true_if_set_to_true_in_workflow_args(
        self,
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"has_soft_delete": "true"}
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
        assert table_attributes.get_has_soft_delete() is True

    def test_get_has_soft_delete_should_return_false_if_set_to_false_in_workflow_args(
        self,
    ):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"has_soft_delete": "false"}
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
        assert table_attributes.get_has_soft_delete() is False

    def test_get_has_soft_delete_should_return_false_if_not_set_anywhere(self):
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
        assert table_attributes.get_has_soft_delete() is False

    def test_get_has_soft_delete_should_return_false_if_set_to_invalid_string(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {"has_soft_delete": "invalid"}
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
        assert table_attributes.get_has_soft_delete() is False

    @pytest.mark.parametrize("mode", [None, "none", "name", "id"])
    def test_column_mapping_mode_accepts_valid_values(self, mode):
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        table_customization = {"column_mapping_mode": mode} if mode is not None else {}

        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=LayerEnum.CLEAN,
            table_name="table_name",
            table_customization=table_customization,
        )

        assert table_attributes.column_mapping_mode == mode

    def test_column_mapping_mode_raises_on_invalid_value(self):
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        table_customization = {"column_mapping_mode": "nme"}

        with pytest.raises(ValueError, match="Invalid column_mapping_mode"):
            TableAttributes(
                dag_args=dag_args,
                workflow_args=workflow_args,
                layer=LayerEnum.CLEAN,
                table_name="table_name",
                table_customization=table_customization,
            )

    def test_criticality_table_override_wins_over_dag_criticality(self):
        # arrange
        dag_args = {"name": "dag_name", "criticality": "Low"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"criticality": "Critical"}

        # act
        table_attributes = TableAttributes(
            dag_args=dag_args,
            workflow_args=workflow_args,
            layer=layer,
            table_name=table_name,
            table_customization=table_customization,
        )

        # assert
        assert table_attributes.criticality == "Critical"

    def test_criticality_falls_back_to_dag_criticality(self):
        # arrange
        dag_args = {"name": "dag_name", "criticality": "Low"}
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
        assert table_attributes.criticality == "Low"

    def test_criticality_defaults_to_medium_when_neither_specified(self):
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
        assert table_attributes.criticality == "Medium"

    def test_criticality_raises_value_error_on_bogus_table_criticality(self):
        # arrange
        dag_args = {"name": "dag_name"}
        workflow_args = {}
        layer = LayerEnum.CLEAN
        table_name = "table_name"
        table_customization = {"criticality": "Bogus"}

        # act & assert
        with pytest.raises(ValueError, match="Invalid criticality"):
            TableAttributes(
                dag_args=dag_args,
                workflow_args=workflow_args,
                layer=layer,
                table_name=table_name,
                table_customization=table_customization,
            )


class TestTableAttributesTransformationGrade:
    def test_reads_grade_from_workflow_args(self):
        table_attributes = TableAttributes(
            dag_args={"name": "transformation_terminator_test"},
            workflow_args={
                "custom_schema": "terminator_test",
                "transformation_grade": "clean",
            },
            layer=LayerEnum.TRANSFORMATION,
            table_name="termination",
        )

        assert table_attributes.transformation_grade == "clean"
        assert table_attributes.spark_transformation_grade_args() == [
            "--transformation-grade",
            "clean",
        ]
        assert (
            table_attributes.get_prod_database_name()
            == "transformation_terminator_test_clean"
        )

    def test_ignores_grade_on_table_customization(self):
        table_attributes = TableAttributes(
            dag_args={"name": "transformation_terminator_test"},
            workflow_args={
                "custom_schema": "terminator_test",
                "transformation_grade": "clean",
            },
            layer=LayerEnum.TRANSFORMATION,
            table_name="termination",
            table_customization={"transformation_grade": "curated"},
        )

        assert table_attributes.transformation_grade == "clean"
        assert table_attributes.spark_transformation_grade_args() == [
            "--transformation-grade",
            "clean",
        ]

    def test_spark_args_raise_when_transformation_grade_missing(self):
        table_attributes = TableAttributes(
            dag_args={"name": "transformation_terminator_test"},
            workflow_args={"custom_schema": "terminator_test"},
            layer=LayerEnum.TRANSFORMATION,
            table_name="termination",
        )

        with pytest.raises(ValueError, match="transformation_grade"):
            table_attributes.spark_transformation_grade_args()
