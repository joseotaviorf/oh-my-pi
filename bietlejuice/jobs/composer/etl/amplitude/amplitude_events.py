import io
import zipfile
import gzip

from pyspark.sql.functions import col, year, month, dayofmonth

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.wrappers import AmplitudeExportApi
from bietlejuice.jobs.composer.base import BaseSparkContext
from bietlejuice.jobs.composer.base import DataFrameService

logger = QuintoAndarLogger('AmplitudeEvents')

spark, sc = BaseSparkContext.spark, BaseSparkContext.sc
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class AmplitudeEvents():
    AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
    RAW_FORMAT = 'json'
    RECORDS_BY_PARTITION = 55000

    def __init__(self, db_raw, s3_raw_path, keys):
        self.db_raw = db_raw
        self.s3_raw_path = s3_raw_path
        self.keys = keys

    def get_number_of_partitions(self, len_data):
        return max(len_data // AmplitudeEvents.RECORDS_BY_PARTITION, 1)

    def create_events_dataframe(self, data, len_data):
        n = self.get_number_of_partitions(len_data)
        logger.info('m=create_events_dataframe, the dataframe will be written in {} partitions'.format(n))
        df = spark.read.json(sc.parallelize(data, n))
        df = df.withColumn('year', year(col('server_upload_time'))) \
            .withColumn('month', month(col('server_upload_time'))) \
            .withColumn('day', dayofmonth(col('server_upload_time')))
        return df

    def get_data_from_zip_file(self, zip_file):
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
            if f:  # check if got response from the API
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
                                                       self.s3_raw_path + table_name)
