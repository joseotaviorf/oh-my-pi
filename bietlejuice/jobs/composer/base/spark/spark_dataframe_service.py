import re

from pyspark.sql.functions import col, year, month, dayofmonth, to_json, lit
from pyspark.sql.types import StructType, ArrayType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext

logger = QuintoAndarLogger("DataFrameService")


class SparkDataFrameService:
    """
    SparkDataFrameService is a class with the purpose of implement several useful operations over a Spark dataframe.
    The methods of this class were implemented in a way for the users to create a pipeline of operations over
    dataframes. So the methods doesn't return a new dataframe, rather they return a SparkDataFrameService object.
    To get the result df after all operations the output method is needed at the end of the pipeline. Examples of use:
    Ex1:
    result_df = SparkDataFrameService(input_df)
            .explode_json_column(json_column="user_properties", prefix="user_", format_column_names=True)
            .explode_json_column(json_column="event_properties", prefix="event_", format_column_names=True)
            .optimize_partition(records_by_partition=250000)
            .output()
    Ex2:
    result_df = SparkDataFrameService().input(input_df)
            .explode_json_column(json_column="user_properties", prefix="user_", format_column_names=True)
            .explode_json_column(json_column="event_properties", prefix="event_", format_column_names=True)
            .optimize_partition(records_by_partition=250000)
            .output()
    Ex3:
    dataframe_service = SparkDataFrameService()
    result_df = dataframe_service.input(input_df)
                .explode_json_column(json_column="user_properties", prefix="user_", format_column_names=True)
                .explode_json_column(json_column="event_properties", prefix="event_", format_column_names=True)
                .optimize_partition(records_by_partition=250000)
                .output()
    """

    def __init__(self, df=None):
        self.df = df

    def input(self, df):
        return SparkDataFrameService(df)

    def output(self):
        return self.df

    @staticmethod
    def format_column_name(column_name):
        """
        :param column_name: name of a column in your dataframe
        :return: formatted name
        """
        formatted_name = re.sub(
            r"\W", "", column_name.replace(" ", "_").replace(".", "_")
        )
        formatted_name = re.sub(r"([A-Z])", r"_\g<1>", formatted_name)
        return formatted_name.lower()

    def format_column_names(self):
        """
        This operation format all names of the columns in the dataframe
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError("m=format_column_names, msg=input df is None")
        existing_names = self.df.schema.fieldNames()
        new_names = [
            SparkDataFrameService.format_column_name(name) for name in existing_names
        ]
        for existing_name, new_name in zip(existing_names, new_names):
            self.df = self.df.withColumnRenamed(existing_name, new_name)
        return SparkDataFrameService(self.df)

    def convert_struct_type_to_json(self):
        """
        This operation cast all struct type columns in the dataframe to string/json type
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError("m=convert_struct_type_to_json, msg=input df is None")
        for field in self.df.schema.fields:
            if isinstance(field.dataType, StructType):
                logger.info(
                    "m=convert_struct_type_to_json, converting struct {} to json".format(
                        field.name
                    )
                )
                self.df = self.df.withColumn(field.name, to_json(self.df[field.name]))
        return SparkDataFrameService(self.df)

    def convert_array_type_to_json(self):
        """
        This operation cast all array type columns in the dataframe to string/json type
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError("m=convert_array_type_to_json, msg=input df is None")
        for field in self.df.schema.fields:
            if isinstance(field.dataType, ArrayType):
                logger.info(
                    "m=convert_array_type_to_json, converting array {} to json".format(
                        field.name
                    )
                )
                self.df = self.df.withColumn(field.name, to_json(self.df[field.name]))
        return SparkDataFrameService(self.df)

    def convert_struct_type_to_string(self):
        """
        This operation cast all structs type columns in the dataframe to string type
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError("m=convert_struct_type_to_string, msg=input df is None")
        for field in self.df.schema.fields:
            if isinstance(field.dataType, StructType):
                logger.info(
                    "m=convert_struct_type_to_string, converting struct {} to string".format(
                        field.name
                    )
                )
                self.df = self.df.withColumn(
                    field.name, self.df[field.name].cast("string")
                )
        return SparkDataFrameService(self.df)

    def explode_json_column(self, json_column, prefix="", format_column_names=False):
        """
        This operation gets all fields of a json column and create one new column in the dataframe for each of those
        fields. This operation will not work on struct type columns, so you can use convert_struct_type_to_json method
        first in the pipeline.
        :param json_column: name of the json column in the dataframe
        :param prefix: a prefix to use in the name of the newly created columns
        :param format_column_names: Optional operation to format all the names of the new columns that will be created
        :return: SparkDataFrameService object with the result df
        """
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
                SparkDataFrameService.format_column_name(name)
                for name in json_column_names
            ]
        json_tuple_alias = ", ".join(
            ["`{}{}`".format(prefix, x) for x in json_column_names]
        )

        self.df.registerTempTable("tmp_df")
        query = "select *, json_tuple({}, {}) as ({}) from tmp_df".format(
            json_column, json_tuple_columns, json_tuple_alias
        )
        return SparkDataFrameService(spark.sql(query).drop(json_column))

    def create_columns_from_dict(self, columns):
        """
        Given a OrderedDict with the desired column name and its corresponding value.
        This method will create the columns and fill them with the given value.
        :param columns: dict with name of the columns and its correponding values
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError("m=create_columns_from_dict, msg=input df is None")

        for column_name, column_value in columns.items():
            self.df = self.df.withColumn(column_name, lit(column_value))

        return SparkDataFrameService(self.df)

    def create_year_month_day_columns_from_dataframe_column(self, date_column_name):
        """
        Given a name of date type column in the dataframe this operation will create three new columns:
        year, month, day extracted from the given column.
        :param date_column_name: name of the column to extract the year, month and day values
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError(
                "m=create_year_month_day_columns_from_dataframe_column, msg=input df is None"
            )
        return SparkDataFrameService(
            self.df.withColumn("year", year(col(date_column_name)))
            .withColumn("month", month(col(date_column_name)))
            .withColumn("day", dayofmonth(col(date_column_name)))
        )

    def create_year_month_day_columns_from_date(self, date):
        """
        Given a datetime this operation will create three new columns:
        year, month, day extracted from the given datetime.
        :param date: the datetime to extract the year, month and day values
        :return: SparkDataFrameService object with the result df
        """
        if not self.df:
            raise ValueError(
                "m=create_year_month_day_columns_from_date, msg=input df is None"
            )
        return SparkDataFrameService(
            self.df.withColumn("year", lit(date.year))
            .withColumn("month", lit(date.month))
            .withColumn("day", lit(date.day))
        )

    def optimize_partition(self, records_by_partition):
        """
        Given a value of records_by_partition this operation will perform a coalesce or  a repartition in the dataframe
        to optimize the number of partitions of the dataframe based in the given number.
        :param records_by_partition: number of records to be in each dataframe partition
        :return: SparkDataFrameService object with the result df
        """
        len_data = self.df.count()
        partitions = max(-(-len_data // records_by_partition), 1)
        if partitions > self.df.rdd.getNumPartitions():
            return SparkDataFrameService(self.df.repartition(partitions))
        return SparkDataFrameService(self.df.coalesce(partitions))

    def optimize_partitions_by_partition_columns(self, partition_by_list):
        """
        You can use this method if you want to have just one dataframe partition for each unique tuple from "partition
        by columns". For example, if you want to save a df as a table partitioned by year, month, day, using this
        method before saving guarantee that will be just one file in each partition on S3.
        :param partition_by_list: a python list with the name of the columns
        :return: SparkDataFrameService object with the result df
        """
        return SparkDataFrameService(self.df.repartition(*partition_by_list))
