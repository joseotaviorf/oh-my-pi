import json
import os
import re
from collections import OrderedDict
from datetime import datetime
from gzip import GzipFile
from io import BytesIO

import boto3
import pandas as pd
from jsonschema import Draft4Validator
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger


class SchemaValidator(object):
    _PATH_PREFIX = 'schemas'

    @logger
    def __init__(self, execution_date, s3_bucket):
        self.today = execution_date.date()
        self.s3_bucket = s3_bucket
        self.ym = '{}-{}'.format(self.today.year, self.today.strftime('%m'))

        self.athena_client = AthenaClient(self.s3_bucket)
        self.s3_client = boto3.client('s3')

        self.schema_dict = {}

        _logger.info('m=__init__, msg=reading dir: {}'.format(SchemaValidator._PATH_PREFIX))
        for root, dirs, files in os.walk(SchemaValidator._PATH_PREFIX):
            self.schema_dict[root] = files

    @staticmethod
    def validate_amplitude_schema(event_json, schema_json):
        dict_errors = []

        app_id = event_json['app']
        event_type = event_json['event_type']
        uuid = event_json['uuid']
        server_upload_time = (event_json['server_upload_time'])
        platform = event_json['platform']
        validation_time = datetime.utcnow()

        v = Draft4Validator(schema_json)
        for error in sorted(v.iter_errors(event_json), key=str):
            err_validator_value = ''
            err_instance = ''
            err_detail = ''

            # error path
            if len(list(error.path)) == 1:
                err_path = str(error.path[0])
            elif len(list(error.path)) == 2:
                err_path = str(error.path[0]) + '.' + str(error.path[1])
            else:
                err_path = str(error.path)

            # error validator
            err_validator = str(error.validator)

            # error validator value
            # if multiple conditions return string of object
            if err_validator in ('anyOf', 'oneOf', 'allOf'):
                err_validator_value = json.dumps(error.validator_value)
                err_instance = json.dumps(error.instance)
            else:
                if type(error.validator_value) == list:
                    for field in error.validator_value:
                        err_validator_value = err_validator_value + ', ' + str(
                            field) if err_validator_value != '' else str(field)
                elif type(error.validator_value) == unicode:
                    err_validator_value = str(error.validator_value)
                else:
                    err_validator_value = json.dumps(error.validator_value)

                # error instance value (received value)
                if type(error.instance) in (dict, list):
                    for field, value in error.instance.iteritems():
                        err_instance = err_instance + ', ' + str(field) if err_instance != '' else str(field)
                elif type(error.instance) == unicode:
                    err_instance = str(error.instance)
                else:
                    err_instance = json.dumps(error.instance)

                # set a custom detail for the error
                if error.validator == 'required':
                    for field in list(set(error.validator_value) - set(error.instance.keys())):
                        err_detail = err_detail + ', ' + field if err_detail != '' else 'missing: ' + field

            dict_errors.append(
                [
                    app_id, event_type, uuid, server_upload_time, platform,
                    validation_time, err_path, err_validator,
                    err_validator_value, err_instance, err_detail,
                    'validated with errors' if err_detail != ''
                                               or err_instance != ''
                                               or err_validator_value != ''
                                            else 'skipped'
                ]
            )

        return dict_errors

    @logger
    def validate_events_and_save_into_s3(self):
        ts_start = datetime.now()
        _logger.info('m=validate_events, msg=job started at {}'.format(ts_start))

        for app, ets in self.schema_dict.iteritems():
            _logger.info('m=validate_events_and_save_into_s3, msg=processing app: {}'.format(app))

            app = re.search('(\d+)', app)
            if not app or len(app.groups()) == 0:
                _logger.warn('m=validate_events_and_save_into_s3, msg=couldn\'t find app')
                continue

            app = app.group(1)
            for et in ets:
                _logger.info('m=validate_events_and_save_into_s3, msg=processing event: {} for app: {}'.format(et, app))

                et = re.search('(.*)\.schema\.json', et)
                if not et or len(et.groups()) == 0:
                    _logger.warn('m=validate_events_and_save_into_s3, msg=couldn\'t find event type')
                    continue

                et = et.group(1)
                # read list of files in s3 folder
                response = self.s3_client.list_objects_v2(
                    Bucket=self.s3_bucket,
                    Prefix='raw/amplitude/events/dt={}/et={}/app={}/'.format(self.today, et, app)
                )

                if response['KeyCount'] < 1:
                    _logger.info('m=validate_events_and_save_into_s3, msg=response_key_count < 1;skipping...')
                    continue

                # set schema path and file
                json_schema_path = '{}/{}/'.format(SchemaValidator._PATH_PREFIX, app)
                json_schema_file = '{}.schema.json'.format(et)

                for key in response['Contents']:
                    _logger.info('m=validate_events_and_save_into_s3, msg=reading {}'.format(key['Key']))

                    json_file = key['Key']
                    obj = self.s3_client.get_object(Bucket=self.s3_bucket, Key=json_file)
                    byte_stream = BytesIO(obj['Body'].read())

                    result_obj = GzipFile(None, 'rb', fileobj=byte_stream)
                    result = result_obj.read().decode('utf-8')
                    result_final = result.split('\n')
                    result_final = result_final[:-1] if result_final[len(result_final) - 1] == '' else result_final

                    # event schema validation
                    with open(json_schema_path + json_schema_file) as json_schema:
                        schema = json.load(json_schema)

                    _logger.info('m=validate_events_and_save_into_s3, et={}, dt={}, app={}, '
                                 'msg=validating schema'.format(et, self.today, app))

                    tbl = []
                    for line in result_final:
                        event = json.loads(line)
                        result = SchemaValidator.validate_amplitude_schema(event, schema)
                        tbl.extend(result) if len(result) > 0 else tbl.extend([[app, et, event['uuid'],
                                                                                event['server_upload_time'],
                                                                                event['platform'],
                                                                                str(datetime.utcnow()), None, None,
                                                                                None, None, None,
                                                                                'validated without errors'
                                                                                ]])

                    df = self.__build_data_frame(tbl)
                    self.__save_df_into_s3(df, et, json_file)
                    
                    _logger.info('m=validate_events_and_save_into_s3, msg=closing file')
                    result_obj.close()

    @logger(exclude='tbl')
    def __build_data_frame(self, tbl):
        return pd.DataFrame.from_records(tbl, columns=['app_id', 'event_type', 'uuid',
                                                       'server_upload_time', 'platform',
                                                       'validation_time', 'err_path',
                                                       'err_validator', 'err_validator_value',
                                                       'err_instance', 'err_details', 'validation_status'])

    @logger(exclude='df')
    def __save_df_into_s3(self, df, et, json_file):
        file_name_prefix = re.search('app=\d*/(.*)\.json\.gz', json_file)
        s3_key = 'clean/amplitude/event_errors/ym={0}/et={1}/{2}.parq'

        self.athena_client.create_parquet_from_df(
            key=s3_key.format(self.ym, et, file_name_prefix.groups(1)[0]),
            df=df,
            raw_columns=OrderedDict([
                ('app_id', str),
                ('event_type', str),
                ('uuid', str),
                ('server_upload_time', str),
                ('platform', str),
                ('validation_time', str),
                ('err_path', str),
                ('err_validator', str),
                ('err_validator_value', str),
                ('err_instance', str),
                ('err_details', str),
                ('validation_status', str)
            ])
        )

