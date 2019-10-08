from collections import OrderedDict
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("SparkMetastoreService")


class SparkMetastoreService:
    def __init__(self, db, db_path, spark_sql_client):
        self.db = db
        self.db_path = db_path
        self.spark_sql_client = spark_sql_client

    @logger
    def create_database(self):
        self.spark_sql_client.run("CREATE DATABASE IF NOT EXISTS {}".format(self.db))

    @logger
    def get_table_names(self):
        return self.spark_sql_client.get_table_names(self.db)

    @logger
    def get_table_schema(self, table_name):
        return OrderedDict(
            field.simpleString().split(":")
            for field in self.spark_sql_client.get_table(
                "{}.{}".format(self.db, table_name)
            ).schema.fields
        )

    @logger
    def repair_table_partitions(self, table_name):
        """
        Execute a 'msck repair table' command on the Spark metastore.
        The time to execute this command can get really slow if the table has too many partitions, so it's better
        to use other methods like add_partition or create_new_partitions_from_df.
        :param table_name: name of the table in the schema (without schema prefix).
        :return: None.
        """
        self.spark_sql_client.run("msck repair table {}.{}".format(self.db, table_name))

    @logger
    def drop_table(self, table_name):
        self.spark_sql_client.run(
            "drop table if exists {}.{}".format(self.db, table_name)
        )

    @logger
    def refresh_table(self, table_name):
        self.spark_sql_client.run("refresh table {}.{}".format(self.db, table_name))

    @logger(exclude="df")
    def merge_schemas(self, table_name, file_format, partition_by_list, df):
        """
        Merge the schemas from the current table in the spark metastore and the input dataframe.
        If there are any new columns in the df that doesn't exist in the table in metastore, this method will recreate
        the table with the new columns.

        :param table_name: name of the table in the schema (without schema prefix).
        :param file_format: file format of the table in spark metastore.
        :param partition_by_list: list of the column names which the table is partitioned.
        :param df: spark dataframe with new data ready to load.
        :return: None.

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
        logger.info("m=merge_schemas, msg=new table definition: \n{}".format(ddl))
        self.drop_table(table_name)
        self.spark_sql_client.run(ddl)
        logger.info("m=merge_schemas, msg=table created with new schema")
        self.repair_table_partitions(table_name)

    @logger
    def add_partition(self, table_name, partition_by_dict):
        """
        Add a new partition to a table in Spark metastore given the table name and a partition dict.

        :param table_name: name of the table to be modified (without database prefix).
        :param partition_by_dict: python dict where the keys are the column names of the partitions and the values are
        the partition values.
        :return: None
        """
        partitions_section = ", ".join(
            [
                "{} = {}".format(k, v)
                if not isinstance(v, str)
                else "{} = '{}'".format(k, v)
                for k, v in partition_by_dict.items()
            ]
        )
        add_partition_query = "ALTER TABLE {}.{} ADD IF NOT EXISTS PARTITION ({})".format(
            self.db, table_name, partitions_section
        )
        self.spark_sql_client.run(add_partition_query)

    @logger(exclude="df")
    def create_new_partitions_from_df(
        self, table_name, df, partition_by_list, parallelism=4
    ):
        """
        Adds new partitions to a table in Spark metastore for each unique partition value found in a given a dataframe.
        Normally this method can be called after write a dataframe to the storage layer and the partitions of the
        respective table in the metastore need to be updated with the new partitions.

        :param table_name: name of the table to be modified (without database prefix).
        :param df: dataframe to extract partition values.
        :param partition_by_list: list of the names of the partition columns contained in the dataframe.
        :param parallelism: value to control how much queries to execute in the metastore at the same time.
        :return: None
        """
        df_partition_values = df.select(partition_by_list).distinct()
        partition_tuple_values = df_partition_values.rdd.map(tuple).collect()
        partition_by_dicts = [
            {x[0]: x[1] for x in zip(partition_by_list, partition_tuple_value)}
            for partition_tuple_value in partition_tuple_values
        ]
        with Pool(parallelism) as p:
            p.map(
                lambda partition_by_dict: self.add_partition(
                    table_name, partition_by_dict
                ),
                partition_by_dicts,
            )
        self.spark_sql_client.run("REFRESH TABLE {}.{}".format(self.db, table_name))

    @logger
    def get_table_path(self, table_name):
        """Get the folder full path on s3 where the table is saved"""
        return (
            self.spark_sql_client.run(
                "describe formatted {}.{}".format(self.db, table_name)
            )
            .where("col_name = 'Location'")
            .select("data_type")
            .collect()[0][0]
        )

    @logger
    def get_table_format(self, table_name):
        """Get the format in which the files of the table were saved"""
        return (
            self.spark_sql_client.run(
                "describe formatted {}.{}".format(self.db, table_name)
            )
            .where("col_name = 'Provider'")
            .select("data_type")
            .collect()[0][0]
            .lower()
        )

    @logger
    def get_file_paths_from_table(self, s3_client, table_name):
        """
        Get all the s3 files on datalake belonging to the table
        :param s3_client: S3Client object
        :param table_name: name of the table (without database prefix).
        :return: list of path and size tuples of all the files belonging to the table
        """
        table_path = self.get_table_path(table_name)
        table_format = self.get_table_format(table_name)

        all_objs = s3_client.list_objects(table_path, include_size=True)

        # filter only the files that finishes with table_format extension, for example: '.json'
        data_files = [
            (path, size) for path, size in all_objs if path.endswith(table_format)
        ]

        return data_files
