# noinspection PyUnresolvedReferences
import __init__
from __init__ import QUERIES_DIR

import json
import re

import fastparquet
import pandas as pd
import s3fs
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

from base.base_etl import BaseETL
from base.enum_db import EnumDb


class AmplitudeETL(object):
    TYPE_MAPPING = {
        'unicode': 'string',
        'int': 'double',
        'bool': 'bool'
    }

    @logger
    def __init__(self, execution_date, s3_bucket):
        self.s3_bucket = s3_bucket
        self.today = execution_date.date()
        self.today_ym = '{}-{}'.format(self.today.year, self.today.strftime('%m'))

        self.athena_client = AthenaClient(self.s3_bucket)

    @classmethod
    @logger
    def __format_query_filename(cls, filename):
        return '{}/{}.sql'.format(QUERIES_DIR, filename)

    @logger
    def get_all_columns(self):
        _logger.info('m=get_all_columns, msg=adding partition \'dt={}\''.format(self.today))
        add_partition_raw_query = self.__format_query_filename('add_partition_raw')
        self.athena_client.execute_file_query_and_wait_for_results(add_partition_raw_query, self.today, self.s3_bucket)

        raw_query = self.__format_query_filename('init_events_raw')
        df_columns_raw = self.athena_client.execute_file_query_and_return_dataframe(raw_query, self.today)

        _logger.info('m=get_all_columns, msg=dropping partition \'dt={}\''.format(self.today))
        drop_partition_raw_query = self.__format_query_filename('drop_partition_raw')
        self.athena_client.execute_file_query_and_wait_for_results(drop_partition_raw_query, self.today, self.s3_bucket)

        return df_columns_raw

    def insert_new_columns(self, df, df_props, df_json, properties, prefix):
        _logger.info('m=insert_new_columns, properties={}, prefix={}'.format(properties, prefix))

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
                    type_mapping = AmplitudeETL.TYPE_MAPPING[str_type]
                except KeyError:
                    _logger.warn('m=insert_new_columns, str_type={}, msg=type not mapped'.format(str_type))
                    type_mapping = 'string'

                add_column_clean_query = self.__format_query_filename('add_column_clean')
                self.athena_client.execute_file_query_and_wait_for_results(add_column_clean_query, prefix, formatted_up,
                                                                           'string', up)

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

    def create_parquets(self, df):
        s3 = s3fs.S3FileSystem()

        ets = df.groupby('event_type')
        for df_et in ets:
            key = '{0}/clean/amplitude/events/et={1}/ym={2}/{3}_{4}.parq'.format(self.s3_bucket, df_et[0],
                                                                                 self.today_ym, self.today, 'events')

            _logger.info('m=create_parquets, et={}, ym={}, filename={}_{}.parq'.format(df_et[0], self.today_ym,
                                                                                       self.today, 'events'))
            filtered_df = df[df['event_type'] == df_et[0]]
            filtered_df = filtered_df.fillna('').astype(str)
            fastparquet.write(key, filtered_df, open_with=s3.open)

            _logger.info('m=create_parquets, msg=adding partition \'et={}\';\'ym={}\''.format(df_et[0], self.today_ym))
            add_partition_clean_query = self.__format_query_filename('add_partition_clean')
            self.athena_client.execute_file_query(add_partition_clean_query, df_et[0], self.today_ym, self.s3_bucket)

    def get_properties_as_df(self):
        props_query = """describe datalake_clean.amplitude_events"""
        return self.athena_client.execute_txt_query_and_return_dataframe(props_query)

    @classmethod
    def __convert_columns_to_number(cls, df, columns, _type):
        for col in columns:
            df[col].fillna(0).astype(_type)

        return df

    @classmethod
    def __convert_columns_to_text(cls, df, column_prefixes, _type):
        for col_prefix in column_prefixes:
            cols = set(df.columns[pd.Series(df.columns).str.startswith(col_prefix)])
            for col in cols:
                df[col] = df[col].fillna('').astype(str)

        return df

    @classmethod
    def __convert_columns_to_datetime(cls, df, columns):
        for col in columns:
            df[col] = pd.to_datetime(df[col])

        return df

    @logger
    def merge_user_ids(self):
        BaseETL.execute_command(
            command="""drop table if exists amplitude_events.tmp_merge_users_result""",
            db_enum=EnumDb.BI_DW,
            commit=True
        )

        BaseETL.execute_command(
            command="""
                    create table amplitude_events.tmp_merge_users_result as (
                        with amplitude_events_not_empty as (
                          select
                            case when device_id is null or device_id = '' then null else device_id end as device_id,
                            case when amplitude_id is null or amplitude_id = '' then null else amplitude_id end as amplitude_id,
                            case when user_id is null or user_id = '' then null else user_id end as user_id
                            from datalake_clean.amplitude_events
                          where ym = '{}'
                        ),
                        user_nulls as (
                          select device_id, amplitude_id, user_id
                            from amplitude_events_not_empty
                          where user_id is null
                        ),
                        user_not_nulls as (
                          select device_id, amplitude_id, user_id
                            from amplitude_events_not_empty
                          where user_id is not null
                        ),
                        result_out_merge as (
                          select
                            coalesce(n.device_id, nn.device_id) as device_id,
                            coalesce(n.amplitude_id, nn.amplitude_id) as amplitude_id,
                            case
                              when n.device_id is not null
                                    and nn.device_id is not null
                                    and n.amplitude_id is not null
                                    and nn.amplitude_id is not null
                                then nn.user_id
                              else coalesce(nn.user_id, n.user_id)
                            end as user_id
                            from user_nulls n
                          full outer join user_not_nulls nn
                            on n.device_id = nn.device_id
                             and n.amplitude_id = nn.amplitude_id
                        )
                        select distinct rom.device_id, rom.amplitude_id, rom.user_id
                          from amplitude_events.merged_users mu
                        right join result_out_merge rom
                          on mu.device_id = rom.device_id
                             and mu.amplitude_id = rom.amplitude_id::varchar
                             and mu.user_id = rom.user_id
                        where mu.device_id is null
                              and mu.amplitude_id is null
                              and mu.user_id is null
                        )
                    """.format(self.today_ym),
            db_enum=EnumDb.BI_DW,
            commit=True
        )

        BaseETL.execute_command(
            command="""insert into amplitude_events.merged_users
                        select distinct
                          coalesce(mu.device_id, tmur.device_id) as device_id,
                          coalesce(mu.amplitude_id, tmur.amplitude_id::varchar) as amplitude_id,
                          case
                            when mu.device_id is not null
                                  and tmur.device_id is not null
                                  and mu.amplitude_id is not null
                                  and tmur.amplitude_id is not null
                              then tmur.user_id
                            else coalesce(mu.user_id, tmur.user_id)
                          end as user_id
                        from amplitude_events.merged_users mu
                        full outer join amplitude_events.tmp_merge_users_result tmur
                          on mu.device_id = tmur.device_id
                            and mu.amplitude_id = tmur.amplitude_id
                        where mu.device_id is null
                              and mu.amplitude_id is null
                              and mu.user_id is null
                    """,
            db_enum=EnumDb.BI_DW,
            commit=True
        )

        BaseETL.execute_command(
            command="""drop table if exists amplitude_events.tmp_merge_users_result""",
            db_enum=EnumDb.BI_DW,
            commit=True
        )
