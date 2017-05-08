import json
import os
import sys

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, 'vendor'))

import requests
import psycopg2


def dre_costs_last_update_date(event, context):
    cursor = connect_to_db()
    last_update_date = get_last_update_date(cursor)

    print 'posting to slack'
    response = requests.post(url='https://hooks.slack.com/services/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',
                             headers={'Content-type': 'application/json'},
                             data=json.dumps(
                                 {'text': 'Costs haven\'t been updated yet! Last update: *{}*'.format(
                                     last_update_date)}))

    if response.status_code != 200:
        print 'error: {}'.format(response.content)


def connect_to_db():
    print 'connecting to db'
    conn = psycopg2.connect(host=os.environ['DB_HOST'], user=os.environ['DB_USER'], password=os.environ['DB_PASSWORD'],
                            database=os.environ['DB_DATABASE'], port=os.environ['DB_PORT'])
    return conn.cursor()


def get_last_update_date(cursor):
    print 'executing select on files.costs_dre'
    cursor.execute('select max("Month")::date from files.costs_dre')
    return cursor.fetchone()[0]
