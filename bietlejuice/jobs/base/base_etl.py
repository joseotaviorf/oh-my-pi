import codecs
import datetime
import gzip
import io
import json
import os
import re
import sys
import zipfile
from StringIO import StringIO
from decimal import Decimal
from functools import partial
from io import BytesIO
from logging import info as log
from os.path import exists
import boto3
import petl
from db_factory import DBFactory
from enum_db import EnumDB
from petl.io.db import create_table
from unidecode import unidecode
import yaml

data_acc_aws_access_key_id = os.environ.get('DATA_ACC_AWS_ACCESS_KEY_ID')
data_acc_aws_secret_access_key = os.environ.get('DATA_ACC_AWS_SECRET_ACCESS_KEY')


class BaseETL(object):
    def __init__(self, *args, **kwargs):
        pass

    @staticmethod
    def now():
        return datetime.datetime.utcnow()

    @staticmethod
    def get_current_filename():
        import inspect
        frame = inspect.stack()[1]
        module = inspect.getmodule(frame[0])
        return module.__file__.split('/')[-1:][0].replace('.py', '')

    @classmethod
    def decode_table(cls, table, encoding):
        table_r = []

        for line in table:
            line_r = []
            for i in line:
                if isinstance(i, str) or isinstance(i, unicode):
                    i = i.decode(encoding)
                line_r.append(i)
            table_r.append(line_r)
        return table_r

    @staticmethod
    def get_json_from_zipfile(f):
        messages = []
        with zipfile.ZipFile(f, 'r') as zfile:
            for name in zfile.namelist():
                if re.search(r'\.gz$', name):
                    buffer_gz = io.BytesIO(zfile.read(name))
                    with gzip.GzipFile(fileobj=buffer_gz, mode='rb') as gzfile:
                        file_content = gzfile.read()
                        for x in file_content[0:-1].split('\n'):
                            yield json.dumps(json.loads(x))
                            # messages += [json.dumps(json.loads(x)) for x in file_content[0:-1].split('\n')]
                            # return messages

    @staticmethod
    def get_table_from_json_child(events, json_column_name, attrib_name, value):
        events[json_column_name][value][attrib_name] = value
        return petl.fromdicts([events[json_column_name][value]])

    @staticmethod
    def publish_messages(messages, queue_name):
        sqs = boto3.resource('sqs')
        queue = sqs.get_queue_by_name(QueueName=queue_name)
        for message in messages:
            queue.send_message(
                MessageBody=message
            )

    @staticmethod
    def publish_notifications(notifications, topic_arn):
        sns = boto3.client('sns')
        c = 0
        for n in notifications:
            sns.publish(
                TopicArn=topic_arn,
                Message=n
            )
            c += 1
        return c

    @classmethod
    def json_loads_byteified(cls, json_text):
        return cls._byteify(
            json.loads(json_text, object_hook=cls._byteify),
            ignore_dicts=True
        )

    @classmethod
    def _byteify(cls, data, ignore_dicts=False):
        # if this is a unicode string, return its string representation
        if isinstance(data, unicode):
            return data.encode('utf-8')
        # if this is a list of values, return list of byteified values
        if isinstance(data, list):
            return [cls._byteify(item, ignore_dicts=True) for item in data]
        # if this is a dictionary, return dictionary of byteified keys and values
        # but only if we haven't already byteified it
        if isinstance(data, dict) and not ignore_dicts:
            return {
                cls._byteify(key, ignore_dicts=True): cls._byteify(value, ignore_dicts=True)
                for key, value in data.iteritems()
            }
        # if it's anything else, return it in its original form
        return data

    @classmethod
    def get_message_content(cls, message):
        body = json.loads(message.body)
        m = cls.json_loads_byteified(body[u'Message'] if body.get(u'Message') else body)
        m = json.dumps(m)
        return m

    @staticmethod
    def get_connection(db_enum, encoding='LATIN1', timeout=0):
        return DBFactory.get_connection(db_enum, encoding, timeout)

    @classmethod
    def to_db(cls, db_enum, data_table, table_name,
              encoding='LATIN1', append=True, schema=None, commit=True, conn=None, create=False):
        """table: list of lists like a PETL Table """
        if not conn:
            conn = cls.get_connection(db_enum=db_enum, encoding=encoding)

        log('Loading {} on {} - Number of rows:{}. {}'.format(
            table_name, db_enum, len(data_table), datetime.datetime.now()))
        if append and not create:
            petl.appenddb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit)
        else:
            petl.todb(table=data_table, dbo=conn, tablename=table_name, schema=schema, commit=commit, create=create)
        log('{} rows loaded on {}. {}'.format(len(data_table) - 1, db_enum, datetime.datetime.now()))
        sys.stdout.flush()

    @staticmethod
    def format_parameters_to_db(line, encode_to='LATIN1'):
        l = []
        for item in line:
            if isinstance(item, datetime.datetime):
                if len(str(item)) <= 8:
                    l.append(datetime.datetime.strftime(item, "%Y%m%d"))
                else:
                    l.append(datetime.datetime.strftime(item, "%Y-%m-%d %H:%M:%S"))
            elif item is None:
                l.append('null')
            elif isinstance(item, Decimal):
                l.append(float(item))
            elif isinstance(item, unicode) or isinstance(item, str):
                l.append(item.encode(encode_to).replace("'", "").replace(",", ""))
            else:
                l.append(item)
        values = str(l).replace('[', '(').replace(']', ')').replace("'null'", "null")
        return values

    @staticmethod
    def format_parameter(p):
        return "'{0}'".format(str(p)) if p else 'null'

    @classmethod
    def execute_function(cls, db_enum, function_name, table=None, conn=None, encoding='LATIN1', commit=False):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)

        conn.autocommit = commit
        if table:
            for line in table:
                if line != table[0]:
                    values = cls.format_parameters_to_db(line)
                    command = "select {0} {1}".replace("()", "").format(function_name, values)
                    conn.cursor().execute(command)
        else:
            fn = function_name if (str(function_name).strip().endswith(")")) else "{0}()".format(function_name)
            command = "select {0}".format(fn)
            conn.cursor().execute(command)

    @classmethod
    def execute_file_query(cls, filename, db_enum=None, conn=None, encoding='LATIN1', commit=False,
                           return_value=False, show_logs=True, timeout=0):
        with open(filename) as f:
            command = f.read()
        cls.execute_command(command, db_enum, conn, encoding, commit, return_value, show_logs, timeout)

    @classmethod
    def execute_command(cls, command, db_enum=None, conn=None, encoding='LATIN1', commit=False,
                        return_value=False, show_logs=True, timeout=0):
        if not db_enum and not conn:
            raise AttributeError()
        if not conn:
            conn = cls.get_connection(db_enum, encoding, timeout)

        if show_logs:
            print ('Starting Connection at: {}'.format(cls.now()))

        cursor = conn.cursor()

        if show_logs:
            print ('Starting Execute Command at: {}'.format(cls.now()))

        cursor.execute(command)

        if commit:
            if show_logs:
                print ('Starting Commit Command at: {}'.format(cls.now()))
            conn.commit()

        if show_logs:
            print ('Ended Execute Command at: {}'.format(cls.now()))

        if return_value:
            return_value = None if cursor.rowcount <= 0 else cursor.fetchone()
            return None if not return_value else return_value[0]

    @staticmethod
    def coalesce(value, ret=None):
        if not ret:
            ret = 'null'
        return ret if value is None else value

    @staticmethod
    def format_date(date):
        return str(datetime.datetime.strptime(date, '%Y-%m-%dT%H:%M:%SZ')) if date else 'null'

    @classmethod
    def insert_row(cls, table, db_enum, table_name, key_name=None, conn=None, encoding='LATIN1', commit=True):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)

        conn.autocommit = commit
        header = cls.format_parameters_to_db(table[0]).replace("'", "\"")
        id_of_new_row = None
        for line in table:
            if line != table[0]:
                values = cls.format_parameters_to_db(line)
                return_value = """returning "{}" """.format(key_name) if key_name is not None else ""
                command = """insert into {0}{1} values {2} {3};""".format(table_name, header, values, return_value)
                cursor = conn.cursor()
                cursor.execute(command)
                id_of_new_row = cursor.fetchone()[0]

        return id_of_new_row

    @staticmethod
    def update_data(table, db_enum, table_name, key_name=None, conn=None, commit=True):
        raise Exception("Not implemented")

    @classmethod
    def create_table(cls, conn, table, tablename, schema=None, commit=True,
                     constraints=True, metadata=None, dialect=None, sample=10000):
        return create_table(table, conn, tablename, schema, commit, constraints, metadata, dialect, sample)

    @classmethod
    def from_db_table(cls, db_enum, table_name, encoding='LATIN1',
                      server_cursor_postgres=None, generator=False, convert_bit_mysql=True):
        table = cls.from_db_query(db_enum=db_enum, query='SELECT * FROM {}'.format(table_name),
                                  encoding=encoding, server_cursor_postgres=server_cursor_postgres, generator=generator)
        if convert_bit_mysql:
            # get all columns declared as BIT because we have a bug converting BIT columns on mysql
            types = BaseETL.get_columns_schema(db_enum, table_name, None, False)
            if types:
                bit_columns = petl.select(types, lambda rec: rec.DATA_TYPE == 'bit')
                table = petl.convert(table, tuple(bit_columns['COLUMN_NAME']), {u'\x00': u'0', u'\x01': u'1'})

        return table

    @classmethod
    def from_db_query(cls, db_enum, query, encoding='LATIN1', server_cursor_postgres=None, conn=None, generator=False):
        if not conn:
            conn = cls.get_connection(db_enum, encoding)
        print('Starting {} on {}. {}'.format(unidecode(query.decode('utf-8')), db_enum, datetime.datetime.now()))

        l = None
        if server_cursor_postgres:
            l = petl.fromdb(lambda: conn.cursor(name=server_cursor_postgres), query)
            print('Server cursor created: {} - {}'.format(server_cursor_postgres, datetime.datetime.now()))
        else:
            ret = petl.fromdb(conn, query)
            if not generator:
                l = list(ret)
                print('Query returned {} rows. {}'.format(len(l), datetime.datetime.now()))
            else:
                l = ret
                print('Query returned a generator... - {}'.format(datetime.datetime.now()))
        sys.stdout.flush()
        return l

    @classmethod
    def get_table_count(cls, db_enum, table_name):
        return cls.from_db_query(
            query="select count(1) from {}".format(table_name),
            db_enum=db_enum
        )[1][0]

    @classmethod
    def table_exists(cls, db_enum, table_name, schema='public'):
        exists = cls.from_db_query(
            query="""
                SELECT 1
                FROM   information_schema.tables
                WHERE  table_schema = '{}'
                AND    table_name = '{}'
                """.format(schema, table_name),
            db_enum=db_enum
        )
        return len(exists) > 1 and exists[1][0]

    @classmethod
    def drop_table(cls, db_enum, table_name, schema='public'):
        cls.execute_command(command='DROP TABLE IF EXISTS "{}"."{}";'.format(schema, table_name), db_enum=db_enum,
                            commit=True, timeout=30)

    @classmethod
    def truncate_table(cls, db_enum, table_name, schema='public'):
        cls.execute_command(
            command='TRUNCATE TABLE "{}"."{}";'.format(schema, table_name),
            db_enum=db_enum,
            timeout=500,
            commit=True
        )

    @classmethod
    def move_table_to_dw(cls, table_name, enum_db_source, enum_db_dest,
                         table_name_dest=None, append=True, encoding='utf8', server_cursor_postgres=None,
                         bucket_name=None, process_name=None):
        data_table = cls.from_db_table(db_enum=enum_db_source, table_name=table_name,
                                       encoding=encoding, server_cursor_postgres=server_cursor_postgres)
        if not table_name_dest:
            table_name_dest = table_name
        if not process_name:
            process_name = table_name_dest

        filename = '{}.csv'.format(process_name)
        bucket_name, filename = cls.to_s3(filename, data_table, bucket_name, encoding=encoding)
        cls.bulk_insert_from_s3_to_dw(
            bucket_name=bucket_name,
            filename=filename,
            enum_db_dest=enum_db_dest,
            table_name=table_name_dest,
            append=append,
            encoding=encoding)

        return bucket_name, filename

    @classmethod
    def copy_file_between_s3_buckets(cls, bucket_source, bucket_destination,
                                     full_filename_source, full_filename_dest):
        if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
            s3 = boto3.resource('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
        else:
            s3 = boto3.resource('s3')
        copy_source = {
            'Bucket': bucket_source,
            'Key': full_filename_source
        }
        s3.meta.client.copy(copy_source, bucket_destination, full_filename_dest)

    @classmethod
    def get_table_ddl_query_from_dataframe(cls, df, table_name):
        df_columns = []
        # list with all column names and max length
        for column in df:
            max_length = df[column].astype(str).str.len().max()
            df_columns.append({'name': column, 'max_length': max_length})
        if len(df_columns) == 0:
            raise ValueError('m=create_table_from_dataframe, table_name={}, msg=dataframe has no '
                             'columns'.format(table_name))
        # create sql statement for columns considering their max length
        df_columns_text = []
        for column in df_columns:
            max_length = column['max_length']
            if max_length > 65536:
                raise ValueError('m=create_table_from_dataframe, table_name={}, column={}, '
                                 'size={}, msg=dataframe has a column with very long '
                                 'text string'.format(table_name, column['name'], column['max_length']))
            elif max_length > 256:
                max_length = max_length + (max_length % 8)  # round to multiples of eight
                length_text = '({})'.format(max_length)
            else:
                length_text = ''
            column_text = ' "{}" varchar{}'.format(column['name'], length_text)
            df_columns_text.append(column_text)
        df_columns_text = ', '.join(df_columns_text)
        statement = 'CREATE TABLE IF NOT EXISTS {} ({})'.format(table_name, df_columns_text)
        return statement

    @classmethod
    def create_table_from_dataframe(cls, df, table_name, enum_db, encoding='LATIN1', commit=True):
        statement = BaseETL.get_table_ddl_query_from_dataframe(df, table_name)
        BaseETL.execute_command(
            command=statement,
            db_enum=enum_db,
            encoding=encoding,
            commit=commit
        )

    @classmethod
    def dataframe_to_db(cls, df, table_name, enum_db, encoding='LATIN1', append=True, commit=True, bucket_name=None,
                        int_columns=None):
        df_table = petl.fromdataframe(df=df)
        for column in int_columns or []:
            df_table = petl.convert(df_table, column, int)
        BaseETL.bulk_insert(
            table=df_table,
            table_name=table_name,
            db_enum=enum_db,
            encoding=encoding,
            append=append,
            commit=commit,
            bucket_name=bucket_name
        )

    @classmethod
    def dataframe_to_ods(cls, df, table_name, encoding='LATIN1', append=True, commit=True):
        cls.dataframe_to_db(df, table_name, EnumDB.BI_ODS, encoding=encoding, append=append, commit=commit)

    @classmethod
    def bulk_insert(cls, table, table_name, db_enum,
                    encoding='LATIN1', append=True, commit=True, delimiter=',', bucket_name=None, conn=None):
        # create a s3_tmp_file before insert on DB
        tmpdir = '/tmp'
        filename = table_name
        if append:
            filename = '{}_{}'.format(filename, cls.now())
        filename = '{}.csv'.format(filename)
        cls.to_s3(filename, table, bucket_name, encoding, tmpdir)
        csv_temp_file = '{}/{}'.format(tmpdir, filename)

        cls.bulk_insert_from_local_file(csv_temp_file, table_name, db_enum, encoding, append, commit, conn)

    @classmethod
    def bulk_insert_from_local_file(cls, csv_filepath, table_name, db_enum,
                                    encoding='LATIN1', append=True, commit=True, conn=None):
        with codecs.open(filename=csv_filepath, encoding=encoding) as f:
            bucket_folder_path, filename = cls.file_to_s3(filename=csv_filepath, dir_path='')
            cls.bulk_insert_from_s3_to_dw(bucket_folder_path, filename, db_enum,
                                          table_name, append, commit, encoding, f, conn)

    @classmethod
    def bulk_insert_from_s3_to_dw(cls, bucket_name, filename, enum_db_dest, table_name,
                                  append=True, commit=True, encoding='LATIN1', f_cursor=None, conn=None):
        aws_access_key_id = os.environ.get('AWS_ACCESS_KEY_ID')
        aws_secret_access_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
        forno = os.environ.get('forno')
        con = cls.get_connection(enum_db_dest, encoding) if not conn else conn
        file = 's3://{}/{}'.format(bucket_name, filename)
        delimiter = ','

        session_token_str = ''
        aws_session_token = os.environ.get('AWS_SESSION_TOKEN')
        if aws_session_token:
            print 'm=bulk_insert_from_s3_to_dw, msg=Using aws_session_token in credentials'
            session_token_str = ';token={}'.format(aws_session_token)

        credentials_str = """CREDENTIALS 'aws_access_key_id={};aws_secret_access_key={}{}'""".format(
            aws_access_key_id, aws_secret_access_key, session_token_str)

        # TODO: FIX THIS -> if env = forno, we got a postgres database, so COPY command is not equal
        try:
            if not append:
                print 'm=bulk_insert_from_s3_to_dw, table_name={}, msg=truncating table'.format(table_name)
                con.cursor().execute('truncate table {};'.format(table_name))
            if enum_db_dest == EnumDB.BI_DW and not eval(str(forno)):
                print 'm=bulk_insert_from_s3_to_dw, table_name={}, file={}, msg=copying file from s3 to Redshift'.format(
                    table_name, file)
                sql = """COPY {} FROM '{}'
                        {}
                        NULL AS 'NULL'
                        EMPTYASNULL
                        DELIMITER '{}' FORMAT CSV IGNOREHEADER 1; commit;""".format(
                    table_name, file, credentials_str, delimiter)

                print 'm=bulk_insert_from_s3_to_dw, msg=Executing SQL'
                result = con.cursor().execute(sql)
                print 'm=bulk_insert_from_s3_to_dw, copy_result={}, msg=Success coping table'.format(result)
            else:
                print 'm=bulk_insert_from_s3_to_dw, table_name={}, file={}, msg=copying file from stdin to ODS'.format(
                    table_name, file)
                sql = """COPY {} FROM stdin DELIMITER '{}' CSV header;""".format(table_name, delimiter)
                con.cursor().copy_expert(sql, f_cursor)

            if commit:
                print 'm=bulk_insert_from_s3_to_dw, msg=committing transaction'
                con.commit()
        except Exception as e:
            raise Exception('m=bulk_insert_from_s3_to_dw, e={}, msg=An exception occurred'.format(e))
        finally:
            if not conn:
                print 'm=bulk_insert_from_s3_to_dw, msg=closing connection'
                con.close()

    @classmethod
    def to_s3(cls, filename, data_table, bucket_folder_path=None, encoding='utf8', tmp_dir='/tmp', write_header=True):
        try:
            petl.tocsv(data_table, '{}/{}'.format(tmp_dir, filename), encoding=encoding, write_header=write_header)
            return cls.file_to_s3(filename=filename, dir_path=tmp_dir, bucket_folder_path=bucket_folder_path)
        except Exception as ex:
            log(ex)
            sys.stdout.flush()
            return None

    @classmethod
    def file_to_s3(cls, filename, dir_path='/tmp', bucket_folder_path=None):
        tmp_fn = '{}/{}'.format(dir_path, filename)
        tmp_bucket = 'bi-etl-ejuice-tmpfiles'

        try:
            if not bucket_folder_path:
                bucket_folder_path = os.environ['s3-tmpfiles'] if os.environ.get(
                    's3-tmpfiles') else tmp_bucket
            else:
                bucket_arr = bucket_folder_path.split('/')
                if len(bucket_arr) > 1:
                    bucket_folder_path = bucket_arr[0]
                    folder = '/'.join(bucket_arr[1:])
                    filename = '{}/{}'.format(folder, filename)
            if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
                s3 = boto3.client('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
            else:
                s3 = boto3.client('s3')
            s3.upload_file(tmp_fn, bucket_folder_path, filename)
        except Exception as ex:
            log(ex)
            sys.stdout.flush()
            return None
        return bucket_folder_path, filename

    def json_to_s3(self, dict_list, s3_bucket, s3_key):
        json_list = map(partial(json.dumps, ensure_ascii=False), dict_list)
        json_lines = u'\n'.join(json_list).encode('utf-8')

        body = StringIO()
        with gzip.GzipFile(fileobj=body, mode='wt') as gz_file:
            gz_file.write(json_lines)

        self.obj_to_s3(
            obj_io=body,
            bucket=s3_bucket,
            file_path=s3_key
        )

    @classmethod
    def obj_to_s3(cls, obj_io, bucket, file_path):
        if not obj_io or not bucket or not file_path:
            return
        if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
            s3 = boto3.resource('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
        else:
            s3 = boto3.resource('s3')

        s3.Bucket(bucket).put_object(Body=obj_io.getvalue(), Key=file_path)

    @classmethod
    def dump_ods_to_datalake(cls, table_name, s3_bucket, filename=None):
        if s3_bucket is None or len(s3_bucket) == 0:
            raise AttributeError('m=dump_ods_to_datalake, table_name={}, s3_bucket={}, filename={}, msg=s3_bucket is '
                                 'invalid'.format(table_name, s3_bucket, filename))

        if not filename:
            filename = table_name

        BaseETL.to_s3(
            filename='{}.csv'.format(filename),
            data_table=BaseETL.from_db_table(db_enum=EnumDB.BI_ODS, table_name=table_name),
            bucket_folder_path='{}/raw/ods/{}'.format(s3_bucket, filename)
        )
        BaseETL.copy_file_between_s3_buckets(
            bucket_source=s3_bucket,
            bucket_destination=s3_bucket,
            full_filename_source='raw/ods/{0}/{0}.csv'.format(filename),
            full_filename_dest='clean/ods/{0}/{0}.csv'.format(filename)
        )

    @staticmethod
    def delete_file_s3(bucket_name, fn):
        if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
            s3 = boto3.resource('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
        else:
            s3 = boto3.resource('s3')

        bucket = s3.Bucket(bucket_name)
        bucket.delete_objects(
            Delete={
                'Objects': [
                    {
                        'Key': fn
                    }
                ]
            }
        )

    @classmethod
    def get_surrogate_key(cls, dimension_table, fact_table, dimension_key, fact_key, sk_name_column,
                          filter_injected_rule=None, rename_dict=None, remove_fact_key=False):
        table = petl.leftjoin(fact_table, dimension_table, lkey=fact_key, rkey=dimension_key, missing='-1')
        if filter_injected_rule:
            table = table.select(lambda item: filter_injected_rule(item))

        cutout_columns = list(dimension_table[0])
        cutout_columns.remove(dimension_key)
        cutout_columns.remove(sk_name_column)
        if remove_fact_key:
            cutout_columns.append(fact_key)

        table = table.cutout(*cutout_columns)

        if rename_dict:
            table = table.rename(rename_dict)

        return table

    @classmethod
    def convert_dataframe_to_json_gzip(cls, data_frame, encode='utf-8'):
        print('m=convert_dataframe_to_json_gzip')
        with cls.open_gzip_fp() as fp:
            for row in data_frame.iterrows():
                item = row[1].to_json().encode(encode)
                cls.write_json_in_fp(item, fp)
        return fp.fileobj

    @classmethod
    def open_gzip_fp(cls, mode='w'):
        print('m=open_gzip_fp')
        gz_obj = io.BytesIO()
        fp = gzip.GzipFile(fileobj=gz_obj, mode=mode)
        return fp

    @classmethod
    def write_json_in_fp(cls, item, fp):
        fp.write(unicode(item).replace('"None"', 'null'))
        fp.write('\n')

    @classmethod
    def convert_camel_to_snake_case(cls, name):
        s1 = re.sub('(.)([A-Z][a-z]+)', r'\1_\2', name)
        return re.sub('([a-z0-9])([A-Z])', r'\1_\2', s1).lower()

    @classmethod
    def get_columns_schema(cls, db_enum, table_name, schema_name=None, skip_header=True):
        columns_table = None

        if db_enum == EnumDB.QuintoAndar_ebdb:
            query = """
                select
                    COLUMN_NAME,
                    DATA_TYPE
                from information_schema.COLUMNS
                where
                    TABLE_NAME = '{}'
                """.format(table_name)
            if schema_name:
                query += " and TABLE_SCHEMA = '{}'".format(schema_name)

            columns_table = BaseETL.from_db_query(
                db_enum=db_enum,
                query=query
            )
            if skip_header:
                columns_table.pop(0)

        return columns_table

    @classmethod
    def get_query_from_file_name(cls, file_name):
        try:
            with open(file_name) as f:
                return f.read()
        except IOError:
            print('m=get_query_from_file_name, file_name={}, msg=file not found'.format(file_name))
            return ''

    @classmethod
    def csv_to_s3(cls, data, bucket, filename):
        csv_buffer = BytesIO()
        data.to_csv(csv_buffer, index=False, encoding='utf8')
        if data_acc_aws_access_key_id is not None and data_acc_aws_secret_access_key is not None:
            s3 = boto3.resource('s3', aws_access_key_id=data_acc_aws_access_key_id, aws_secret_access_key=data_acc_aws_secret_access_key)
        else:
            s3 = boto3.resource('s3')
        s3.Bucket(bucket).put_object(
            Body=csv_buffer.getvalue(),
            Key=filename
        )

    @classmethod
    def move_file_query_data_to_db(cls, schema, file_name, table_name, append, db_enum_source, db_enum_destination,
                                   query_params_dict=None):
        query = BaseETL.get_query_from_file_name(file_name=file_name)

        if query_params_dict:
            query = query.format(**query_params_dict)

        table = BaseETL.from_db_query(
            db_enum=db_enum_source,
            query=query)

        BaseETL.bulk_insert(
            table=table,
            table_name='{}.{}'.format(schema, table_name),
            db_enum=db_enum_destination,
            encoding='UTF-8',
            append=append
        )

    @staticmethod
    def get_dict_from_yaml_file(file_path):
        if not exists(file_path):
            raise RuntimeError(
                "m=get_dict_from_yaml_file, file_path={}, msg=File not found in the specified path".format(file_path)
            )

        with open(file_path, "r") as stream:
            try:
                response = yaml.safe_load(stream)
            except yaml.YAMLError as ex:
                print(
                    "m=get_dict_from_yaml_file, file_path={}, msg=YAML content cannot be parsed, e={}".format(
                        file_path,
                        ex)
                )
                raise ex
        return response or {}
