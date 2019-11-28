import gzip
import io
import os
import zipfile

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("AmplitudeEvents")


class AmplitudeEvents:
    """
    This class is deprecated and must be removed the sooner the better. The idea is
    to not have specific ETL classes for our migrated/new jobs but to define the
    tasks using the spark scripts together with the repo common entities (clients,
    consumers, loaders, etc.)
    """

    AMPLITUDE_API_DATE_FORMAT = "%Y%m%dT%H"
    RAW_FORMAT = "json"
    RAW_RECORDS_BY_PARTITION = 45000
    CLEAN_FORMAT = "parquet"
    CLEAN_RECORDS_BY_PARTITION = 250000

    def __init__(
        self,
        spark_client,
        db_raw=None,
        s3_raw_path=None,
        db_clean=None,
        s3_clean_path=None,
        keys=None,
    ):
        self.spark_client = spark_client
        self.db_raw = db_raw
        self.s3_raw_path = s3_raw_path
        self.keys = keys

        self.db_clean = db_clean
        self.s3_clean_path = s3_clean_path

    @staticmethod
    def _get_data_from_zip_file(zip_file):  # Todo: move method to external client
        data = []
        for name in zip_file.namelist():
            with gzip.open(io.BytesIO(zip_file.read(name)), "rb") as gzip_file:
                data.extend(gzip_file.read().decode("utf-8").splitlines())
        return data

    @logger(exclude="keys")
    def create_raw_events_df(self, file_from_api, dataframe_service):
        if not file_from_api:
            logger.warning("m=create_raw_events_df, msg=Empty file to load in datalake")
            return
        with zipfile.ZipFile(file_from_api, "r") as zip_file:
            data = self._get_data_from_zip_file(zip_file)
        len_data = len(data)
        logger.info("m=create_raw_events_df, got {} events".format(len_data))
        n = max(len_data // AmplitudeEvents.RAW_RECORDS_BY_PARTITION, 1)
        logger.info(
            "m=create_raw_events_df, the dataframe will be written in {} "
            "partitions".format(n)
        )

        # todo: this piece of code must be improved. Right now, we are using spark
        #  code directly in this class. We got the error `Some of types cannot be
        #  determined after inferring` while using the method
        #  spark_client.create_dataframe because the rows contain nested dicts. A
        #  solution here is to declare the schema of the DataFrame statically.
        json_rdd = self.spark_client.conn.sparkContext.parallelize(data, n)
        df = self.spark_client.conn.read.json(json_rdd)

        return (
            dataframe_service.input(df)
            .format_column_names()
            .convert_struct_type_to_json()
            .create_year_month_day_columns_from_dataframe_column("server_upload_time")
            .output()
        )

    @logger
    def create_clean_events_df(
        self, date, spark_sql_consumer, dataframe_service, partition_by_list
    ):
        year, month, day = date.year, date.month, date.day
        logger.info(
            "m=create_clean_events_df, year={}, month={}, day={}".format(
                year, month, day
            )
        )

        with open(
            os.path.join(
                os.path.dirname(os.path.realpath(__file__)),
                "../../db/datalake/queries/amplitude/clean_events.sql",
            )
        ) as f:
            query = f.read()

        table_name = "events"
        df = spark_sql_consumer.get_data_from_query(
            query.format(self.db_raw, table_name, year, month, day)
        )

        return (
            dataframe_service.input(df)
            .optimize_partitions_by_partition_columns(partition_by_list)
            .output()
        )

    @logger
    def create_filtered_clean_events_df(
        self, date, event_type, spark_sql_consumer, dataframe_service
    ):
        table_name = "events"
        year, month, day = date.year, date.month, date.day
        logger.info(
            "m=create_filtered_clean_events_df, year={}, month={}, day={}, "
            "event_type={}".format(year, month, day, event_type)
        )

        filtered_event_df = spark_sql_consumer.get_data_from_query(
            "select * from {}.{} where year={} and month={} and day={} and event_type "
            "= '{}'".format(self.db_clean, table_name, year, month, day, event_type)
        )

        return (
            dataframe_service.input(filtered_event_df)
            .explode_json_column("user_properties", "user_", True)
            .explode_json_column("event_properties", "event_", True)
            .optimize_partition(AmplitudeEvents.CLEAN_RECORDS_BY_PARTITION)
            .output()
        )
