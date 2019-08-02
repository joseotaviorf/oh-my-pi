import io
import zipfile
import gzip
import os
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.wrappers import AmplitudeExportApi, AthenaClient
from bietlejuice.jobs.composer.base.spark import BaseSparkContext, DataFrameService

logger = QuintoAndarLogger('AmplitudeEvents')

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class AmplitudeEvents():
    AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
    RAW_FORMAT = 'json'
    RAW_RECORDS_BY_PARTITION = 55000
    CLEAN_FORMAT = 'parquet'
    CLEAN_RECORDS_BY_PARTITION = 250000

    DROP_QUERY_TEMPLATE = "DROP TABLE IF EXISTS `{database}`.`{table}`;"
    CREATE_QUERY_TEMPLATE = """CREATE EXTERNAL TABLE IF NOT EXISTS
                            `{database}`.`{table}`
                            (
                              {columns}
                            )
                            {partitioned_by}
                            {format}
                            LOCATION '{path}'
                            tblproperties ("parquet.compress"="SNAPPY");"""
    CREATE_QUERY_CLEAN_FORMAT = "STORED AS PARQUET"

    def __init__(self, db_raw=None, s3_raw_path=None, db_clean=None, s3_clean_path=None, keys=None):
        self.db_raw = db_raw
        self.s3_raw_path = s3_raw_path
        self.keys = keys

        self.db_clean = db_clean
        self.s3_clean_path = s3_clean_path

    @staticmethod
    def get_number_of_partitions(len_data, stage):
        if stage == 'raw':
            return max(len_data // AmplitudeEvents.RAW_RECORDS_BY_PARTITION, 1)
        elif stage == 'clean':
            return max(len_data // AmplitudeEvents.CLEAN_RECORDS_BY_PARTITION, 1)

    def create_events_dataframe(self, data, len_data):
        n = self.get_number_of_partitions(len_data, 'raw')
        logger.info('m=create_events_dataframe, the dataframe will be written in {} partitions'.format(n))
        df = spark.read.json(sc.parallelize(data, n))
        df = DataFrameService.df_columns_name_format(df)
        df = DataFrameService.df_struct_type_to_json(df)
        df = DataFrameService.df_create_year_month_day_columns(df, 'server_upload_time')
        return df

    @staticmethod
    def get_data_from_zip_file(zip_file):  # Todo: move method to external client
        data = []
        for name in zip_file.namelist():
            with gzip.open(io.BytesIO(zip_file.read(name)), "rb") as gzip_file:
                data.extend(gzip_file.read().decode('utf-8').splitlines())
        return data

    @logger(exclude='keys')
    def load_events_into_datalake_raw(self, start_date=None, end_date=None):
        start = start_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)
        end = end_date.strftime(AmplitudeEvents.AMPLITUDE_API_DATE_FORMAT)

        if not start and not end:
            logger.warning('m=load_events_into_datalake_raw, start_date and end_date are none, nothing to do')
            return

        logger.info('m=load_events_into_datalake_raw, Param Start String: start={} end={}'.format(start, end))
        for key in self.keys:
            logger.info('m=load_events_into_datalake_raw, App id: {}, App name: {}'
                        .format(key['app_id'], key['app_name']))

            a = AmplitudeExportApi(key['app_key'], key['secret_key'])
            logger.info('m=load_events_into_datalake_raw, get_files_from_extract_api')
            f = a.get_files_from_extract_api(start, end)
            if not f:
                logger.warning("m=load_events_into_datalake_raw, msg=None response from get_files_from_extract_api")
            else:
                with zipfile.ZipFile(f, 'r') as zip_file:
                    data = self.get_data_from_zip_file(zip_file)
                    len_data = len(data)
                    logger.info('m=load_events_into_datalake_raw, got {} events'.format(len_data))

                    df = self.create_events_dataframe(data, len_data)
                    table_name = 'amplitude_events'
                    DataFrameService.incremental_write(df,
                                                       AmplitudeEvents.RAW_FORMAT,
                                                       ['year', 'month', 'day', 'app'],
                                                       self.db_raw, table_name,
                                                       self.s3_raw_path + table_name,
                                                       True)

    @logger
    def update_clean_amplitude_events(self, date):
        year, month, day = date.year, date.month, date.day
        logger.info('m=create_clean_amplitude_events, year={}, month={}, day={}'
                    .format(year, month, day))

        with open(os.path.join(os.path.dirname(os.path.realpath(__file__)),
                               "../../../../db/composer/amplitude/clean_amplitude_events.sql")) as f:
            query = f.read()

        table_name = "amplitude_events"
        df = spark.sql(query.format(self.db_raw, table_name, year, month, day))

        len_df = df.count()
        partitions = self.get_number_of_partitions(len_df, 'clean')
        df = df.coalesce(partitions)

        DataFrameService.incremental_write(df,
                                           AmplitudeEvents.CLEAN_FORMAT,
                                           ['year', 'month', 'day', 'event_type'],
                                           self.db_clean, table_name,
                                           self.s3_clean_path + table_name)

    @logger
    def update_filtered_events_table(self, date, event_type):
        table_name = 'amplitude_events'
        year, month, day = date.year, date.month, date.day
        filtered_event_df = spark.sql("select * from {}.{} where year={} and month={} and day={} and event_type = '{}'"
                                      .format(self.db_clean, table_name, year, month, day, event_type))

        filtered_event_exploded_df = DataFrameService.explode_json_column(filtered_event_df,
                                                                          'user_properties',
                                                                          'user_', True)
        filtered_event_exploded_df = DataFrameService.explode_json_column(filtered_event_exploded_df,
                                                                          'event_properties',
                                                                          'event_', True)

        len_df = filtered_event_exploded_df.count()
        partitions = self.get_number_of_partitions(len_df, 'clean')
        filtered_event_exploded_df = filtered_event_exploded_df.coalesce(partitions)

        table_name = 'amplitude_{}_events'.format(event_type)
        DataFrameService.incremental_write(filtered_event_exploded_df,
                                           AmplitudeEvents.CLEAN_FORMAT,
                                           ['year', 'month', 'day'],
                                           self.db_clean, table_name,
                                           self.s3_clean_path + table_name,
                                           True)

    @logger
    def create_athena_external_table(self, consumer, table, partition_by=None):
        file_format = AmplitudeEvents.CREATE_QUERY_CLEAN_FORMAT

        drop_query = AmplitudeEvents.DROP_QUERY_TEMPLATE.format(
            database=self.db_clean,
            table=table)
        AthenaClient.execute_athena_query(drop_query, self.db_clean)
        logger.info('m=create_athena_external_table, table={}.{}, msg=Dropped table in Athena successfully'.format(
            self.db_clean,
            table))

        table_schema = consumer.get_table_schema(table).collect()
        table_schema = OrderedDict(
            [(row['col_name'], row['col_type'].lower().replace('timestamp', 'string')) for row in table_schema])

        columns_section = ',\n  '.join(
            ['`' + col + '` ' + col_type.upper() for col, col_type in table_schema.items() if
             not partition_by or col not in partition_by])
        partitions_section = ''
        if partition_by:
            partitions_section = 'PARTITIONED BY (\n  {}\n)'.format(
                ',\n  '.join(['`' + col + '` ' + table_schema[col] for col in partition_by]))
        create_query = AmplitudeEvents.CREATE_QUERY_TEMPLATE.format(
            database=self.db_clean,
            table=table,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=file_format,
            path='{}{}'.format(
                self.s3_clean_path,
                table
            )
        )
        AthenaClient.execute_athena_query(create_query, self.db_clean)
        if partition_by:
            AthenaClient.execute_athena_query(
                'MSCK REPAIR TABLE `{}`.`{}`;'.format(self.db_clean, table), self.db_clean)

        logger.info(
            'm=_create_athena_external_table, table={}.{}, msg=The table was created successfully in Athena'.format(
                self.db_clean, table))
