import re

from pyspark.sql.functions import col, year, month, dayofmonth, to_json
from pyspark.sql.types import StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

logger = QuintoAndarLogger("DataFrameService")


class SparkDataFrameService:
    def __init__(self, df=None):
        self.df = df

    def input(self, df):
        return SparkDataFrameService(df)

    def output(self):
        return self.df

    @staticmethod
    def column_name_format(column_name):
        formatted_name = re.sub(
            r"\W", "", column_name.replace(" ", "_").replace(".", "_")
        )
        formatted_name = re.sub(r"^([A-Z])", r"_\g<1>", formatted_name)
        formatted_name = re.sub(r"(.)_([A-Z])", r"\g<1>__\g<2>", formatted_name)
        return formatted_name.lower()

    def columns_name_format(self):
        if not self.df:
            raise ValueError("m=columns_name_format, msg=input df is None")
        existing_names = self.df.schema.fieldNames()
        new_names = [
            SparkDataFrameService.column_name_format(name) for name in existing_names
        ]
        for existing_name, new_name in zip(existing_names, new_names):
            self.df = self.df.withColumnRenamed(existing_name, new_name)
        return SparkDataFrameService(self.df)

    def struct_type_to_json(self):
        if not self.df:
            raise ValueError("m=struct_type_to_json, msg=input df is None")
        for field in self.df.schema.fields:
            if isinstance(field.dataType, StructType):
                logger.info(
                    "m=struct_type_to_json, converting struct {} to json".format(
                        field.name
                    )
                )
                self.df = self.df.withColumn(field.name, to_json(self.df[field.name]))
        return SparkDataFrameService(self.df)

    def explode_json_column(self, json_column, prefix="", format_column_names=False):
        if not self.df:
            raise ValueError("m=explode_json_column, msg=input df is None")
        if json_column not in self.df.schema.fieldNames():
            raise ValueError(
                "m=explode_json_column, msg=input json_column does not exists"
            )

        df_json_column = sqlContext.read.json(
            self.df.rdd.map(lambda r: getattr(r, json_column))
        )
        json_column_names = df_json_column.schema.fieldNames()
        if not json_column_names:
            logger.warning("m=explode_json_column, msg=json_column is empty")
            return SparkDataFrameService(self.df.drop(json_column))

        logger.info(
            "m=explode_json_column, msg=creating {} columns".format(
                len(json_column_names)
            )
        )
        json_tuple_columns = ", ".join(["'{}'".format(x) for x in json_column_names])
        if format_column_names:
            json_column_names = [
                SparkDataFrameService.column_name_format(name) for name in json_column_names
            ]
        json_tuple_alias = ", ".join(
            ["`{}{}`".format(prefix, x) for x in json_column_names]
        )

        self.df.registerTempTable("tmp_df")
        query = "select *, json_tuple({}, {}) as ({}) from tmp_df".format(
            json_column, json_tuple_columns, json_tuple_alias
        )
        return SparkDataFrameService(spark.sql(query).drop(json_column))

    def create_year_month_day_columns(self, date_column_name):
        if not self.df:
            raise ValueError("m=create_year_month_day_columns, msg=input df is None")
        return SparkDataFrameService(
            self.df.withColumn("year", year(col(date_column_name)))
            .withColumn("month", month(col(date_column_name)))
            .withColumn("day", dayofmonth(col(date_column_name)))
        )

    def partition_optimize(self, records_by_partition):
        len_data = self.df.count()
        partitions = max(len_data // records_by_partition, 1)
        if partitions > self.df.rdd.getNumPartitions():
            return SparkDataFrameService(self.df.repartition(partitions))
        return SparkDataFrameService(self.df.coalesce(partitions))
