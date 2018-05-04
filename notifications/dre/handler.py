import json
import os
import sys
from base64 import b64decode
from datetime import datetime

import boto3
import dateutil.relativedelta
import psycopg2
import requests

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, 'vendor'))


def dre_costs_last_update_date(event, context):
    cursor = connect_to_db()
    last_update_date = get_last_update_date(cursor)
    if not last_update_date:
        return

    dt = datetime.today().replace(hour=0, minute=0, second=0, microsecond=0, day=1)
    dt_2months = dt.date() - dateutil.relativedelta.relativedelta(months=2)

    if last_update_date >= dt_2months:
        return

    print 'posting to slack'
    response = requests.post(url='https://hooks.slack.com/services/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',
                             headers={'Content-type': 'application/json'},
                             data=json.dumps(
                                 {'text': 'Costs haven\'t been updated yet! Last update: *{}*'.format(
                                     last_update_date)}))

    if response.status_code != 200:
        print 'error sending notification to slack: {}'.format(response.content)


def connect_to_db():
    db_host = decrypt_variable(os.environ['DB_HOST'])
    db_user = decrypt_variable(os.environ['DB_USER'])
    db_password = decrypt_variable(os.environ['DB_PASSWORD'])
    db_database = decrypt_variable(os.environ['DB_DATABASE'])
    db_port = decrypt_variable(os.environ['DB_PORT'])

    print 'connecting to db'
    conn = psycopg2.connect(host=db_host, user=db_user, password=db_password, database=db_database, port=db_port)
    return conn.cursor()


def get_last_update_date(cursor):
    print 'executing select on files.costs_dre'
    cursor.execute("""
                    select max("Month") :: DATE
                    from files.costs_dre
                   """)

    result = cursor.fetchone()
    return None if not result else result[0]


def decrypt_variable(var):
    return boto3.client('kms').decrypt(CiphertextBlob=b64decode(var))['Plaintext']
