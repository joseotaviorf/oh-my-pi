from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.wrappers import AthenaClient

logger = QuintoAndarLogger("DatabaseIntoDataLakeLoader")

spark = BaseSparkContext.spark


class DatabaseIntoDataLakeLoader:
    DROP_TABLE_QUERY_TEMPLATE = "DROP TABLE IF EXISTS `{database}`.`{table}`;"
    CREATE_TABLE_QUERY_TEMPLATE = """CREATE EXTERNAL TABLE IF NOT EXISTS
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
        final_path = "{}/{}".format(self.datalake_path, table_name.lower())

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
        spark.sql("CREATE DATABASE IF NOT EXISTS {}".format(self.datalake_db))
        write_df = (
            df.write.mode("overwrite")
            .option("compression", self.codec)
            .format(self.file_format)
            .option("path", final_path)
        )
        if partition_by:
            for col in partition_by:
                write_df = write_df.partitionBy(col)
        write_df.saveAsTable("{}.{}".format(self.datalake_db, table_name))
        logger.info(
            "load_full_table, table={}.{},"
            "msg=Copied table into datalake ({}).".format(
                self.datalake_db, table_name, final_path
            )
        )

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
        final_path = "{}/{}".format(self.datalake_path, table_name.lower())
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
        df.write.mode("overwrite").option("compression", self.codec).format(
            self.file_format
        ).save(final_path)

        # refresh table in spark metastore
        spark.sql("MSCK REPAIR TABLE {}.{}".format(self.datalake_db, table_name))
        spark.sql("REFRESH TABLE {}.{}".format(self.datalake_db, table_name))
        logger.info(
            "load_incremental_partitioned_table, table={}.{},"
            "msg=Loaded successfully incremental data into datalake ({}).".format(
                self.datalake_db, table_name, final_path
            )
        )

    @logger
    def create_athena_external_table(
        self, consumer, table_name, athena_db, partition_by=None
    ):
        drop_query = self.DROP_TABLE_QUERY_TEMPLATE.format(
            database=athena_db, table=table_name
        )
        AthenaClient.execute_athena_query(drop_query, athena_db)
        logger.info(
            "m=create_athena_external_table, table={}.{}, msg=Dropped "
            "table in Athena successfully".format(athena_db, table_name)
        )

        table_schema = consumer.get_table_schema(table_name).collect()
        table_schema = OrderedDict(
            [
                (
                    row["col_name"],
                    row["col_type"]
                    .lower()
                    .replace("timestamp", "string")
                    .replace("binary", "varchar(53535)"),
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
        create_query = self.CREATE_TABLE_QUERY_TEMPLATE.format(
            database=athena_db,
            table=table_name,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=self.create_query_format,
            path="{}/{}".format(self.datalake_path, table_name),
        )
        AthenaClient.execute_athena_query(create_query, athena_db)
        if partition_by:
            AthenaClient.execute_athena_query(
                "MSCK REPAIR TABLE `{}`.`{}`;".format(athena_db, table_name), athena_db
            )

        logger.info(
            "m=_create_athena_external_table, table={}.{}, msg=The table was created "
            "successfully in Athena".format(athena_db, table_name)
        )

    @property
    def datalake_db(self):
        if "datalake_db" not in self.config:
            raise AttributeError(
                "param=datalake_db, msg=Attribute is required in database loader "
                "configuration."
            )
        return self.config["datalake_db"]

    @property
    def datalake_path(self):
        if "datalake_path" not in self.config:
            raise AttributeError(
                "param=datalake_path, msg=Attribute is required in database loader "
                "configuration."
            )
        return self.config["datalake_path"]

    @property
    def codec(self):
        if "codec" not in self.config:
            raise AttributeError(
                "param=codec, msg=Attribute is required in database loader "
                "configuration."
            )
        return self.config["codec"]

    @property
    def file_format(self):
        if "format" not in self.config:
            raise AttributeError(
                "param=format, msg=Attribute is required in database loader "
                "configuration."
            )
        return self.config["format"]

    @property
    def create_query_format(self):
        if "create_query_format" not in self.config:
            raise AttributeError(
                "param=create_query_format, msg=Attribute is required in database loader "
                "configuration."
            )
        return self.config["create_query_format"]
