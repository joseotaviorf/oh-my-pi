import locale

import pandas as pd
from datetime import datetime, timedelta
from pymongo import MongoClient

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.dags.util import environment as env
from qa_python_utils.default_logger import _logger

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_NAME = 'bi-crm-leads-conversion'
MAIN_START_DATE = datetime(2018, 5, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 4 * * *'


def parse_dt(dt):
    fmt1 = '%Y-%m-%dT%H:%M:%S'
    fmt2 = '%b %d %Y %H:%M:%S'

    _dt = None
    try:
        _dt = (datetime.strptime(dt[:19], fmt1) +
               timedelta(hours=int(dt[20:22]), minutes=int(dt[23:])) * (-1 if dt[19] == '+' else 1))
        return _dt
    except ValueError:
        _dt = None

    try:
        locale.setlocale(locale.LC_ALL, 'en_US.UTF-8')
        _dt = (datetime.strptime(dt[4:24], fmt2) +
               timedelta(hours=int(dt[29:31]), minutes=int(dt[31:])) * (-1 if dt[28] == '+' else 1))
        locale.setlocale(locale.LC_ALL, '')
        return _dt
    except ValueError as e:
        _logger.error('m=parse_dt, msg=bad date dt={} type={} 1={} 2={} 3={} e={}'.format(dt, type(dt), dt[:28],
                                                                                          dt[29:31], dt[31:], e))
        return None


def cap_dt(dt):
    if dt is not None:
        if dt >= datetime.utcnow():
            return datetime.utcnow()
        else:
            return dt
    return None


def extract_conversion_tasks(_uri, dt=None):
    client = MongoClient(_uri)
    db = client.tasks
    conversion_columns = ['task_id', 'task_status', 'rep_id', 'lead_id', 'number_of_reschedules',
                          'total_reschedule_time_hours', 'dt_created', 'dt_closed']
    _filter = {
        "type": {"$in": ["ConverterLead", "ConverterLeadPrioritario"]}
    }
    if dt is not None:
        _filter = {
            "type": {"$in": ["ConverterLead", "ConverterLeadPrioritario"]},
            "dataInicio": {"$gte": dt}
        }

    projection = {
        "_id": 1,
        "assigneeId": 1,
        "origemId": 1,
        "dataInicio": 1,
        "realizadaEm": 1,
        "silenciadaAte": 1,
        "actions": 1
    }

    tasks = list()
    count = 0
    _logger.info('m=extract_conversion_tasks, total_task={}'.format(db.tasks.find(_filter).count()))
    _logger.info('m=extract_conversion_tasks, msg=listing tasks')
    for row in db.tasks.find(_filter, projection).batch_size(200):
        count += 1
        if count % 1000 == 0:
            _logger.info('m=extract_conversion_tasks, total_loaded={}'.format(count))
        task_status = 'Open'
        task_id = row['_id']
        rep_id = row['assigneeId']
        lead_id = row['origemId']
        number_of_reschedules = 0
        total_reschedule_time_hours = 0
        dt_created = row['dataInicio']
        dt_closed = None

        if 'silenciadaAte' in row:
            task_status = 'Rescheduled'
        if 'realizadaEm' in row:
            task_status = 'Closed'
            dt_closed = row['realizadaEm']
        for action in row['actions']:
            _metadata = None
            _date = None
            if 'metadata' in action:
                _metadata = action['metadata']
            if 'date' in action:
                _date = action['date']

            if action['type'] == 'SNOOZE':
                number_of_reschedules += 1
                if cap_dt(parse_dt(_metadata)) is not None:
                    total_reschedule_time_hours += round((cap_dt(parse_dt(_metadata)) - _date).total_seconds() / 3600.,
                                                         2)

        task = {
            "task_id": task_id,
            "task_status": task_status,
            "rep_id": rep_id,
            "lead_id": lead_id,
            "number_of_reschedules": number_of_reschedules,
            "total_reschedule_time_hours": total_reschedule_time_hours,
            "dt_created": dt_created,
            "dt_closed": dt_closed
        }
        tasks.append(task)

    df = pd.DataFrame(tasks)
    df['dt_created'] = df['dt_created'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    df['dt_closed'] = df['dt_closed'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    return df.loc[:, conversion_columns]


def load_conversion_tasks(_uri, table_name, schema_name='crm'):
    df = extract_conversion_tasks(_uri=_uri)
    _logger.info('m=load_conversion_tasks, msg=start saving to db')
    BaseETL.dataframe_to_db(df=df, enum_db=EnumDb.BI_ODS, table_name='{}.{}'.format(schema_name, table_name),
                            encoding='utf-8', append=False)
    _logger.info('m=load_conversion_tasks, msg=saved to db')


# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL for extracting inside sales tasks',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL
)

fact_demand = BaseDAG.get_quintoandar_python_operator(
    dag=main_dag,
    task_id='load_conversion_tasks',
    func_command=load_conversion_tasks,
    op_kwargs={'table_name': 'lead_tasks', '_uri': uri, 'schema_name': 'crm'}
)
