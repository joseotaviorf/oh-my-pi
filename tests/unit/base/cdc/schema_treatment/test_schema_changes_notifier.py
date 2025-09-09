import unittest
from unittest.mock import patch, MagicMock
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.base.cdc.schema_treatment.schema_changes_notifier import (
    SchemaChangesNotifier,
)


class TestSchemaChangesNotifier(unittest.TestCase):
    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.BaseSparkContext"
    )
    @patch("bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.GChatService")
    def test_should_do_nothing_when_table_does_not_exist(
        self, mock_gchat_service, mock_base_spark_context
    ):
        # arrange
        table_name = "test_table"
        new_df_mock = MagicMock()
        new_df_mock.columns = ["column1", "column2"]
        webhook_url = "webhook_url"
        mock_base_spark_context.spark.catalog.tableExists.return_value = False

        # act
        SchemaChangesNotifier.alert_schema_changes(table_name, new_df_mock, webhook_url)

        # assert
        mock_gchat_service.send_message.assert_not_called()

    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.BaseSparkContext"
    )
    @patch("bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.GChatService")
    def test_should_do_nothing_when_schema_has_not_changed(
        self, mock_gchat_service, mock_base_spark_context
    ):
        # arrange
        table_name = "test_table"
        new_df_mock = MagicMock()
        new_df_mock.columns = ["column1", "column2"]
        webhook_url = "webhook_url"
        existing_df_mock = MagicMock()
        existing_df_mock.columns = ["column1", "column2"]
        mock_base_spark_context.spark.catalog.tableExists.return_value = True
        mock_base_spark_context.spark.table.return_value = existing_df_mock

        # act
        SchemaChangesNotifier.alert_schema_changes(table_name, new_df_mock, webhook_url)

        # assert
        mock_gchat_service.send_message.assert_not_called()

    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.BaseSparkContext"
    )
    @patch("bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.GChatService")
    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.SparkTablePropertyHelper"
    )
    def test_should_alert_when_schema_has_changed(
        self,
        mock_spark_table_property_helper,
        mock_gchat_service,
        mock_base_spark_context,
    ):
        # arrange
        table_name = "test_table"
        new_df_mock = MagicMock()
        new_df_mock.columns = ["column1", "column2"]
        webhook_key = "webhook_url"
        existing_df_mock = MagicMock()
        existing_df_mock.columns = ["column1", "column3"]
        mock_base_spark_context.spark.catalog.tableExists.return_value = True
        mock_base_spark_context.spark.table.return_value = existing_df_mock

        # No previously removed columns
        mock_spark_table_property_helper.get_property.return_value = None

        # act
        SchemaChangesNotifier.alert_schema_changes(
            table_name, new_df_mock, webhook_key, mock_base_spark_context.spark
        )

        # assert
        expected_message = Message(
            "Schema of the source of table test_table has changed.\nColumns added: column2\nColumns removed: column3",
            "webhook_url",
        )
        mock_gchat_service.send_message.assert_called_once_with(expected_message)
        mock_spark_table_property_helper.set_property.assert_called_once_with(
            table_name, "removed_columns", "column3"
        )

    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.BaseSparkContext"
    )
    @patch("bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.GChatService")
    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.SparkTablePropertyHelper"
    )
    def test_should_alert_when_schema_has_changed_in_columns_not_previously_identified(
        self,
        mock_spark_table_property_helper,
        mock_gchat_service,
        mock_base_spark_context,
    ):
        # arrange
        table_name = "test_table"
        new_df_mock = MagicMock()
        new_df_mock.columns = ["column1", "column2"]
        webhook_key = "webhook_url"
        existing_df_mock = MagicMock()
        existing_df_mock.columns = ["column1", "column3"]
        mock_base_spark_context.spark.catalog.tableExists.return_value = True
        mock_base_spark_context.spark.table.return_value = existing_df_mock

        # Previously removed columns
        mock_spark_table_property_helper.get_property.return_value = "column3"

        # act
        SchemaChangesNotifier.alert_schema_changes(
            table_name, new_df_mock, webhook_key, mock_base_spark_context.spark
        )

        # assert
        expected_message = Message(
            "Schema of the source of table test_table has changed.\nColumns added: column2",
            "webhook_url",
        )
        mock_gchat_service.send_message.assert_called_once_with(expected_message)
        mock_spark_table_property_helper.set_property.assert_called_once_with(
            table_name, "removed_columns", "column3"
        )

    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.BaseSparkContext"
    )
    @patch("bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.GChatService")
    @patch(
        "bietlejuice.base.cdc.schema_treatment.schema_changes_notifier.SparkTablePropertyHelper"
    )
    def test_should_do_nothing_when_only_changed_columns_have_been_previously_identified(
        self,
        mock_spark_table_property_helper,
        mock_gchat_service,
        mock_base_spark_context,
    ):
        # arrange
        table_name = "test_table"
        new_df_mock = MagicMock()
        new_df_mock.columns = ["column1"]
        webhook_key = "webhook_url"
        existing_df_mock = MagicMock()
        existing_df_mock.columns = ["column1", "column2"]
        mock_base_spark_context.spark.catalog.tableExists.return_value = True
        mock_base_spark_context.spark.table.return_value = existing_df_mock

        # Previously removed columns
        mock_spark_table_property_helper.get_property.return_value = "column2"

        # act
        SchemaChangesNotifier.alert_schema_changes(table_name, new_df_mock, webhook_key)

        # assert
        mock_gchat_service.send_message.assert_not_called()
