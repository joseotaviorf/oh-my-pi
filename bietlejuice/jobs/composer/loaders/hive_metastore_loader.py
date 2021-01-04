from hive_metastore_client.builders import ColumnBuilder
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("HiveMetastoreLoader")


class HiveMetastoreLoader:
    """Loads Spark DataFrame schemas into Hive Metastore as a table."""

    def __init__(self, metastore_service):
        """
        Constructor.

        :param metastore_service: service to interact with the Hive Metastore
        :type metastore_service: HiveMetastoreService
        """
        self.hive_metastore_service = metastore_service

    def compare_table_schema(self, database_name, table_name, source_schema):
        """
        Compare the table schema from Spark Metastore (in Databricks) with Hive
         Metastore.

        :param database_name: the database name of the table
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param source_schema: columns to compare the table schema with
        :type source_schema: collections.OrderedDict
        :return: dictionary with two positions: key "added" with a list of new
         columns and the key "removed" with a list removed columns.
        :rtype: dict
        """
        hive_table_columns = self.hive_metastore_service.get_table_columns(
            database_name, table_name
        )

        added_columns, removed_columns = self._get_tables_difference(
            source_schema, hive_table_columns
        )

        return {"added": added_columns, "removed": removed_columns}

    @staticmethod
    def _get_tables_difference(table_source, metastore_columns):
        """
        Identifies the columns that were added and removed from the table source.

        :param table_source: the most updated columns list from table source
        :type table_source: collections.OrderedDict
        :param metastore_columns: the columns list from table's data lake metastore
        :type metastore_columns: Dict[str, str]
        :return: a list with new columns and another list with the removed ones
        :rtype: List[FieldSchema], List[str]
        """
        metastore_columns_names = list(metastore_columns.keys())
        removed_columns = metastore_columns_names
        added_columns = []
        for col_name, col_type in table_source.items():
            if (
                col_name in metastore_columns_names
                and col_type == metastore_columns[col_name]
            ):
                removed_columns.remove(col_name)
            else:
                added_columns.append(ColumnBuilder(col_name, col_type).build())

        return added_columns, removed_columns
