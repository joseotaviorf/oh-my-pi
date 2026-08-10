from unittest import mock

from bietlejuice.base.airflow.task_creators.load_cdf_to_datazord_task_creator import (
    LoadCDFtoDatazordTaskCreator,
)
from bietlejuice.base.airflow.task_creators.table_attributes import TableAttributes
from bietlejuice.base.pipeline.layer_enum import LayerEnum

_CONFIGURATION_SERVICE_PATH = (
    "bietlejuice.base.airflow.task_creators.load_cdf_to_datazord_task_creator"
    ".ConfigurationService"
)


def _make_table_attributes():
    return TableAttributes(
        dag_args={"name": "enrich-transactional-entities"},
        workflow_args={
            "type": "query_delta_datazord",
            "datazord_config": {
                "entity": "business_objects",
                "table": "entities",
                "key_columns": ["sk_entity"],
                "topic_namespace": "datazord",
                "schema_validation": "none",
                "include_delete_events": True,
            },
        },
        layer=LayerEnum.ENRICH,
        table_name="entities",
    )


def _make_context():
    ctx = mock.MagicMock()
    ctx.environment = "forno"
    ctx.workflow_args = _make_table_attributes().workflow_args
    ctx.dag_args = {"name": "enrich-transactional-entities"}
    return ctx


class TestLoadCDFtoDatazordTaskCreator:
    def test_parameters_include_explicit_topic_and_new_flags(self):
        creator = LoadCDFtoDatazordTaskCreator(
            dag_execution_context=_make_context(),
            config_service=mock.MagicMock(
                get_config=mock.Mock(
                    side_effect=lambda key: {
                        "datazord_kafka_bootstrap_servers": "kafka:9092",
                        "datazord_base_checkpoint_location": "s3://checkpoints",
                    }[key]
                )
            ),
        )
        table_attrs = _make_table_attributes()

        params = creator._get_parameters(table_attrs, ["sk_entity"])

        assert params == [
            "--delta-table",
            "enrich-transactional-entities.entities",
            "--key-columns",
            "sk_entity",
            "--kafka-topic",
            "forno_datazord.business_objects",
            "--kafka-bootstrap-servers",
            "kafka:9092",
            "--checkpoint-location",
            "s3://checkpoints/enrich-transactional-entities/entities",
            "--entity",
            "business_objects",
            "--schema-validation",
            "none",
            "--include-delete-events",
        ]

    def test_wonka_default_topic_when_kafka_topic_omitted(self):
        ctx = _make_context()
        ctx.environment = "prod"
        ctx.workflow_args = {
            "datazord_config": {
                "entity": "my_entity",
                "table": "feature_set__latest",
                "key_columns": ["id"],
            }
        }
        creator = LoadCDFtoDatazordTaskCreator(
            dag_execution_context=ctx,
            config_service=mock.MagicMock(
                get_config=mock.Mock(
                    side_effect=lambda key: {
                        "datazord_kafka_bootstrap_servers": "kafka:9092",
                        "datazord_base_checkpoint_location": "s3://checkpoints",
                    }[key]
                )
            ),
        )
        table_attrs = TableAttributes(
            dag_args={"name": "wonka-pipeline"},
            workflow_args=ctx.workflow_args,
            layer=LayerEnum.WONKA,
            table_name="feature_set__latest",
        )

        params = creator._get_parameters(table_attrs, ["id"])

        checkpoint_index = params.index("--checkpoint-location")
        assert params[checkpoint_index + 1] == "s3://checkpoints/feature_set__latest"
        assert "--kafka-topic" in params
        topic_index = params.index("--kafka-topic")
        assert params[topic_index + 1] == "prod_wonka.my_entity"
        assert "--schema-validation" in params
        schema_validation_index = params.index("--schema-validation")
        assert params[schema_validation_index + 1] == "cassandra"
        assert "--include-delete-events" not in params
