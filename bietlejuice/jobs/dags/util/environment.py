import base64
import json
import os
from datetime import datetime
from logging import info as log

import boto3
import pytz
from airflow.exceptions import AirflowException
from airflow.hooks.base_hook import BaseHook
from airflow.models import Variable


def __conn_to_json(conn):
    return json.dumps({
        'host': conn.host,
        'user': conn.login,
        'pwd': conn.get_password(),
        'db': conn.schema,
        'dbtype': conn.conn_type,
        'port': conn.port
    })


def __add_env(*keys):
    env = {}
    for key in keys:
        __set_env_var(env, key)

    return env


def __set_env_var(env, key):
    ex = None
    k = None
    try:
        env[key] = Variable.get(key)
    except KeyError as ex:
        try:
            k = BaseHook.get_connection(key)
            env["ENV_" + key] = __conn_to_json(k)
        except AirflowException as ex:
            k = None
    if not k:
        print ex


def __initialize_environment():
    return {
        "AWS_ACCESS_KEY_ID": Variable.get('AWS_ACCESS_KEY_ID'),
        "AWS_SECRET_ACCESS_KEY": Variable.get('AWS_SECRET_ACCESS_KEY'),
        "AWS_DEFAULT_REGION": Variable.get('AWS_DEFAULT_REGION')
    }


def get_airflow_env_var(key):
    _var = __add_env(key)[key]
    return _var.encode('utf-8') if _var is not None else None


def set_airflow_var_to_local_env(*keys):
    _vars = __add_env(*keys)
    for key in _vars:
        os.environ[key] = _vars[key]


def get_ecr_credentials(environment):
    registry = Variable.get('DOCKER_REGISTRY')
    ecr = boto3.client(
        'ecr',
        region_name=environment['AWS_DEFAULT_REGION'],
        aws_access_key_id=environment['AWS_ACCESS_KEY_ID'],
        aws_secret_access_key=environment['AWS_SECRET_ACCESS_KEY'],
    )
    user, pwd = base64.b64decode(ecr.get_authorization_token()['authorizationData'][0]['authorizationToken']).split(':')
    return registry, user, pwd


def docker_login(cli, user, pwd, registry):
    log('Trying to login...')
    log('Registry: {}'.format(user, pwd, registry))
    if cli:
        cli.login(username=user, password=pwd, registry='https://' + registry, reauth=True)
        log('Login succeeded...')


def convert_to_utc_schedule(cron_expression, tz=pytz.timezone('America/Sao_Paulo')):
    if cron_expression.startswith('timedelta'):
        return cron_expression
    sep = ' '
    exp = cron_expression.split(sep)
    local_now = datetime.now(tz)
    offset = local_now.utcoffset().total_seconds() / 60 / 60
    exp[1] = _change_digits(exp[1], offset)
    return sep.join(exp)


def _change_digits(hour_exp, offset):
    values = []
    number = ''
    p_char = ''
    for char in hour_exp:
        if char.isdigit():
            number += char
        else:
            _append_values(number, offset, values, p_char)
            values.append(char)
            number = ''
            p_char = char

    if number:
        if p_char != '/':
            _append_values(number, offset, values, p_char)
        else:
            values.append(number)

    return ''.join(values)


def _append_values(number, offset, values, p_char):
    if number.isdigit():
        n = int(number) - int(offset)  # hour
        if n > 23:
            if p_char == '-':
                if n > 24:
                    str_new_n = ',0-{}'.format(n - 23)
                else:
                    str_new_n = ',{}'.format(n - 24)
            else:
                str_new_n = ',{}'.format(n - 24)
            n = '23'
            values.append(n + str_new_n)
        else:
            values.append(str(n))
