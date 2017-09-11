import json
import os
import re
import sys
from datetime import datetime

import fastparquet
import pandas as pd
import s3fs
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

args = sys.argv

today = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S').date()
today_ym = '{}-{}'.format(today.year, today.strftime('%m'))

bucket_datalake = os.environ['bi-datalake-s3-bucket']

TYPE_MAPPING = {
    'unicode': 'string',
    'int': 'double',
    'bool': 'bool'
}


class AmplitudeETL(object):
    @logger
    def __init__(self):
        self.athena_client = AthenaClient(bucket_datalake)

    @logger
    def get_all_columns(self):
        _logger.info('m=get_all_columns, msg=adding partition \'dt={}\''.format(today))
        add_partition_raw_query = './db/2.datalake/queries/amplitude/add_partition_raw.sql'
        self.athena_client.execute_file_query(add_partition_raw_query, today, bucket_datalake)

        raw_query = '.db/2.datalake/queries/amplitude/init_events_raw.sql'
        df_columns_raw = self.athena_client.execute_file_query_and_return_dataframe(raw_query, today)

        _logger.info('m=get_all_columns, msg=dropping partition \'dt={}\''.format(today))
        drop_partition_raw_query = './db/2.datalake/queries/amplitude/drop_partition_raw.sql'
        self.athena_client.execute_file_query(drop_partition_raw_query, today, bucket_datalake)

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
                    type_mapping = TYPE_MAPPING[str_type]
                except KeyError:
                    _logger.warn('m=insert_new_columns, str_type={}, msg=type not mapped'.format(str_type))
                    type_mapping = 'string'

                add_column_clean_query = './db/2.datalake/queries/amplitude/add_column_clean.sql'
                self.athena_client.execute_file_query(add_column_clean_query, prefix, formatted_up, 'string', up)

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

    def __format_properties(self, property_name, property_value):
        str_type = re.search('<type \'([a-z]+)\'>', str(type(property_value))).groups()[0]
        formatted_prop = re.sub('\W', '', property_name.replace(' ', '_').replace('.', '_'))

        return str_type, '_{}'.format(formatted_prop)

    def create_parquets(self, df):
        s3 = s3fs.S3FileSystem()

        ets = df.groupby('event_type')
        for df_et in ets:
            key = '{0}/clean/amplitude/events/et={1}/ym={2}/{3}_{4}.parq'.format(bucket_datalake, df_et[0], today_ym,
                                                                                 today, 'events')

            _logger.info('m=create_parquets, et={}, ym={}, filename={}_{}.parq'.format(df_et[0], today_ym, today,
                                                                                       'events'))
            filtered_df = df[df['event_type'] == df_et[0]]
            filtered_df.astype(object).where(pd.notnull(filtered_df), None)

            filtered_df = self.__convert_columns_to_text(
                df=filtered_df,
                column_prefixes=['u_', 'e_'],
                _type=str
            )

            fastparquet.write(key, filtered_df, open_with=s3.open)

            _logger.info('m=create_parquets, msg=adding partition \'et={}\';\'ym={}\''.format(df_et[0], today_ym))
            add_partition_clean_query = './db/2.datalake/queries/amplitude/add_partition_clean.sql'
            self.athena_client.execute_file_query(add_partition_clean_query, df_et[0], today_ym, bucket_datalake)

    def get_properties_as_df(self):
        props_query = """describe datalake_clean.amplitude_events"""
        return amplitude_etl.athena_client.execute_txt_query_and_return_dataframe(props_query)

    def __convert_columns_to_number(self, df, columns, _type):
        for col in columns:
            df[col].fillna(0).astype(_type)

        return df

    def __convert_columns_to_text(self, df, column_prefixes, _type):
        for col_prefix in column_prefixes:
            cols = set(df.columns[pd.Series(df.columns).str.startswith(col_prefix)])
            for col in cols:
                df[col] = df[col].fillna('').astype(str)

        return df

    def __convert_columns_to_datetime(self, df, columns):
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
                        with user_nulls as (
                          select device_id, amplitude_id, user_id
                            from datalake_clean.amplitude_events
                          where user_id is null
                             and ym = '{0}'
                        ),
                        user_not_nulls as (
                          select device_id, amplitude_id, user_id
                            from datalake_clean.amplitude_events
                          where user_id is not null
                             and ym = '{0}'
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
                        select rom.device_id, rom.amplitude_id, rom.user_id
                          from amplitude_events.merged_users mu
                        right join result_out_merge rom
                          on mu.device_id = rom.device_id
                             and mu.amplitude_id = rom.amplitude_id::varchar
                             and mu.user_id = rom.user_id
                        where mu.device_id is null
                              and mu.amplitude_id is null
                              and mu.user_id is null
                        )
                    """.format(today_ym),
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
                    """,
            db_enum=EnumDb.BI_DW,
            commit=True
        )

        BaseETL.execute_command(
            command="""drop table if exists amplitude_events.tmp_merge_users_result""",
            db_enum=EnumDb.BI_DW,
            commit=True
        )


if __name__ == '__main__':
    amplitude_etl = AmplitudeETL()

    if args[1] == 'load_data':
        df_raw = amplitude_etl.get_all_columns()

        if df_raw.empty:
            _logger.warn('m=__main__, msg=empty dataframe')
        else:
            df_raw_json = pd.io.json.json_normalize(df_raw.event_data.apply(json.loads))
            df_raw_json['dt'] = df_raw['dt']

            df_properties = amplitude_etl.get_properties_as_df()
            df_raw_json = amplitude_etl.insert_new_columns(
                df=df_raw,
                df_props=df_properties,
                df_json=df_raw_json,
                properties='user_properties',
                prefix='u_'
            )
            df_raw_json = amplitude_etl.insert_new_columns(
                df=df_raw,
                df_props=df_properties,
                df_json=df_raw_json,
                properties='event_properties',
                prefix='e_'
            )

            amplitude_etl.create_parquets(df_raw_json)
    elif args[1] == 'merge_users':
        amplitude_etl.merge_user_ids()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
