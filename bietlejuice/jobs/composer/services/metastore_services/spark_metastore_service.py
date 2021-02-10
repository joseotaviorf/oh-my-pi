import copy
from collections import OrderedDict

from pyspark.sql.functions import col
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.services.metastore_services.metastore_service import (
    MetastoreService,
)

logger = QuintoAndarLogger("SparkMetastoreService")


class SparkMetastoreService(MetastoreService):
    """
    Service to interact with the Spark Metastore (Hive Metastore).

    :param spark_client: a client to interact with Spark Metastore
    :type spark_client: SparkClient
    """

    def __init__(self, spark_client):
        self._client = spark_client

    @property
    def client(self):
        return self._client

    @logger
    def get_table_names(self, database_name, regex="*"):
        """
        Gets the names of the tables and views in a database
        :param database_name: database name
        :type database_name: str
        :param regex: regular expression to filter table and view names. Only the
        wildcard *, which indicates any character, or |, which indicates a choice
        between characters, can be used.
        :type regex: str
        :return list with the table names
        """
        query = f"SHOW TABLES IN {database_name} LIKE '{regex}'"
        df = self.client.get_records(query).collect()
        res = [table.tableName for table in df]

        return res

    @staticmethod
    def _get_partition_keys_from_table_description(table_desc_df):
        """
        Gets the partition keys from the columns dataframe

        :param table_desc_df: pyspark.sql.Dataframe
        :return: OrderedDict with partition keys names and types in tuples
        :rtype: collections.OrderedDict[(string, string)]
        """
        partition_keys = []
        all_cols_list = table_desc_df.collect()
        for index, item in enumerate(all_cols_list):
            if item[0] == "# col_name":
                partition_keys = all_cols_list[index + 1 :]
                break

        partition_keys = OrderedDict(
            [(row["col_name"], row["data_type"].lower()) for row in partition_keys]
        )

        return partition_keys

    @logger
    def get_table_schema(self, database_name, table_name, ignore_partition_keys=False):
        """
        Gets the schema (columns' names and types) of a table

        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param ignore_partition_keys: indicates if the partition keys should be
         removed from the result set
        :type ignore_partition_keys: bool
        :return: OrderedDict with partition keys names and types in tuples
        :rtype: collections.OrderedDict[(string, string)]
        """
        result_df = super().get_table_description(database_name, table_name)

        partition_cols = []
        if ignore_partition_keys:
            partition_keys = self._get_partition_keys_from_table_description(result_df)
            partition_cols = [col_name for col_name in partition_keys]

        cols_list_df = (
            result_df.select("col_name", "data_type")
            .filter(col("col_name").rlike(r"^\w"))
            .filter(~col("col_name").isin(partition_cols))
        )

        table_columns = OrderedDict(
            [
                (row["col_name"], row["data_type"].lower())
                for row in cols_list_df.collect()
            ]
        )

        return table_columns

    @logger
    def get_table_partition_keys_names(self, database_name, table_name):
        """
        Gets the partition key's names of a table

        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: list of partition keys names
        :rtype: List[str]
        """
        result_df = super().get_table_description(database_name, table_name)
        partition_keys = self._get_partition_keys_from_table_description(result_df)

        return [col_name for col_name in partition_keys]

    @logger
    def refresh_table(self, database_name, table_name):
        """
        Refresh all cached entries associated with a table. If the table was
        previously cached, then it would be cached lazily the next time it is scanned.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        """
        command = f"REFRESH TABLE {database_name}.{table_name}"
        self.client.run(command)

    @logger
    def get_table_path(self, database_name, table_name):
        """
        Gets the location of the data files of a table.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: location of the table data as a str
        """
        df = super().get_table_description(database_name, table_name, True)
        res = df.where("col_name = 'Location'").select("data_type").collect()[0][0]

        return res

    @logger
    def get_table_format(self, database_name, table_name):
        """
        Gets the format of the data files of a table.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :return: the format of the data files as a str
        """
        df = super().get_table_description(database_name, table_name, True)
        res = (
            df.where("col_name = 'Provider'")
            .select("data_type")
            .collect()[0][0]
            .lower()
        )

        return res

    @logger
    def get_file_paths_and_sizes_from_table(self, database_name, table_name, s3_client):
        """
        Gets the path and size of each data file of a table.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param s3_client: a client to interact with S3
        :type s3_client: S3Service
        :return: list of path and size tuples of all the data files belonging to the
        table
        """
        table_path = self.get_table_path(database_name, table_name)
        table_format = self.get_table_format(database_name, table_name)

        all_objs = s3_client.list_objects(table_path, include_size=True)

        # filter only the files that finishes with table_format extension,
        # for example: '.json'
        data_files = [
            (path, size) for path, size in all_objs if path.endswith(table_format)
        ]

        return data_files

    @logger(exclude="df")
    def merge_table_and_dataframe_schemas(self, database_name, table_name, df):
        """
        Merges the schemas of an existing table and a dataframe by an union operation.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param df: a dataframe
        :type df: SparkDataFrame
        :return: a schema formed by an union operation as an OrderedDict.
        """

        if not df:
            raise ValueError(
                "m=merge_table_and_dataframe_schemas, msg=input dataframe is empty"
            )
        if table_name not in self.get_table_names(database_name):
            raise ValueError(
                f"m=merge_table_and_dataframe_schemas, table={table_name}, "
                f"database={database_name}, msg=table "
                "does not exist in database "
            )

        table_schema = self.get_table_schema(database_name, table_name)
        df_schema = OrderedDict(
            field.simpleString().split(":", 1) for field in df.schema.fields
        )

        new_schema = copy.deepcopy(table_schema)
        for col_df in df_schema:
            if col_df not in new_schema:
                new_schema[col_df] = df_schema[col_df]

        return new_schema

    @logger
    def create_external_table(
        self,
        database_name,
        table_name,
        table_location,
        table_schema,
        partition_cols,
        format_options,
    ):
        """
        Creates an external table based on underlying data files that exists in
        Amazon S3. When you create an external table, the data referenced must comply
        with the default format or the format that you specify in format_options.
        clauses.
        :param database_name: database name
        :type database_name: str
        :param table_name: table name
        :type table_name: str
        :param table_location: specifies the location of the underlying data,
        for example, 's3://mystorage/'
        :param table_schema: specifies the name and type for each column to be
        created (including partitioning columns).
        :type table_schema: OrderedDict
        :param partition_cols: specifies the names of partition columns in case of
        existence. A table can have one or more partitions, which consist of a
        distinct column name and value combination. A separate data directory is
        created for each specified combination, which can improve query performance
        in some circumstances. Partitioned columns don't exist within the table data
        itself.
        :type partition_cols: list
        :param format_options: specifies the format of the data files.
        :type format_options: str
        """

        # columns builder
        columns_section = ",\n".join(
            ["  `" + col + "` " + col_type for col, col_type in table_schema.items()]
        )

        # partitions builder
        partitions_section = ""
        if partition_cols:
            partitions_section = "\nPARTITIONED BY (\n  {}\n)".format(
                ",\n  ".join([" `" + col + "`" for col in partition_cols])
            )

        command = (
            f"CREATE TABLE IF NOT EXISTS `{database_name}`.`{table_name}`\n"
            f"(\n"
            f"{columns_section}\n"
            ")\n"
            f"USING {format_options}\n"
            f"{partitions_section}\n"
            f"LOCATION '{table_location}'"
        )

        self.client.run(command)
        logger.info(
            f"m=create_external_table, table={database_name}.{table_name}, msg=the "
            f"table was created successfully in the metastore."
        )
