import re
from collections import OrderedDict

from pyspark.sql.functions import col, year, month, dayofmonth, to_json
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

logger = QuintoAndarLogger("MetastoreService")

class MetastoreService:
    def __init__(self, db):
        self.db = db

    def get_table_names(self):
        sqlContext.tableNames(dbName=self.db)

    @logger(exclude="df")
    def make_schema_merging(self, table_name, file_format, path, partition_by_list, df):
        if not df:
            raise ValueError("m=make_schema_merging, msg=input df is None")
        df_aux = spark.sql("select * from {}.{} limit 0".format(self.db, table_name))
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
            self.db, table_name, columns_ddl, file_format, partitions_ddl, path
        )
        logger.info(
            "m=make_schema_merging, the schema is incompatible, new table definition: \n{}".format(
                ddl
            )
        )
        spark.sql("drop table {}.{}".format(self.db, table_name))
        spark.sql(ddl)
        spark.sql("msck repair table {}.{}".format(self.db, table_name))
