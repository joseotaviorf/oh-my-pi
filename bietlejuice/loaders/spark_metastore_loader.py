from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.schema_service import SchemaService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper

logger = QuintoAndarLogger("SparkMetastoreLoader")


class SparkMetastoreLoader:
    """
    Loads Spark DataFrames into Spark Metastore as a table.

    :param metastore_service: service to interact with the Spark Metastore
    :type metastore_service: SparkMetastoreService
    """

    def __init__(self, metastore_service):
        self.metastore_service = metastore_service
        self.schema_service = SchemaService

    def update_metastore(
        self,
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions=[],
        force_recreate=True,
    ):
        """
        Saves the schema of the Spark Dataframe as a table in metastore.
        If table already exists and dataframe and table schemas are different, merges schemas and recreates table.
        If schemas are equal, does nothing.

        :param df: a dataframe
        :type df: DataFrame
        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param format_options: the file format options used to save
        :type format_options: str
        :param database_location: location of the database in the object storage
        :type database_location: str
        :param partitions: names of partitioning columns
        :type partitions: list
        :param force_recreate: indicates if it must force table recreation in metastore
        :type force_recreate: bool
        :return: None
        """

        if not df:
            raise ValueError("m=update_metastore, msg=Spark DataFrame is empty")
        if not isinstance(database_name, str):
            raise ValueError("m=update_metastore, msg=database needs to be a string")
        if not isinstance(table_name, str):
            raise ValueError("m=update_metastore, msg=table_name needs to be a string")
        if not isinstance(format_options, str):
            raise ValueError(
                "m=update_metastore, msg=format_options needs to be a string"
            )
        if not isinstance(database_location, str):
            raise ValueError(
                "m=update_metastore, msg=database_location needs to be a string"
            )

        s3_path = database_location + table_name

        # if it mustn't force table recreation and table already exists,
        # it merges dataframe schema with table schema if they are different
        if not force_recreate and self.is_table_in_metastore(database_name, table_name):
            logger.info(
                "m=update_metastore, db={}, table={}, msg=existing table in metastore, "
                "checking if it needs to be merged with dataframe schema".format(
                    database_name, table_name
                )
            )
            merge_schema = self.create_merge_schema(database_name, table_name, df)
            if merge_schema:
                logger.info(
                    "m=update_metastore, db={}, table={}, msg=existing table in metastore, "
                    "merging with dataframe schema".format(database_name, table_name)
                )
                self.recreate_table(
                    database_name,
                    table_name,
                    merge_schema,
                    s3_path,
                    format_options,
                    partitions,
                )
            else:
                logger.warning(
                    "m=update_metastore, db={}, table={}, msg=table and dataframe have the same schema "
                    "and metastore will not be changed.".format(
                        database_name, table_name
                    )
                )
        else:
            logger.info(
                "m=update_metastore, db={}, table={}, msg=table is not in metastore "
                "or we are forcing table recreation: creating it with dataframe schema".format(
                    database_name, table_name
                )
            )
            self.create_table(
                database_name, table_name, df, s3_path, format_options, partitions
            )

        logger.info(
            "m=update_metastore, db={}, table={}, msg=successfully loaded table in metastore.".format(
                database_name, table_name
            )
        )

        # We want to sync to Unity Catalog when possible
        # Except if the table is partitioned. We're going to call the sync in create_new_partitions_from_df,
        # not here.
        if (
            UnityCatalogHelper.is_cluster_unity_catalog_enabled()
            and not UnityCatalogHelper.is_default_catalog_using_unity()
            and not partitions
        ):
            UnityCatalogHelper.sync_table_to_unity_catalog(
                f"{database_name}.{table_name}"
            )

    def is_table_in_metastore(self, database_name, table_name):
        return table_name in self.metastore_service.get_table_names(database_name)

    def create_merge_schema(self, database_name, table_name, df):
        table_schema = self.metastore_service.get_table_schema(
            database_name, table_name
        )
        new_schema = self.metastore_service.merge_table_and_dataframe_schemas(
            database_name, table_name, df
        )
        if new_schema != table_schema:
            return new_schema

    def recreate_table(
        self, database_name, table_name, new_schema, s3_path, format_options, partitions
    ):
        self.metastore_service.drop_table(database_name, table_name)
        self.metastore_service.create_external_table(
            database_name, table_name, s3_path, new_schema, partitions, format_options
        )
        if partitions:
            self.metastore_service.repair_table_partitions(database_name, table_name)

    def create_table(
        self, database_name, table_name, df, s3_path, format_options, partitions
    ):
        df_schema = self.schema_service.get_schema_from_dataframe(df)
        self.metastore_service.drop_table(database_name, table_name)
        self.metastore_service.create_external_table(
            database_name, table_name, s3_path, df_schema, partitions, format_options
        )
        if partitions:
            self.metastore_service.repair_table_partitions(database_name, table_name)
