from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.base.spark.spark_table_property_helper import SparkTablePropertyHelper
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

logger = QuintoAndarLogger("schema_changes_alert")


class SchemaChangesNotifier:
    @staticmethod
    def alert_schema_changes(
        table_name: str,
        new_df: DataFrame,
        webhook_url: str,
        spark=BaseSparkContext.spark,
    ) -> None:
        """
        Send alert through a webhook  when the schema of a table changes
        """
        if not spark.catalog.tableExists(table_name):
            return

        existing_df = spark.table(table_name)
        if set(new_df.columns) != set(existing_df.columns):
            logger.info(
                f"m=alert_schema_changes, table_name={table_name}, msg=Schema of table has changed. Sending alert..."
            )
            added_columns = set(new_df.columns) - set(existing_df.columns)
            # We store the previously identified removed columns in the table properties. This is to avoid sending the same message multiple times.
            previously_removed_columns = (
                SchemaChangesNotifier._retrieve_previously_removed_columns(table_name)
            )
            all_removed_columns = set(existing_df.columns) - set(new_df.columns)
            newly_removed_columns = all_removed_columns - previously_removed_columns

            # We check again because the difference in the schema may have been simply caused by previously removed columns
            if not added_columns and not newly_removed_columns:
                return

            message = SchemaChangesNotifier._create_changes_message(
                table_name, added_columns, newly_removed_columns, webhook_url
            )
            GChatService.send_message(message)
            SparkTablePropertyHelper.set_property(
                table_name, "removed_columns", ",".join(all_removed_columns)
            )

    @staticmethod
    def _create_changes_message(
        table_name: str,
        added_columns: set,
        newly_removed_columns: set,
        webhook_url: str,
    ) -> Message:
        """
        Format the message to alert when the schema of a table changes
        """
        message = f"Schema of the source of table {table_name} has changed.\n"
        if added_columns:
            message += f"Columns added: {', '.join(added_columns)}\n"
        if newly_removed_columns:
            message += f"Columns removed: {', '.join(newly_removed_columns)}\n"
        return Message(message.rstrip(), webhook_url)

    @staticmethod
    def _retrieve_previously_removed_columns(table_name: str) -> set:
        removed_columns = SparkTablePropertyHelper.get_property(
            table_name, "removed_columns"
        )
        if removed_columns:
            return set(removed_columns.split(","))
        return set()
