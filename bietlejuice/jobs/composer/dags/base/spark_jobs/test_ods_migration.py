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

    DEFAULT_THRESHOLD = 0.1
    DEFAULT_SAMPLE_SIZE_MONTHS = 1

    def __init__(self, table_name, execution_date, migration_metadata):
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
            base_query += f" where {self.date_column} < '{execution_date}'"

        df_janus = self._get_janus_data(base_query)
        janus_result_count = df_janus.collect()[0][0]

        df_dw = self._get_dw_data(base_query)
        dw_result_count = df_dw.collect()[0][0]

        logger.info(
            f"m=validate_counts, janus_result_count={janus_result_count}, "
            f"dw_result_count={dw_result_count}, msg=Validating counts."
        )
        assert janus_result_count == dw_result_count

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
                f" where {self.date_column} between '{start_date}' and '{end_date}'"
            )

        df_janus = self._get_janus_data(base_query)
        df_dw = self._get_dw_data(base_query)

        logger.info("m=validate_content, msg=Validating contents.")
        self._assert_dfs(df_janus, df_dw)

    def _get_janus_data(self, janus_query):
        databricks_consumer = DatabricksConsumer(
            conn_config={"db": "default"}, spark_client=SparkClient()
        )
        return databricks_consumer.get_data_from_query(
            janus_query.format(schema="dw_janus_staging")
        )

    def _get_dw_data(self, dw_query):
        redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))
        postgres_consumer = PostgresConsumer(
            conn_config=redshift_conn, spark_client=SparkClient()
        )
        return postgres_consumer.get_data_from_query(
            dw_query.format(schema=self.dw_schema)
        )

    def _calculate_date_range(self):
        end_date = self.execution_date
        start_date = end_date - pd.DateOffset(months=self.sample_size_months)

        start_date = start_date.strftime("%Y-%m-%d %H:%M:%S")
        end_date = end_date.strftime("%Y-%m-%d %H:%M:%S")

        return start_date, end_date

    def _assert_dfs(self, df_janus, df_dw):
        df_dw_with_new_names = self._update_dw_df_columns_names(df_dw)
        df_all = df_janus.unionByName(df_dw_with_new_names)

        df_janus = df_janus.drop("ts_load")
        new_columns = df_janus.columns

        window = Window.partitionBy(new_columns).rowsBetween(-sys.maxsize, sys.maxsize)
        df_all = df_all.withColumn(
            "test_control",
            when((count("*").over(window) > 1), "VALID").otherwise(lit("ERROR")),
        ).dropDuplicates()

        df_errors = df_all.filter(col("test_control") == "ERROR")

        error_percentage = df_errors.count() / df_all.count()
        if error_percentage > self.DEFAULT_THRESHOLD:
            raise AssertionError(
                "m=assert_dfs_are_equal "
                f"error_percentage={error_percentage}, "
                f"acceptable_threshold={self.DEFAULT_THRESHOLD}, "
                "msg=The data from table in Janus and in DW are divergent."
            )

        logger.info(
            f"m=assert_dfs_are_equal error_percentage={error_percentage}, "
            f"acceptable_threshold={self.DEFAULT_THRESHOLD}, msg=The "
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
            if new_col_name:
                df_dw = df_dw.withColumn(new_col_name, col(col_map["ods_column"]))
                df_dw = df_dw.drop(col_map["ods_column"])
        return df_dw


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    logger.info(
        f"m={JOB_NAME}, env={args.env}, table_name={args.table_name},"
        f"execution_date={args.execution_date}, msg=Job execution started."
    )

    test_file_path = f"{BASE_ODS_MIGRATION_TEST_FILES}{args.table_name}.yaml"
    migration_metadata = FileService.get_dict_from_yaml_file(test_file_path)
    migration_validation = OdsMigrationValidation(
        table_name=args.table_name,
        execution_date=args.execution_date,
        migration_metadata=migration_metadata,
    )

    migration_validation.validate_counts()
    migration_validation.validate_content()

    logger.info(f"m=test_ods_migration, msg=All tests passed!")
