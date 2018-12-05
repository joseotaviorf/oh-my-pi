import io
import json
import re
import zipfile
from datetime import datetime

import boto3
import numpy as np
import pandas as pd
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.new_etl import DW_QUERIES_DIR, DATALAKE_QUERIES_DIR
from bietlejuice.jobs.wrappers.amplitude import amplitude_props_reader as props
from bietlejuice.jobs.wrappers.amplitude.amplitude_export_api import AmplitudeExportApi
from pandas import errors
from pandas.io.json import json_normalize
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('AmplitudeEventsETL')

DEFAULT_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S'
AMPLITUDE_API_DATE_FORMAT = '%Y%m%dT%H'
LOCAL_TZ = 'America/Sao_Paulo'


class AmplitudeEventsETL(BaseETL):
    TYPE_MAPPING = {
        'unicode': 'string',
        'int': 'double',
        'bool': 'bool'
    }

    @logger
    def __init__(self, s3_bucket, *args, **kwargs):
        super(AmplitudeEventsETL, self).__init__(*args, **kwargs)
        self.s3 = boto3.resource('s3')
        self.s3_bucket = s3_bucket

    def dump_events_to_s3(self, f, app, start, hour, extra):
        if isinstance(start, str):
            start = datetime.strptime(start, DEFAULT_DATETIME_FORMAT)
        if isinstance(start, datetime):
            start = start.date()

        date_partition = 'dt={}'.format(str(start))
        file_name = 'raw/amplitude/events/{}/{}_{}_{}_{}.json.gz'.format(date_partition, app, str(start), hour, extra)
        logger.info('m=dump_events_to_s3, pushing file to s3 bucket={} filename={}'.format('5a-datalake', file_name))
        self.s3.Bucket('5a-datalake').put_object(Body=f.getvalue(), Key=file_name)

    @logger
    def extract_from_api_to_s3(self, start_date=None, end_date=None):
        start = start_date.strftime(AMPLITUDE_API_DATE_FORMAT)
        end = end_date.strftime(AMPLITUDE_API_DATE_FORMAT)

        if start and end:
            logger.info('m=extract_from_api_to_s3, Param Start String: start={} end={}'.format(start, end))
            keys = props.get_keys()
            for key in keys:
                logger.info('m=extract_from_api_to_s3, processing {}'.format(key['app']))
                a = AmplitudeExportApi(key['app_key'], key['secret_key'])
                logger.info('dt={} m=extract_from_api_to_s3, get_files_from_extract_api'.format(datetime.now()))
                f = a.get_files_from_extract_api(start, end)
                if f:
                    with zipfile.ZipFile(f, 'r') as zfile:
                        for name in zfile.namelist():
                            hourly_gz = io.BytesIO(zfile.read(name))
                            hour = name.split('#')[0].split('_')[-1]  # extract the hour from the file name
                            extra = name.split('#')[1].split('.')[0]  # putting the extra on the name for deduplication
                            self.dump_events_to_s3(hourly_gz, key['app'], start_date, hour, extra)
                            logger.info('dt={} m=extract_from_api_to_s3, object sent name={} app={} hour={} extra={}'.
                                        format(datetime.now(), name, key['app'], hour, extra))

    @logger
    def merge_user_ids(self, ym):
        schema = 'amplitude_events'
        table_mu = 'merged_users'
        table_tmp = 'tmp_merge_users_result'

        BaseETL.drop_table(db_enum=EnumDB.BI_DW, table_name=table_tmp, schema=schema)

        logger.info("m=merge_user_ids, table={}, msg=creating table".format(table_tmp))
        query_create = BaseETL.get_query_from_file_name(
            '{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, table_tmp))

        BaseETL.execute_command(
            command=query_create.format(ym),
            db_enum=EnumDB.BI_DW,
            commit=True
        )

        logger.info("m=merge_user_ids, msg=querying DW")
        query_select = BaseETL.get_query_from_file_name('{}/{}/{}.sql'.format(DW_QUERIES_DIR, schema, table_mu))

        table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query_select
        )

        table = BaseETL.decode_table(table, 'LATIN-1')

        logger.info("m=merge_user_ids, table={}, msg=sending to DW".format(table_mu))
        BaseETL.bulk_insert(
            table=table,
            table_name='{}.{}'.format(schema, table_mu),
            db_enum=EnumDB.BI_DW,
            encoding='UTF8',
            append=True,
            commit=True,
            bucket_name='{}/clean/amplitude_events/{}'.format(self.s3_bucket, table_mu)
        )

        BaseETL.drop_table(db_enum=EnumDB.BI_DW, table_name=table_tmp, schema=schema)

    @logger
    def load_data_to_clean(self, execution_date):
        athena_client = AthenaClient(self.s3_bucket)
        chunks = 20

        df_raw = self.get_all_columns(athena_client, execution_date)
        df_final = pd.DataFrame()
        i = 1

        if len(df_raw) <= 0:
            raise errors.EmptyDataError('m=load_data_to_clean, msg=empty dataframe')
        else:
            logger.info('m=load_data_to_clean, chunks={}, msg=Starting to normalize df'.format(
                str(round(len(df_raw) / chunks))))
            for chunk in np.array_split(df_raw, chunks):
                logger.info('m=load_data_to_clean, chunk={}, msg=Starting new batch'.format(str(i)))

                df_raw_json = json_normalize(chunk.event_data.apply(json.loads))

                df_raw_json['dt'] = chunk['dt']

                df_properties = self.get_properties_as_df(athena_client=athena_client)
                df_raw_json = self.expand_columns(
                    athena_client=athena_client,
                    df=chunk,
                    df_props=df_properties,
                    df_json=df_raw_json,
                    properties='user_properties',
                    prefix='u_'
                )
                df_raw_json = self.expand_columns(
                    athena_client=athena_client,
                    df=chunk,
                    df_props=df_properties,
                    df_json=df_raw_json,
                    properties='event_properties',
                    prefix='e_'
                )

                df_final = df_final.append(df_raw_json)
                i += 1

            self.create_parquets(athena_client=athena_client, execution_date=execution_date, df=df_final)

    @logger
    def get_all_columns(self, athena_client, execution_date):
        today = str(execution_date.strftime('%Y-%m-%d'))

        logger.info("m=get_all_columns, msg=adding partition 'dt={}'".format(today))
        add_partition_raw_query = self.__format_query_filename('add_partition_raw')
        athena_client.execute_file_query_and_wait_for_results(
            filename=add_partition_raw_query,
            query_params={
                'dt_partition': today,
                's3_bucket': self.s3_bucket
            }
        )

        raw_query = self.__format_query_filename('init_events_raw')
        df_columns_raw = athena_client.execute_file_query_and_return_dataframe(
            filename=raw_query,
            query_params={'dt_partition': today})

        logger.info("m=get_all_columns, msg=dropping partition 'dt={}'".format(today))
        drop_partition_raw_query = self.__format_query_filename('drop_partition_raw')
        athena_client.execute_file_query_and_wait_for_results(
            filename=drop_partition_raw_query,
            query_params={'dt_partition': today})

        return df_columns_raw

    @classmethod
    @logger
    def __format_query_filename(cls, filename):
        return '{}/amplitude/{}.sql'.format(DATALAKE_QUERIES_DIR, filename)

    @logger
    def get_properties_as_df(self, athena_client):
        props_query = 'describe datalake_clean.amplitude_events'
        return athena_client.execute_txt_query_and_return_dataframe(props_query)

    def expand_columns(self, athena_client, df, df_props, df_json, properties, prefix):
        logger.info('m=expand_columns, properties={}, prefix={}'.format(properties, prefix))

        props_list = list(
            df_props[df_props[0].str.contains(prefix).fillna(False)][2].apply(lambda x: x.strip()))
        already_added_list = []
        already_prop_added_list = []

        for index, row in df.iterrows():
            event_json = json.loads(row['event_data'])

            up_diff = list(set(event_json[properties]) - set(props_list))
            for up in up_diff:
                if up in already_added_list:
                    continue

                str_type, formatted_up = self.__format_properties(
                    property_name=up,
                    property_value=event_json[properties][up]
                )

                try:
                    type_mapping = self.TYPE_MAPPING[str_type]
                except KeyError:
                    logger.warn('m=expand_columns, str_type={}, msg=type not mapped'.format(str_type))
                    type_mapping = 'string'

                add_column_clean_query = self.__format_query_filename('add_column_clean')
                athena_client.execute_file_query_and_wait_for_results(
                    filename=add_column_clean_query,
                    query_params={
                        'column_prefix': prefix,
                        'column_formatted': formatted_up,
                        'column_type': 'string',
                        'original_column': up
                    }
                )

                already_added_list.append(up)

            for prop in event_json[properties]:
                if prop in already_prop_added_list:
                    continue

                _, formatted_prop = self.__format_properties(
                    property_name=prop,
                    property_value=event_json[properties][prop]
                )

                df_json.rename(columns={'{0}.{1}'.format(properties, prop): '{0}{1}'.format(prefix, formatted_prop)},
                               inplace=True)

                already_prop_added_list.append(prop)

        return df_json

    @classmethod
    def __format_properties(cls, property_name, property_value):
        str_type = re.search('<type \'([a-z]+)\'>', str(type(property_value))).groups()[0]
        formatted_prop = re.sub('\W', '', property_name.replace(' ', '_').replace('.', '_'))
        formatted_prop = re.sub('^([A-Z])', '_\g<1>', formatted_prop)
        formatted_prop = re.sub('(.)_([A-Z])', '\g<1>__\g<2>', formatted_prop)

        return str_type, formatted_prop.lower()

    @logger(exclude='df')
    def create_parquets(self, athena_client, execution_date, df):
        today = str(execution_date.strftime('%Y-%m-%d'))
        ym = str(execution_date.strftime('%Y-%m'))

        ets = df.groupby('event_type')
        for df_et in ets:
            key = 'clean/amplitude/events/et={0}/ym={1}/{2}_{3}.parq'.format(df_et[0],
                                                                             ym, today, 'events')

            logger.info('m=create_parquets, et={}, ym={}, filename={}_{}.parq'.format(df_et[0], ym,
                                                                                      today, 'events'))
            filtered_df = df[df['event_type'] == df_et[0]]
            filtered_df = filtered_df.fillna('').astype(str)
            athena_client.create_parquet_from_df(key=key, df=filtered_df)

            logger.info('m=create_parquets, et={}, ym={}, msg=adding partition'.format(df_et[0], ym))
            add_partition_clean_query = self.__format_query_filename('add_partition_clean')
            athena_client.execute_file_query(
                filename=add_partition_clean_query,
                query_params={
                    'et': df_et[0],
                    'ym': ym,
                    's3_bucket': self.s3_bucket
                }
            )


def convert_date(date_str):
    return datetime.strptime(date_str, DEFAULT_DATETIME_FORMAT)
