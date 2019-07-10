import io
import zipfile
import gzip

from pyspark.sql.functions import col, year, month, dayofmonth
from pyspark.sql import session
from pyspark.sql import context
from pyspark import SparkContext

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.wrappers import AmplitudeExportApi

logger = QuintoAndarLogger('AmplitudeEventsETL')

# spark setup
sc = SparkContext.getOrCreate()
spark = session.SparkSession(sc)
sqlContext = context.HiveContext(sc)
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class AmplitudeEventsETL():
    AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
    DB_RAW = 'datalake_raw_spark'
    S3_RAW_PATH = 's3://5a-datalake-forno/raw/amplitude/'
    RAW_FORMAT = 'json'
    RECORDS_BY_PARTITION = 55000

    @staticmethod
    @logger
    def incremental_write(df, file_format, partition_by_list, db, table_name, path):
        write_df = df.write \
            .mode('overwrite') \
            .format(file_format) \
            .partitionBy(*partition_by_list)

        if table_name not in sqlContext.tableNames(dbName=db):
            logger.info('m=incremental_write, table not created, creating table...')
            write_df.option('path', path) \
                .saveAsTable(db + '.' + table_name)
        else:
            logger.info('m=incremental_write, insert overwrite on right partition')
            write_df.save(path)
            spark.sql('msck repair table {}.{}'.format(db, table_name))

        logger.info(
            'm=incremental_write, pushing files to s3 path={} partitions={}'.format(path, str(partition_by_list)))

    @staticmethod
    def get_number_of_partitions(len_data):
        return max(len_data // AmplitudeEventsETL.RECORDS_BY_PARTITION, 1)

    @staticmethod
    def create_events_dataframe(data, len_data):
        n = AmplitudeEventsETL.get_number_of_partitions(len_data)
        logger.info('m=create_events_dataframe, the dataframe will be written in {} partitions'.format(n))
        df = spark.read.json(sc.parallelize(data, n))
        df = df.withColumn('etl_year', year(col('server_upload_time'))) \
            .withColumn('etl_month', month(col('server_upload_time'))) \
            .withColumn('etl_day', dayofmonth(col('server_upload_time')))
        return df

    @staticmethod
    @logger(exclude='keys')
    def load_events_into_datalake_raw(start_date=None, end_date=None, keys=None):
        start = start_date.strftime(AmplitudeEventsETL.AMPLITUDE_API_DATE_FORMAT)
        end = end_date.strftime(AmplitudeEventsETL.AMPLITUDE_API_DATE_FORMAT)

        if start and end:
            logger.info('m=load_events_into_datalake_raw, Param Start String: start={} end={}'.format(start, end))
            for key in keys:
                logger.info('m=load_events_into_datalake_raw, App id: {}'.format(key['app']))
                a = AmplitudeExportApi(key['app_key'], key['secret_key'])
                logger.info('m=load_events_into_datalake_raw, get_files_from_extract_api')
                f = a.get_files_from_extract_api(start, end)
                with zipfile.ZipFile(f, 'r') as zip_file:
                    data = []
                    for name in zip_file.namelist():
                        with gzip.open(io.BytesIO(zip_file.read(name)), "rb") as gzip_file:
                            data.extend(gzip_file.read().decode('utf-8').splitlines())
                    len_data = len(data)
                    logger.info('m=load_events_into_datalake_raw, got {} events'.format(len_data))

                    df = AmplitudeEventsETL.create_events_dataframe(data, len_data)
                    table_name = 'amplitude_events'
                    AmplitudeEventsETL.incremental_write(df, AmplitudeEventsETL.RAW_FORMAT,
                                                         ['app', 'etl_year', 'etl_month', 'etl_day'],
                                                         AmplitudeEventsETL.DB_RAW, table_name,
                                                         AmplitudeEventsETL.S3_RAW_PATH + table_name)
