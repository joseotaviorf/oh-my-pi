import json
import logging
import sys
from argparse import ArgumentParser

import pandas as pd
from pyspark.sql import Window
from pyspark.sql.functions import lit, count, col, when
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import (
    DatabricksConsumer,
    PostgresConsumer,
)
from bietlejuice.jobs.composer.dags.base.spark_jobs import BASE_ODS_MIGRATION_TEST_FILES
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "test_ods_migration"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()


class OdsMigrationValidation:

    DEFAULT_SAMPLE_SIZE_MONTHS = 1

    def __init__(self, tests_threshold, table_name, execution_date, migration_metadata):
        self.count_test_min_assert_threshold = tests_threshold.get(
            "count_test_min_assert", 1.0
        )
        self.content_test_max_error_threshold = tests_threshold.get(
            "content_test_max_error", 0.1
        )
        self.table_name = table_name
        self.execution_date = pd.to_datetime(execution_date)
        self.dw_schema = migration_metadata.get("dw_schema")
        self.date_column = migration_metadata.get("base_date_column")
        self.columns_mapping = migration_metadata.get("columns_mapping", [])
        self.sample_size_months = migration_metadata.get(
            "sample_size_months", self.DEFAULT_SAMPLE_SIZE_MONTHS
        )

    def validate_counts(self):
        """
          Check if the counts of the table in DW and in Janus matches.
          If table has a date column specified in the migration file so it
          will count only the data before the job execution day, due to the
          scheduling difference between the old and new DAGs.
        """
        base_query = "select count(1) from {schema}." + self.table_name
        if self.date_column:
            execution_date = self.execution_date.strftime("%Y-%m-%d %H:%M:%S")
            base_query += " where {date_column}" + f" < '{execution_date}'"

        df_janus = self._get_janus_data(base_query)
        janus_result_count = df_janus.collect()[0][0]

        df_dw = self._get_dw_data(base_query)
        dw_result_count = df_dw.collect()[0][0]

        logger.info(
            f"m=validate_counts, janus_result_count={janus_result_count}, "
            f"dw_result_count={dw_result_count}, msg=Validating counts."
        )

        min_count = min(janus_result_count, dw_result_count)
        max_count = max(janus_result_count, dw_result_count)
        assertion_percentage = min_count / max_count

        if assertion_percentage < self.count_test_min_assert_threshold:
            raise AssertionError(
                "m=validate_counts, "
                f"assertion_percentage={assertion_percentage}, "
                f"minimum_assertion_threshold={self.count_test_min_assert_threshold}, "
                "msg=The count matching percentage of table in Janus and in DW "
                "is smaller than the permitted threshold."
            )

        logger.info(
            f"m=validate_counts, assertion_percentage={assertion_percentage}, "
            f"minimum_assertion_threshold={self.count_test_min_assert_threshold}, "
            "msg=The counts matching percentage is valid."
        )

        assert True

    def validate_content(self):
        """
         Check if the content of the table in DW and in Janus matches.
         If table has a date column in specified in the migration file, so this
         column will be used to get a sample rather than testing the entire table.
        """
        base_query = "select * from {schema}." + self.table_name

        if self.date_column:
            start_date, end_date = self._calculate_date_range()
            base_query += (
                " where {date_column}" + f" between '{start_date}' and '{end_date}'"
            )

        df_janus = self._get_janus_data(base_query)
        df_dw = self._get_dw_data(base_query)

        logger.info("m=validate_content, msg=Validating contents.")
        self._assert_dfs(df_janus, df_dw)

    def _get_ods_column(self, new_col_name):
        for col_map in self.columns_mapping:
            if new_col_name == col_map.get("new_column"):
                return col_map.get("ods_column")
        return new_col_name

    def _get_janus_data(self, janus_query):
        databricks_consumer = DatabricksConsumer(
            conn_config={"db": "default"}, spark_client=SparkClient()
        )
        if self.date_column:
            janus_query = janus_query.format(
                schema="dw_janus_staging", date_column=self.date_column
            )
        else:
            janus_query = janus_query.format(schema="dw_janus_staging")

        return databricks_consumer.get_data_from_query(janus_query)

    def _get_dw_data(self, dw_query):
        redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))
        postgres_consumer = PostgresConsumer(
            conn_config=redshift_conn, spark_client=SparkClient()
        )
        if self.date_column:
            dw_query = dw_query.format(
                schema=self.dw_schema,
                date_column=self._get_ods_column(self.date_column),
            )
        else:
            dw_query = dw_query.format(schema=self.dw_schema)

        return postgres_consumer.get_data_from_query(dw_query)

    def _calculate_date_range(self):
        end_date = self.execution_date
        start_date = end_date - pd.DateOffset(months=self.sample_size_months)

        start_date = start_date.strftime("%Y-%m-%d %H:%M:%S")
        end_date = end_date.strftime("%Y-%m-%d %H:%M:%S")

        return start_date, end_date

    def _assert_dfs(self, df_janus, df_dw):
        df_dw = self._update_dw_df_columns_names(df_dw)
        df_dw = self._remove_dw_df_removed_columns(df_dw)
        df_dw = self._convert_all_df_columns_to_string(df_dw)

        df_janus = self._remove_janus_df_new_columns(df_janus)
        df_janus = self._convert_all_df_columns_to_string(df_janus)

        # remove now() columns since it will always differ
        dynamic_timestamp_columns = ["ts_load", "dt_timestamp", "load_timestamp"]
        for column in dynamic_timestamp_columns:
            if column in df_janus.columns:
                df_janus = df_janus.drop(column)
                df_dw = df_dw.drop(column)

        df_all = df_janus.unionByName(df_dw)
        window = Window.partitionBy(df_janus.columns).rowsBetween(-sys.maxsize, sys.maxsize)
        df_all = df_all.withColumn(
            "test_control",
            when((count("*").over(window) > 1), "VALID").otherwise(lit("ERROR")),
        ).dropDuplicates()

        df_errors = df_all.filter(col("test_control") == "ERROR")

        if df_all.count() == 0:
            logger.info(
                "m=assert_dfs_are_equal, "
                f"acceptable_threshold={self.content_test_max_error_threshold}, msg=The "
                "dataframes are empty."
            )
        else:
            error_percentage = df_errors.count() / df_all.count()
            if error_percentage > self.content_test_max_error_threshold:
                raise AssertionError(
                    "m=assert_dfs_are_equal "
                    f"error_percentage={error_percentage}, "
                    f"acceptable_threshold={self.content_test_max_error_threshold}, "
                    "msg=The data from table in Janus and in DW are divergent."
                )

            logger.info(
                f"m=assert_dfs_are_equal error_percentage={error_percentage}, "
                f"acceptable_threshold={self.content_test_max_error_threshold}, msg=The "
                f"contents are valid."
            )

        assert True

    def _update_dw_df_columns_names(self, df_dw):
        """
        Replace the columns names from DW with the new names mapped in the
        migration file.
        """
        for col_map in self.columns_mapping:
            new_col_name = col_map.get("new_column")
            ods_col_name = col_map.get("ods_column")
            new_type = col_map.get("new_column_type")
            # renaming column
            if self._is_column_renamed(
                ods_col_name=ods_col_name, new_col_name=new_col_name
            ):
                df_dw = df_dw.withColumn(new_col_name, col(ods_col_name))
                df_dw = df_dw.drop(ods_col_name)
            # retyping column
            if new_type:
                new_type = self._map_redshift_to_spark_data_type(new_type)
                if self._is_column_renamed(
                    ods_col_name=ods_col_name, new_col_name=new_col_name
                ):
                    df_dw = df_dw.withColumn(
                        new_col_name, col(new_col_name).cast(new_type)
                    )
                # if retyped column
                elif self._is_column_name_kept(
                    ods_col_name=ods_col_name, new_col_name=new_col_name
                ):
                    df_dw = df_dw.withColumn(
                        ods_col_name, col(ods_col_name).cast(new_type)
                    )
        return df_dw

    @staticmethod
    def _is_column_renamed(ods_col_name, new_col_name):
        return new_col_name and ods_col_name

    @staticmethod
    def _is_column_name_kept(ods_col_name, new_col_name):
        return ods_col_name and not new_col_name

    def _remove_dw_df_removed_columns(self, df):
        """
        Remove from dw data frame the columns removed in the migration process.
        """
        for col_map in self.columns_mapping:
            ods_col_name = col_map.get("ods_column")
            if (
                ods_col_name
                and not col_map.get("new_column")
                and not col_map.get("new_column_type")
            ):
                df = df.drop(ods_col_name)
        return df

    def _remove_janus_df_new_columns(self, df):
        """
        Remove from janus' data frame the columns added in the migration process.
        """
        for col_map in self.columns_mapping:
            new_col_name = col_map.get("new_column")
            if new_col_name and not col_map.get("ods_column"):
                df = df.drop(new_col_name)
        return df

    @staticmethod
    def _convert_all_df_columns_to_string(df):
        """
        In order to union data frames we must match columns names and types;
        Converts every column of a data frame to string.
        """
        for cur_column in df.columns:
            df = df.withColumn(cur_column, col(cur_column).cast("string"))
        return df

    @staticmethod
    def _map_redshift_to_spark_data_type(new_type):
        """
        Maps the conversion of data-type between Redshift (input) and Pyspark (output)
        """
        new_type = new_type.lower()
        if new_type in ("smallint", "bigint", "date", "float"):
            return new_type
        elif new_type.startswith("int"):
            return "int"
        # timestamp; timestamptz; timestamp with/out time zone
        elif new_type.startswith("timestamp"):
            return "timestamp"
        elif new_type in ("bool", "boolean"):
            return "boolean"
        elif new_type.startswith(tuple(["decimal", "double", "real", "numeric"])):
            return "double"
        elif new_type.startswith(tuple(["varchar", "char"])):
            return "string"
        else:
            raise TypeError("Unsupported Spark type: " + new_type)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("table_name")
    parser.add_argument("tests_threshold")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    logger.info(
        f"m={JOB_NAME}, env={args.env}, table_name={args.table_name},"
        f"execution_date={args.execution_date}, msg=Job execution started."
    )

    tests_threshold = json.loads(args.tests_threshold)
    test_file_path = f"{BASE_ODS_MIGRATION_TEST_FILES}{args.table_name}.yaml"
    migration_metadata = FileService.get_dict_from_yaml_file(test_file_path)
    migration_validation = OdsMigrationValidation(
        tests_threshold=tests_threshold,
        table_name=args.table_name,
        execution_date=args.execution_date,
        migration_metadata=migration_metadata,
    )

    migration_validation.validate_counts()
    migration_validation.validate_content()

    logger.info(f"m=test_ods_migration, msg=All tests passed!")
