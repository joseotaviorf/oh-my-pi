import json
import os
import re
import sys
import types
from datetime import datetime, date, timedelta
from io import BytesIO, StringIO
from gzip import GzipFile

import boto3
import pandas as pd
from jsonschema import Draft4Validator
from tabulate import tabulate

#args = sys.argv
#args = [1]
#args[0] = '2017-10-01'
#dt = args[0]
#sys.argv = ['2017-10-10']
args = sys.argv
date = []
#date.append(datetime.strptime(args[0], '%Y-%m-%d').date())

date_start = datetime.strptime('13-11-17', '%d-%m-%y').date()
date_end = datetime.strptime('14-11-17', '%d-%m-%y').date()
date_delta = date_end - date_start

for d in range(date_delta.days + 1):
    date.append(date_start + timedelta(days=d))

#var_env = os.environ('airflow_amplitude_schema_validation')
var_env = {
    'apps': [
        {
            # Dev Supply
            '183049': [

                'landing_page_viewed',
                'onboarding_page_viewed',

                'listing_intent_clicked',
                'listing_intent_clicked',
                'addressauto_page_viewed',
                'addressdetails_page_viewed',
                'property_page_viewed',
                'condo_page_viewed',
                'price_page_viewed',
                'terms_page_viewed',
                'listing_terms_confirmed',

                'photo_intent_clicked',
                'photo_intent_clicked',
                'photo_intent_clicked',
                'photo_schedule_confirmed',

                'reminder_page_viewed',
                'photo_reminder_set',

                'homescreen_install_impression',
                'homescreen_install_confirmed'
            ]
        },
        {
            # Prod Supply
            # '183047': [
            #
            # ]
        }
    ]
}


class SchemaValidator(object):

    def validate_amplitude_schema(self, event_json, schema_json):

        dict_errors = []
        event = event_json
        schema = schema_json

        app_id = event['app']
        event_type = event['event_type']
        uuid = event['uuid']
        server_upload_time = (event['server_upload_time'])
        platform = event['platform']
        validation_time = datetime.utcnow()

        v = Draft4Validator(schema)
        for error in sorted(v.iter_errors(event), key=str):

            err_validator = ''
            err_validator_value = ''
            err_instance = ''
            err_detail = ''

            # error path
            if (len(list(error.path)) == 1):
                err_path = str(error.path[0])
            elif (len(list(error.path)) == 2):
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
                        if err_validator_value != '':
                            err_validator_value = err_validator_value + ', ' + str(field)
                        else:
                            err_validator_value = str(field)
                elif type(error.validator_value) == unicode:
                    err_validator_value = str(error.validator_value)
                else:
                    err_validator_value = json.dumps(error.validator_value)

                # error instance value (received value)
                if type(error.instance) in (dict, list):
                    for field, value in error.instance.iteritems():
                        if err_instance != '':
                            err_instance = err_instance + ', ' + str(field)
                        else:
                            err_instance = str(field)
                elif type(error.instance) == unicode:
                    err_instance = str(error.instance)
                else:
                    err_instance = json.dumps(error.instance)

                # set a custom detail for the error
                # if type(error.instance) == dict and error.validator == 'required':
                if error.validator == 'required':
                    for field in list(set(error.validator_value) - set(error.instance.keys())):
                        if err_detail != '':
                            err_detail = err_detail + ', ' + field
                        else:
                            err_detail = 'missing: ' + field

            dict_errors.append(
                [app_id, event_type, uuid, server_upload_time, platform,
                 validation_time, err_path, err_validator,
                 err_validator_value, err_instance, err_detail])

        return dict_errors



    def validate_events(self):

        s3c = boto3.client('s3')
        # s3r = boto3.resource('s3')
        bucket = '5a-datalake'

        ts_start = datetime.now()
        print '### Job started: {}'.format(ts_start)

        tbl = []

        for dt in date:
            for apps in var_env['apps']:
                for app, ets in apps.iteritems():
                    for et in ets:

                        # read list of files in s3 folder
                        response = s3c.list_objects_v2(
                            Bucket='5a-datalake',
                            Prefix='raw/amplitude/events/dt={}/et={}/app={}/'.format(dt, et, app)
                        )

                        # if no files found jdataLayer = [{ 'pageCategory': 'Statistics', 'visitorType': 'high-value' }]ump to next event
                        if response['KeyCount'] < 1:
                             continue

                        # set schema path and file
                        json_schema_path = 'schemas/{}/'.format(app)
                        json_schema_file = '{}.schema.json'.format(et)

                        cnt_evt = 0
                        cnt_err = 0

                        for key in response['Contents']:

                            json_file = key['Key']
                            tmp_path, tmp_file = os.path.split(json_file)

                            #print 'evt_nr {} - reading: {}'.format(cnt_evt, json_file)

                            obj = s3c.get_object(Bucket=bucket, Key=json_file)

                            byte_stream = BytesIO(obj['Body'].read())
                            result = GzipFile(None, 'rb', fileobj=byte_stream).read().decode('utf-8')

                            result_final = result.split('\n')
                            result_final = result_final[:-1] if result_final[len(result_final)-1] == '' else result_final

                            # event schema validation
                            with open(json_schema_path + json_schema_file) as json_schema:
                                schema = json.load(json_schema)

                            for line in result_final:

                                event = json.loads(line)
                                print event
                                tbl.extend(self.validate_amplitude_schema(event, schema))

        labels = ['app_id', 'event_type', 'uuid', 'server_upload_time', 'platform', 'validation_time',
                  'err_path', 'err_validator', 'err_validator_value', 'err_instance', 'err_details']

        df = pd.DataFrame.from_records(tbl, columns=labels)

        print ''
        print 'errors found:'
        print ''
        print tabulate(df.groupby(['app_id','event_type','platform','err_path','err_validator','err_validator_value','err_instance','err_details']).size().reset_index().rename(columns={0:'count'}), headers='keys', tablefmt='psql')

        df.to_csv('supply_errors.csv', index=False, encoding='utf-8')

        return df

                            # set schema path and file
                            # error_log_path = 'errors_supply/dt={}/et={}/app={}/'.format(dt, et, app)
                            # error_log_file = '{}_errors.csv'.format(tmp_file)
                            # if not os.path.exists(error_log_path):
                            #     os.makedirs(error_log_path)
                            # df.to_csv(error_log_path + error_log_file, mode='a', header=False, index=False, encoding='utf-8')

                            #csv_buffer = StringIO()
                            #df.to_csv(csv_buffer)
                            #s3r.Object(bucket, 'df.csv').put(Body=csv_buffer.getvalue())

                            # write files to s3 bucket
                            #s3_target_path = 'raw/amplitude/errors/dt={}/et={}/app={}/'.format(dt, et, app)
                            #s3r.Object(bucket, s3_target_path + error_log_file).put(Body=open(error_log_path + error_log_file, 'rb'))

                        # print ''
                        # print 'app: {} / event-type: {}'.format(app, et)
                        # print '{} jsons validated with {} errors, runtime: {}'.format(cnt_evt, cnt_err, datetime.now() - ts_start)
                        #
                        # print ''
                        # print ''

            #print '### {} processed. Total runtime: {}'.format(dt, (datetime.now() - ts_start))


