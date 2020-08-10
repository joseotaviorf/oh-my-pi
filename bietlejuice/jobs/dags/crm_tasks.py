import locale
from datetime import datetime, timedelta

import pandas as pd
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from pymongo import MongoClient
from qa_python_utils import QuintoAndarLogger

env.set_airflow_var_to_local_env('BI_DW', 'BI_ODS', 'DATA_ACC_AWS_ACCESS_KEY_ID', 'DATA_ACC_AWS_SECRET_ACCESS_KEY')
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')
uri = env.get_airflow_env_var('MONGODB_CRM_URI')

MAIN_DAG_NAME = 'bi-crm-tasks'
MAIN_START_DATE = datetime(2018, 5, 15, 0, 0, 0)
MAIN_SCHEDULE_INTERVAL = '0 1 * * *'

logger = QuintoAndarLogger(MAIN_DAG_NAME)


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
        logger.error('m=parse_dt, msg=bad date dt={} type={} 1={} 2={} 3={} e={}'.format(dt, type(dt), dt[:28],
                                                                                         dt[29:31], dt[31:], e))
        return None


def cap_dt(dt):
    if dt is not None:
        if dt >= datetime.utcnow():
            return datetime.utcnow()
        else:
            return dt
    return None


def extract_tasks(_uri, id_column, task_types, dt=None):
    client = MongoClient(_uri)
    db = client.tasks
    conversion_columns = ['task_id', 'task_status', 'rep_id', 'first_rep_id', id_column, 'number_of_reschedules',
                          'dt_created', 'dt_closed', 'task_type']
    _filter = {
        "type": {"$in": task_types}
    }
    if dt is not None:
        _filter = {
            "type": {"$in": task_types},
            "dataInicio": {"$gte": dt}
        }

    projection = {
        "_id": 1,
        "assigneeId": 1,
        "origemId": 1,
        "dataInicio": 1,
        "realizadaEm": 1,
        "silenciadaAte": 1,
        "actions": 1,
        "type": 1
    }

    tasks = list()
    count = 0
    logger.info('m=extract_tasks, total_task={}'.format(db.tasks.find(_filter).count()))
    logger.info('m=extract_tasks, msg=listing tasks')

    for row in db.tasks.find(_filter, projection).batch_size(200):
        count += 1
        if count % 1000 == 0:
            logger.info('m=extract_tasks, total_loaded={}'.format(count))
        task_status = 'Open'
        if row['_id'] == '56d9a6b1544b0d22004af7b3':
            continue
        task_id = row['_id']
        rep_id = row.get('assigneeId', -1)
        origem_id = row.get('origemId', -1)
        number_of_reschedules = 0
        dt_created = row.get('dataInicio')
        t_type = row.get('type')
        dt_closed = None
        first_rep_id = None

        # status construction
        if 'silenciadaAte' in row:
            task_status = 'Rescheduled'
        if 'realizadaEm' in row:
            task_status = 'Closed'
            dt_closed = row['realizadaEm']

        for action in row['actions']:
            # resolved tasks do not have a specific time column, time must be found through actions
            if action['type'] == 'RESOLVE':
                task_status = 'Closed'
                dt_closed = action['date']
            if action['type'] == 'SNOOZE':
                number_of_reschedules += 1
            if action['type'] == 'UPDATE':
                if 'metadata' in action:
                    if 'key' in action['metadata']:
                        if action['metadata']['key'] == '/assigneeId':
                            if first_rep_id is None and 'oldValue' in action:
                                first_rep_id = action['metadata']['oldValue']

        if first_rep_id is None:
            first_rep_id = row.get('assigneeId', -1)

        task = {
            "task_id": task_id,
            "task_status": task_status,
            "rep_id": int(rep_id),
            id_column: origem_id,
            "number_of_reschedules": number_of_reschedules,
            "first_rep_id": int(first_rep_id),
            "dt_created": dt_created,
            "dt_closed": dt_closed,
            "task_type": t_type
        }
        tasks.append(task)

    if len(tasks) == 0:
        return None
    df = pd.DataFrame(tasks)
    df['dt_created'] = df['dt_created'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    df['dt_closed'] = df['dt_closed'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')

    return df.loc[:, conversion_columns]


def extract_manual_tasks(_uri, dt=None):
    client = MongoClient(_uri)
    db = client.tasks
    conversion_columns = ['id_task', 'id_task_opener', 'id_assignee', 'id_original_assignee', 'id_workgroup',
                          'task_done', 'description', 'subject', 'sk_date_created', 'dt_created', 'dt_reschedule',
                          'dt_closed']

    _filter = {
        "type": {"$in": ["Manual"]}
    }
    if dt is not None:
        _filter = {
            "type": {"$in": ["Manual"]},
            "dataInicio": {"$gte": dt}
        }

    projection = {
        "_id": 1,
        "dataInicio": 1,
        "realizadaEm": 1,
        "resolvida": 1,
        "assigneeId": 1,
        "metadata.workgroupId": 1,
        "metadata.assunto": 1,
        "metadata.descricao": 1,
        "metadata.assigneeId": 1,
        "silenciadaAte": 1,
        "openedById": 1
    }

    tasks = list()
    count = 0
    logger.info('m=extract_conversion_tasks, total_task={}'.format(db.tasks.find(_filter).count()))
    logger.info('m=extract_conversion_tasks, msg=listing tasks')
    for row in db.tasks.find(_filter, projection).batch_size(200):
        count += 1
        if count % 1000 == 0:
            logger.info('m=extract_conversion_tasks, total_loaded={}'.format(count))

        task_id = row['_id']
        assignee_id = row.get('assigneeId', -1)
        dt_created = row.get('dataInicio')
        task_done = row.get('resolvida')
        task_opener_id = row.get('openedById', None)
        workgroup_id = row['metadata'].get('workgroupId', None)
        original_assignee_id = row['metadata'].get('assigneeId', None)
        subject = row['metadata'].get('assunto', None)
        description = row['metadata'].get('descricao', None)
        dt_reschedule = row.get('silenciadaAte', None)
        dt_closed = row.get('realizadaEm', None)

        task = {
            "id_task": task_id,
            "id_task_opener": task_opener_id,
            "id_assignee": assignee_id,
            "id_original_assignee": original_assignee_id,
            "id_workgroup": workgroup_id,
            "task_done": task_done,
            "description": description,
            "subject": subject,
            "sk_date_created": dt_created,
            "dt_created": dt_created,
            "dt_reschedule": dt_reschedule,
            "dt_closed": dt_closed
        }
        tasks.append(task)

    if len(tasks) == 0:
        return None
    df = pd.DataFrame(tasks)
    df['id_task_opener'] = \
        pd.to_numeric(df['id_task_opener'], errors='coerce').where(pd.notnull(df['id_task_opener']), None)
    df['id_assignee'] = \
        pd.to_numeric(df['id_assignee'], errors='coerce').where(pd.notnull(df['id_assignee']), None)
    df['id_original_assignee'] = \
        pd.to_numeric(df['id_original_assignee'], errors='coerce').where(pd.notnull(df['id_original_assignee']), None)
    df['sk_date_created'] = df['dt_created'].apply(lambda x: x.strftime('%Y%m%d') if not pd.isnull(x) else '')
    df['dt_created'] = df['dt_created'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    df['dt_closed'] = df['dt_closed'].apply(lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    df['dt_reschedule'] = df['dt_reschedule'].apply(
        lambda x: x.strftime('%Y-%m-%d %H:%M:%S') if not pd.isnull(x) else '')
    df['description'] = df['description'].str[:250]
    df['subject'] = df['subject'].str[:250]
    return df.loc[:, conversion_columns]


def load_tasks(_uri, table_name, _bucket, id_column, task_types, schema_name='crm'):
    df = extract_tasks(_uri=_uri, id_column=id_column, task_types=task_types)
    logger.info('m=load_tasks, table_name={}, msg=start saving to db'.format(table_name))
    BaseETL.dataframe_to_db(
        df=df,
        enum_db=EnumDB.BI_ODS,
        table_name='{}.{}'.format(schema_name, table_name),
        encoding='utf-8',
        append=False,
        bucket_name='{}/raw/crm/{}'.format(_bucket, table_name)
    )
    logger.info('m=load_tasks, table_name={}, msg=saved to db'.format(table_name))


def load_manual_tasks(_uri, table_name, _bucket, schema_name='crm'):
    df = extract_manual_tasks(_uri=_uri)
    logger.info('m=load_manual_tasks, msg=start saving to db')
    BaseETL.dataframe_to_db(
        df=df,
        enum_db=EnumDB.BI_ODS,
        table_name='{}.{}'.format(schema_name, table_name),
        encoding='utf-8',
        append=False,
        bucket_name='{}/raw/crm/{}'.format(_bucket, table_name),
        int_columns=['id_task_opener', 'id_original_assignee', 'id_assignee']
    )
    logger.info('m=load_manual_tasks, msg=saved to db')


# create main DAG definition
main_dag = BaseDAG.build_dag(
    dag_id=MAIN_DAG_NAME,
    description='ETL for extracting CRM tasks',
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    catchup=False
)

lead_tasks = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_lead_tasks',
    python_callable=load_tasks,
    op_kwargs={'table_name': 'lead_tasks', '_uri': uri, 'schema_name': 'crm', '_bucket': bucket,
               'id_column': 'lead_id', 'task_types': ["ConverterLead", "ConverterLeadPrioritario"]}
)

manual_tasks = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_manual_tasks',
    python_callable=load_manual_tasks,
    op_kwargs={'table_name': 'manual_tasks', '_uri': uri, 'schema_name': 'crm', '_bucket': bucket}
)

photo_tasks = BaseDAG.build_python_operator(
    dag=main_dag,
    task_id='load_photo_tasks',
    python_callable=load_tasks,
    op_kwargs={'table_name': 'photo_tasks', '_uri': uri, 'schema_name': 'crm', '_bucket': bucket,
               'id_column': 'origin_id', 'task_types': ['FupFoto', 'AgendarJobDeFotografo']}
)

lead_tasks >> photo_tasks >> manual_tasks
