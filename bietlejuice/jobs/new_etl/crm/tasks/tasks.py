import json
from abc import abstractmethod
from datetime import datetime
from gzip import GzipFile
from io import BytesIO

import boto3
from botocore.exceptions import ClientError
from ordereddict import OrderedDict
from pymongo import MongoClient
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from unidecode import unidecode

from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.new_etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

logger = QuintoAndarLogger('CRMTasks')


# TODO: move to generic wrapper
class UnidecodeHandler(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, unicode):
            return unidecode(obj)
        if isinstance(obj, datetime):
            return obj.isoformat(' ') if obj.year >= 1900 else obj.replace(year=obj.year + 2000)

        return unidecode(unicode(str(obj)))


class CRMTasks(object):
    DEFAULT_FIELDS_PROJECTION = {
        'metadata.inquilino.dataExpedicaoRg': False,
        'metadata.proprietario.dataExpedicaoRg': False
    }

    BUCKET_FOLDER_SUFFIXES = {
        'tasks': 'crm/tasks',
        'resolution': 'crm/tasks_resolution'
    }

    TABLE_NAMES = {
        'tasks': 'crm_tasks',
        'resolution': 'crm_tasks_resolution'
    }

    SCHEMA_NAMES = {
        'staging': 'staging',
        'prod': 'crm'
    }

    S3_FILE_NAME = 'data'

    TABLE_PARTITION_PARAM = '__PARTITION_DATE__'

    @logger(exclude='mongo_client_uri')
    def __init__(self, s3_bucket, mongo_client_uri, execution_date):
        self.s3_bucket = s3_bucket
        self.mongo_client = MongoClient(mongo_client_uri)
        self.execution_date_from = execution_date.replace(hour=0, minute=0, second=0, microsecond=0)
        self.partition_date = self.execution_date_from.strftime('%Y-%m-%d')
        self.execution_date_to = execution_date.replace(hour=23, minute=59, second=59, microsecond=59)

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_resource = boto3.resource('s3')

    # abstract methods
    @abstractmethod
    def move_fact_to_staging(self):
        raise NotImplementedError('m=move_fact_to_staging, msg=method not implemented')

    @abstractmethod
    def move_dim_to_staging(self):
        raise NotImplementedError('m=move_dim_to_staging, msg=method not implemented')

    @abstractmethod
    def append_fact_to_dw(self):
        raise NotImplementedError('m=append_fact_to_dw, msg=method not implemented')

    @abstractmethod
    def append_dim_to_dw(self):
        raise NotImplementedError('m=append_dim_to_dw, msg=method not implemented')

    @abstractmethod
    def delete_staging_fact_entries(self):
        raise NotImplementedError('m=delete_staging_fact_entries, msg=method not implemented')

    @abstractmethod
    def delete_staging_dim_entries(self):
        raise NotImplementedError('m=delete_staging_dim_entries, msg=method not implemented')

    # instance methods
    @logger
    def data_existence_check(self, bucket_type):
        if bucket_type not in ('raw', 'clean'):
            logger.error('m=data_existence_check, bucket_type={}, msg=invalid bucket type'.format(bucket_type))
            raise ValueError

        file_path = '{}/{}/dt={}/{}.gz'.format(bucket_type,
                                               CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
                                               self.partition_date,
                                               CRMTasks.S3_FILE_NAME)

        try:
            self.s3_resource.Object(self.s3_bucket, file_path).load()
        except ClientError as e:
            if e.response['Error']['Code'] == '404':
                return False  # file does not exist
            raise  # something else had gone wrong

        return True

    @logger
    def __add_incremental_constraints(self):
        return {
            'actions': {
                '$elemMatch': {
                    'date': {
                        '$lte': self.execution_date_to,
                        '$gte': self.execution_date_from
                    }
                }
            }
        }

    @logger
    def extract_and_load_data(self, fields_projection=None):
        incremental_filter = self.__add_incremental_constraints()

        db = self.mongo_client.tasks
        collection_gen = db.tasks.find(
            filter=incremental_filter,
            projection=fields_projection if fields_projection is not None else CRMTasks.DEFAULT_FIELDS_PROJECTION
        ).batch_size(10000)  # reduces the number of trips to the server

        total_count = collection_gen.count()
        logger.info('m=extract_and_load_data, msg=processing {} rows'.format(total_count))
        self.__save_to_s3(
            json_list=collection_gen,
            total_count=total_count
        )

    @logger
    def __delete_old_files(self):
        key = 'raw/{}/dt={}/'.format(CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'], self.partition_date)
        s3_bucket_obj = self.s3_resource.Bucket(self.s3_bucket)

        _files = (s3_bucket_obj
                  .objects
                  .filter(Prefix=key)
                  )

        list_files = list(_files)
        if _files is None or len(list_files) == 0:
            return

        response = (s3_bucket_obj
                    .objects
                    .filter(Prefix=list_files[0].key)  # deleting entire folder
                    .delete())

        if (response is None or
                len(response) == 0 or
                'ResponseMetadata' not in response[0] or
                'HTTPStatusCode' not in response[0]['ResponseMetadata'] or
                response[0]['ResponseMetadata']['HTTPStatusCode'] != 200):
            logger.error('m=__delete_old_files, key={}, msg=error deleting files from S3'.format(key))
            raise Exception

    @logger(exclude='json_list')
    def __save_to_s3(self, json_list, total_count):
        if json_list is None or json_list.count() == 0:
            logger.info('m=__save_to_s3, msg=no results')
            return

        # use the method below if multiple files have to be saved into s3
        # self.__delete_old_files()

        logger.info('m=__save_to_s3, msg=gzipping json_list')

        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode='w') as fp:
                fp.write((json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)).encode('utf-8'))
                fp.write('\n')

        # don't need to clear old entries since the data volume always grows big
        file_suffix = 'raw/{}/dt={}/{}.gz'.format(CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
                                                  self.partition_date,
                                                  CRMTasks.S3_FILE_NAME)
        self.__obj_to_s3(
            obj_io=gz_body,
            file_suffix=file_suffix
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        gz_body.seek(0)
        gz_body.flush()

        logger.info('m=__save_to_s3, msg={} rows saved'.format(total_count))

    def __obj_to_s3(self, obj_io, file_suffix):
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sending to s3'.format(file_suffix))
        BaseETL.obj_to_s3(
            obj_io=obj_io,
            bucket=self.s3_bucket,
            file_path=file_suffix
        )
        logger.info('m=__obj_to_s3, file_suffix={}, msg=sent to s3'.format(file_suffix))

    @logger
    def upsert_tasks_partition(self, bucket_type):
        self.__upsert_partition(
            bucket_type=bucket_type,
            bucket_folder_suffix=CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
            table_name=CRMTasks.TABLE_NAMES['tasks']
        )

    @logger
    def upsert_tasks_resolution_partition(self, bucket_type):
        self.__upsert_partition(
            bucket_type=bucket_type,
            bucket_folder_suffix=CRMTasks.BUCKET_FOLDER_SUFFIXES['resolution'],
            table_name=CRMTasks.TABLE_NAMES['resolution']
        )

    @logger
    def __upsert_partition(self, bucket_type, bucket_folder_suffix, table_name):
        if bucket_type not in ('raw', 'clean'):
            logger.error('m=__upsert_partition, bucket_type={}, msg=invalid bucket type'.format(bucket_type))
            raise ValueError

        self.athena_client.upsert_single_partition(
            bucket_folder_path='{}/{}/{}/'.format(self.s3_bucket, bucket_type, bucket_folder_suffix),
            database='datalake_{}'.format(bucket_type),
            table=table_name,
            partition_name='dt',
            partition_value=self.partition_date
        )

    @logger
    def move_tasks_to_clean(self):
        r_cols = OrderedDict([
            ('links', str),
            ('score_factor', str),
            ('fluxo_locacao_id', str),
            ('actions', str),
            ('data_inicio', str),
            ('nome_destinatario', str),
            ('realizada_em', str),
            ('comentario', str),
            ('origem_id', str),
            ('assignee_id', str),
            ('score', str),
            ('origem', str),
            ('data_visita', str),
            ('type', str),
            ('tipo_destinatario', str),
            ('descricao', str),
            ('fase', str),
            ('silenciada_ate', str),
            ('imovel_id', str),
            ('assunto', str),
            ('tags', str),
            ('opened_by_id', str),
            ('inquilino_id', str),
            ('data_criacao', str),
            ('negociacao_id', str),
            ('origem_data', str),
            ('gerente_id', str),
            ('data_fup', str),
            ('follow_up_visita', str),
            ('metadata', str),
            ('v', str),
            ('proprietario_id', str),
            ('destinatario_id', str),
            ('id', str),
            ('resolvida', str)
        ])

        c_cols = OrderedDict([
            ('links', str),
            ('score_factor', float),
            ('id_rent_flow', float),
            ('actions', str),
            ('dt_start', str),
            ('receiver_name', str),
            ('dt_completed', str),
            ('comment', str),
            ('id_origin', float),
            ('id_assignee', float),
            ('score', str),
            ('origin', str),
            ('dt_visit', str),
            ('type', str),
            ('receiver_type', str),
            ('description', str),
            ('phase', str),
            ('dt_silenced_until', str),
            ('id_house', float),
            ('subject', str),
            ('tags', str),
            ('id_opened_by', float),
            ('id_tenant', float),
            ('dt_created', str),
            ('id_negotiation', float),
            ('data_origin', str),
            ('id_manager', str),
            ('fup_date', str),
            ('fup_visit', str),
            ('metadata', str),
            ('version', float),
            ('id_owner', float),
            ('id_receiver', float),
            ('id', str),
            ('solved', bool)
        ])

        self.__move_to_clean(
            bucket_folder_suffix=CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
            sql_file_name='create_tasks_table.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger
    def move_tasks_resolution_to_clean(self):
        r_cols = OrderedDict([
            ('links', str),
            ('score_factor', str),
            ('id_rent_flow', str),
            ('actions', str),
            ('dt_start', str),
            ('receiver_name', str),
            ('dt_completed', str),
            ('comment', str),
            ('id_origin', str),
            ('id_assignee', str),
            ('score', str),
            ('origin', str),
            ('dt_visit', str),
            ('type', str),
            ('receiver_type', str),
            ('description', str),
            ('phase', str),
            ('dt_silenced_until', str),
            ('id_house', str),
            ('subject', str),
            ('tags', str),
            ('id_opened_by', str),
            ('id_tenant', str),
            ('dt_created', str),
            ('id_negotiation', str),
            ('data_origin', str),
            ('id_manager', str),
            ('fup_date', str),
            ('fup_visit', str),
            ('metadata', str),
            ('version', str),
            ('id_owner', str),
            ('id_receiver', str),
            ('id', str),
            ('solved', str),
            ('action_user_name', str),
            ('id_user_action', str),
            ('dt_action', str),
            ('action_type', str),
            ('dt_task_user_start', str),
            ('dt_task_user_end', str),
            ('task_user_type', str),
            ('task_user_resolve_hours', str)
        ])

        c_cols = OrderedDict([
            ('links', str),
            ('score_factor', float),
            ('id_rent_flow', float),
            ('actions', str),
            ('dt_start', str),
            ('receiver_name', str),
            ('dt_completed', str),
            ('comment', str),
            ('id_origin', float),
            ('id_assignee', float),
            ('score', str),
            ('origin', str),
            ('dt_visit', str),
            ('type', str),
            ('receiver_type', str),
            ('description', str),
            ('phase', str),
            ('dt_silenced_until', str),
            ('id_house', float),
            ('subject', str),
            ('tags', str),
            ('id_opened_by', float),
            ('id_tenant', float),
            ('dt_created', str),
            ('id_negotiation', float),
            ('data_origin', str),
            ('id_manager', str),
            ('fup_date', str),
            ('fup_visit', str),
            ('metadata', str),
            ('version', float),
            ('id_owner', float),
            ('id_receiver', float),
            ('id', str),
            ('solved', bool),
            ('action_user_name', str),
            ('id_user_action', str),
            ('dt_action', str),
            ('action_type', str),
            ('dt_task_user_start', str),
            ('dt_task_user_end', str),
            ('task_user_type', str),
            ('task_user_resolve_hours', float)
        ])

        self.__move_to_clean(
            bucket_folder_suffix=CRMTasks.BUCKET_FOLDER_SUFFIXES['resolution'],
            queries_folder_suffix=CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
            sql_file_name='create_tasks_resolution_table.sql',
            r_cols=r_cols,
            c_cols=c_cols
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def __move_to_clean(self, bucket_folder_suffix, sql_file_name, r_cols, c_cols, queries_folder_suffix=None):
        key = 'clean/{}/dt={}/{}.parq'.format(bucket_folder_suffix,
                                              self.partition_date,
                                              CRMTasks.S3_FILE_NAME)

        query = BaseETL.get_query_from_file_name(
            '{}/{}/{}'.format(DATALAKE_QUERIES_DIR,
                              bucket_folder_suffix if queries_folder_suffix is None else queries_folder_suffix,
                              sql_file_name))

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.replace(CRMTasks.TABLE_PARTITION_PARAM, self.partition_date),
            raw_columns=r_cols,
            clean_columns=c_cols
        )

    @logger
    def __move_to_staging(self, table_name, queues, query_filename, manual_task_workgroups,
                          append_query_filename=None):
        if not queues and not manual_task_workgroups:
            raise ValueError(
                'm=__move_to_staging, queues={}, manual_task_workgroups={}, msg=at least one must be not none')

        query = BaseETL.get_query_from_file_name(
            '{}/{}/{}'.format(DATALAKE_QUERIES_DIR,
                              CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
                              query_filename)
        )

        if queues is None:
            where_clause = """(trim(ct.type) = 'Manual' and regexp_extract(ct.metadata, 'workgroupid":"([^"]+)', 1) in ('{manual_workgroups}'))""".format(
                manual_workgroups="', '".join(workgroup for workgroup in manual_task_workgroups))
        else:
            where_clause = "trim(ct.type) in ('{types}')".format(types="', '".join(queue for queue in queues))

            if manual_task_workgroups:
                where_clause = """({previous_clause} or (trim(ct.type) = 'Manual' and regexp_extract(ct.metadata, 'workgroupid":"([^"]+)', 1) in ('{manual_workgroups}')))""".format(
                    previous_clause=where_clause,
                    manual_workgroups="', '".join(workgroup for workgroup in manual_task_workgroups))

        empty = self.__is_prod_table_empty(table_name=table_name)
        if not empty:
            where_clause = """{previous_clause}
                                and dt = '{dt_partition}'""".format(previous_clause=where_clause,
                                                                    dt_partition=self.partition_date)

        final_query = query.replace('__WHERE_CLAUSE__', where_clause)

        if append_query_filename is not None:
            append_query = BaseETL.get_query_from_file_name(
                '{}/{}/{}'.format(DATALAKE_QUERIES_DIR,
                                  CRMTasks.BUCKET_FOLDER_SUFFIXES['tasks'],
                                  append_query_filename
                                  )
            )
            final_query = '{}\n{}'.format(final_query, append_query)

        df = self.athena_client.execute_query_and_return_dataframe(final_query)

        logger.info('m=__move_to_staging, table_name={}, msg=sending df to DW staging'.format(table_name))
        BaseETL.dataframe_to_db(
            df=df,
            table_name='{}.{}'.format(CRMTasks.SCHEMA_NAMES['staging'], table_name),
            enum_db=EnumDB.BI_DW,
            encoding='utf-8',
            append=False
        )

    def _move_dim_to_staging(self, table_name, queues=None, manual_task_workgroups=None):
        self.__move_to_staging(
            table_name=table_name,
            queues=queues,
            query_filename='create_staging_dim_table.sql',
            manual_task_workgroups=manual_task_workgroups
        )

    @logger
    def _move_fact_to_staging(self, table_name, queues=None, manual_task_workgroups=None,
                              append_query_filename='append_fact_default_info.sql'):
        self.__move_to_staging(
            table_name=table_name,
            queues=queues,
            query_filename='create_staging_fact_table.sql',
            manual_task_workgroups=manual_task_workgroups,
            append_query_filename=append_query_filename
        )

    @logger
    def _append_fact_to_dw(self, table_name, query_filename='append_fact_default_table.sql'):
        self.__append_to_dw(
            schema=CRMTasks.SCHEMA_NAMES['prod'],
            table_name=table_name,
            query_filename=query_filename
        )

    @logger
    def _append_dim_to_dw(self, table_name):
        self.__append_to_dw(
            schema=CRMTasks.SCHEMA_NAMES['prod'],
            table_name=table_name,
            query_filename='append_dim_table.sql'
        )

    @logger
    def __append_to_dw(self, schema, table_name, query_filename):
        upsert_query = BaseETL.get_query_from_file_name('{}/crm/{}'.format(DW_QUERIES_DIR, query_filename))

        empty = self.__is_prod_table_empty(table_name=table_name)
        if empty:
            logger.info(
                'm=__append_to_dw, schema={}, table_name={}, msg=table already empty'.format(
                    CRMTasks.SCHEMA_NAMES['prod'], table_name))
        else:
            deletion_query = BaseETL.get_query_from_file_name(
                file_name='{}/crm/delete_old_entries.sql'.format(DW_QUERIES_DIR))

            logger.info(
                'm=__append_to_dw, schema={}, table_name={}, msg=deleting old entries'.format(
                    CRMTasks.SCHEMA_NAMES['prod'],
                    table_name))
            BaseETL.execute_command(
                command=deletion_query.format(
                    table_name=table_name,
                    partition_date=self.partition_date
                ),
                db_enum=EnumDB.BI_DW,
                encoding='utf-8',
                commit=True
            )

            upsert_query = '{}\n where dt_partition = \'{}\';'.format(upsert_query, self.partition_date)

        self.__append_into_dw(
            upsert_query=upsert_query.format(table_name=table_name),
            schema=schema,
            table_name=table_name
        )

    @logger
    def __append_into_dw(self, upsert_query, schema, table_name):
        logger.info(
            'm=__append_into_dw, schema={}, table_name={}, msg=getting data from DW'.format(schema, table_name))
        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=upsert_query,
            encoding='utf-8',
        )

        logger.info(
            '__upsert_into_dw, schema={}, table_name={}, msg=bulk inserting...'.format(schema, table_name))

        BaseETL.bulk_insert(
            table=table_data,
            table_name='{}.{}'.format(schema, table_name),
            db_enum=EnumDB.BI_DW,
            encoding='utf-8'
        )

    @logger
    def _delete_staging_entries(self, table_name):
        BaseETL.truncate_table(
            db_enum=EnumDB.BI_DW,
            schema=CRMTasks.SCHEMA_NAMES['staging'],
            table_name=table_name
        )

    @logger
    def __is_prod_table_empty(self, table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query='select 1 from {}.{} limit 1'.format(CRMTasks.SCHEMA_NAMES['prod'], table_name)
        )

        return len(result) == 1
