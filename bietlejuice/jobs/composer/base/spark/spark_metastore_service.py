from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("SparkMetastoreService")


class SparkMetastoreService:
    def __init__(self, db, db_path, spark_sql_client):
        self.db = db
        self.db_path = db_path
        self.spark_sql_client = spark_sql_client

    def create_database(self):
        self.spark_sql_client.run("CREATE DATABASE IF NOT EXISTS {}".format(self.db))

    def get_table_names(self):
        return self.spark_sql_client.get_table_names(self.db)

    def get_table_schema(self, table_name):
        return OrderedDict(
            field.simpleString().split(":")
            for field in self.spark_sql_client.get_table(
                "{}.{}".format(self.db, table_name)
            ).schema.fields
        )

    def update_table_partitions(self, table_name):
        self.spark_sql_client.run("msck repair table {}.{}".format(self.db, table_name))

    def drop_table(self, table_name):
        self.spark_sql_client.run("drop table {}.{}".format(self.db, table_name))

    @logger(exclude="df")
    def merge_schemas(self, table_name, file_format, partition_by_list, df):
        """
        Method to merge the schemas from the current table in the spark metastore and the input dataframe. If there are any new columns in df that don't exist in the table in metastore, this method will recreate the table with the new columns.

        :param table_name: name of the table in the schema (without schema prefix)
        :param file_format: file format of the table in spark metastore
        :param partition_by_list: list of the column names which the table is partitioned
        :param df: spark dataframe with new data ready to load
        :return: None

        TODO: Split this method in two: one the compares schemas and other the recreate the table if necessary.
        """
        if df is None:
            raise ValueError("m=merge_schemas, msg=input df is None")
        if table_name not in self.get_table_names():
            raise ValueError(
                "m=merge_schemas, msg=Table does not exist in schema {}".format(self.db)
            )

        current_schema = self.get_table_schema(table_name)
        new_data_schema = OrderedDict(
            field.simpleString().split(":") for field in df.schema.fields
        )

        current_columns_names = [k for k in current_schema]
        new_data_columns_names = [k for k in new_data_schema]

        new_columns = [
            c for c in new_data_columns_names if c not in current_columns_names
        ]
        if not new_columns:
            logger.info(
                "m=merge_schemas, msg=the schema is compatible no need to recreate table"
            )
            return None

        logger.info(
            "m=merge_schemas, msg=the schema is incompatible, creating new columns: {}".format(
                str(new_columns)
            )
        )
        columns_ddl = ", ".join(
            ["`{}` {}".format(k, current_schema[k]) for k in current_columns_names]
            + ["`{}` {}".format(k, new_data_schema[k]) for k in new_columns]
        )
        partitions_ddl = ", ".join(partition_by_list)
        ddl = "create table {}.{} ({}) using {} partitioned by ({}) location '{}'".format(
            self.db,
            table_name,
            columns_ddl,
            file_format,
            partitions_ddl,
            self.db_path + table_name,
        )
        logger.info(
            "m=merge_schemas, the schema is incompatible, new table definition: \n{}".format(
                ddl
            )
        )
        self.drop_table(table_name)
        self.spark_sql_client.run(ddl)
        self.update_table_partitions(table_name)
