from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

logger = QuintoAndarLogger("MetastoreService")


class MetastoreService:
    def __init__(self, db, db_path, spark_sql_client):
        self.db = db
        self.db_path = db_path
        self.spark_sql_client = spark_sql_client

    def create_database(self):
        self.spark_sql_client.run("CREATE DATABASE IF NOT EXISTS {}".format(self.db))

    def get_table_names(self):
        sqlContext.tableNames(dbName=self.db)

    @logger(exclude="df")
    def make_schema_merging(self, table_name, file_format, partition_by_list, df):
        if not df:
            raise ValueError("m=make_schema_merging, msg=input df is None")
        if table_name not in self.get_table_names():
            raise ValueError("m=make_schema_merging, msg=input df is None")
        df_aux = self.spark_sql_client.run(
            "select * from {}.{} limit 0".format(self.db, table_name)
        )
        current_schema = OrderedDict(
            field.simpleString().split(":") for field in df_aux.schema.fields
        )
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
                "m=make_schema_merging, msg=the schema is compatible no need to recreate table"
            )
            return None

        logger.info(
            "m=make_schema_merging, msg=the schema is incompatible, creating new columns: {}".format(
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
            "m=make_schema_merging, the schema is incompatible, new table definition: \n{}".format(
                ddl
            )
        )

        self.spark_sql_client.run("drop table {}.{}".format(self.db, table_name))
        self.spark_sql_client.run(ddl)
        self.spark_sql_client.run("msck repair table {}.{}".format(self.db, table_name))

    def update_table_partitions(self, table_name):
        self.spark_sql_client.run("msck repair table {}.{}".format(self.db, table_name))
