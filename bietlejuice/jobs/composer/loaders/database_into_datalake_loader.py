from collections import OrderedDict

from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.wrappers import AthenaClient

logger = QuintoAndarLogger("DatabaseIntoDataLakeLoader")


class DatabaseIntoDataLakeLoader:
    DROP_QUERY_TEMPLATE = "DROP TABLE IF EXISTS `{database}`.`{table}`;"
    CREATE_QUERY_TEMPLATE = """CREATE EXTERNAL TABLE IF NOT EXISTS
                                `{database}`.`{table}`
                                (
                                  {columns}
                                )
                                {partitioned_by}
                                {format}
                                LOCATION '{path}'
                                ;"""

    @logger
    def __init__(self, config):
        self.config = config

    @logger
    def load_full_table(
        self, consumer, table_name, query=None, partition_by=None, concurrency=1
    ):
        db_source = consumer.connection["db"]
        final_path = "{}/{}/{}".format(
            self.get_datalake_path(), db_source, table_name.lower()
        )

        logger.info(
            "load_full_table, table={}.{}, msg=Getting  data...".format(
                db_source, table_name
            )
        )
        if query:
            df = consumer.get_data_from_query(query)
        else:
            if concurrency > 1:
                df = consumer.get_data_from_table_in_parallel(table_name, concurrency)
            else:
                df = consumer.get_data_from_table(table_name)

        logger.info(
            "load_full_table, table={}.{},"
            "msg=Writing data into datalake...".format(db_source, table_name)
        )
        # create the db in spark metastore in case it doesn't exist it
        SparkSession.builder.getOrCreate().sql(
            "CREATE DATABASE IF NOT EXISTS {}".format(self.get_datalake_db())
        )
        write_df = (
            df.write.mode("overwrite")
            .option("compression", self.get_codec())
            .format(self.get_file_format())
            .option("path", final_path)
        )
        if partition_by:
            for col in partition_by:
                write_df = write_df.partitionBy(col)
        new_table_name = "{}_{}".format(db_source, table_name)
        write_df.saveAsTable("{}.{}".format(self.get_datalake_db(), new_table_name))
        logger.info(
            "load_full_table, table={}.{},"
            "msg=Copied table into datalake ({}).".format(
                self.get_datalake_db(), new_table_name, final_path
            )
        )

    @staticmethod
    @logger
    def load_incremental_partitioned_table(
        self, consumer, table_name, query, partition_by
    ):
        if not partition_by:
            raise RuntimeError(
                "load_incremental_partitioned_table,"
                "msg=partition_by param is required to not overwrite the"
                "entire table but a single partition"
            )
        data_source = consumer.connection["db"]
        final_path = "{}/{}/{}".format(
            self.get_datalake_path(), data_source, table_name.lower()
        )
        for key, val in partition_by:
            final_path += "/{}={}".format(key, val)

        logger.info(
            "load_incremental_partitioned_table, query={},"
            "msg=Getting data from query...".format(query)
        )
        df = consumer.get_data_from_query(query)
        logger.info(
            "load_incremental_partitioned_table, msg=Writing data into datalake..."
        )
        df.write.mode("overwrite").option("compression", self.get_codec()).format(
            self.get_format()
        ).save(final_path)

        # refresh table in spark metastore
        spark = SparkSession.builder.getOrCreate()
        new_table_name = "{}_{}".format(data_source, table_name)
        spark.sql(
            "MSCK REPAIR TABLE {}.{}".format(self.get_datalake_db(), new_table_name)
        )
        spark.sql("REFRESH TABLE {}.{}".format(self.get_datalake_db(), new_table_name))
        logger.info(
            "load_incremental_partitioned_table, table={}.{},"
            "msg=Loaded successfully incremental data into datalake ({}).".format(
                self.get_datalake_db(), new_table_name, final_path
            )
        )

    @staticmethod
    @logger
    def create_athena_external_table(
        self, consumer, table_name, db_source, partition_by=None
    ):
        if not table_name.startswith(db_source + "_"):
            raise RuntimeError(
                "m=create_athena_external_table, table_name={}, db_source={}, "
                "msg=Database source must be the prefix of the "
                "table_name".format(table_name, db_source)
            )

        drop_query = self.DROP_QUERY_TEMPLATE.format(
            database=self.get_datalake_db(), table=table_name
        )
        AthenaClient.execute_athena_query(drop_query, self.get_datalake_db())
        logger.info(
            "m=create_athena_external_table, table={}.{}, msg=Dropped "
            "table in Athena successfully".format(self.get_datalake_db(), table_name)
        )

        table_schema = consumer.get_table_schema(table_name).collect()
        table_schema = OrderedDict(
            [
                (
                    row["col_name"],
                    row["col_type"].lower().replace("timestamp", "string"),
                )
                for row in table_schema
            ]
        )

        columns_section = ",\n  ".join(
            [
                "`" + col + "` " + col_type.upper()
                for col, col_type in table_schema.items()
                if not partition_by or col not in partition_by
            ]
        )
        partitions_section = ""
        if partition_by:
            partitions_section = "PARTITIONED BY (\n  {}\n)".format(
                ",\n  ".join(
                    ["`" + col + "` " + table_schema[col] for col in partition_by]
                )
            )
        create_query = self.CREATE_QUERY_TEMPLATE.format(
            database=self.get_datalake_db(),
            table=table_name,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=self.get_create_query_format(),
            path="{}/{}/{}".format(
                self.get_datalake_path(), db_source, table_name[len(db_source) + 1 :]
            ),
        )
        AthenaClient.execute_athena_query(create_query, self.get_datalake_db())
        if partition_by:
            AthenaClient.execute_athena_query(
                "MSCK REPAIR TABLE `{}`.`{}`;".format(
                    self.get_datalake_db(), table_name
                ),
                self.get_datalake_db(),
            )

        logger.info(
            "m=_create_athena_external_table, table={}.{}, msg=The table was created "
            "successfully in Athena".format(self.get_datalake_db(), table_name)
        )

    def get_datalake_db(self):
        if "datalake_db" not in self.config:
            raise ValueError(
                "param=datalake_db, msg=Parameter is required in database loader "
                "configuration."
            )
        return self.config["datalake_db"]

    def get_datalake_path(self):
        if "datalake_path" not in self.config:
            raise ValueError(
                "param=datalake_path, msg=Parameter is required in database loader "
                "configuration."
            )
        return self.config["datalake_path"]

    def get_codec(self):
        if "codec" not in self.config:
            raise ValueError(
                "param=codec, msg=Parameter is required in database loader "
                "configuration."
            )
        return self.config["codec"]

    def get_file_format(self):
        if "format" not in self.config:
            raise ValueError(
                "param=format, msg=Parameter is required in database loader "
                "configuration."
            )
        return self.config["format"]

    def get_create_query_format(self):
        if "create_query_format" not in self.config:
            raise ValueError(
                "param=create_query_format, msg=Parameter is required in database loader "
                "configuration."
            )
        return self.config["create_query_format"]
