import petl
import json
import os
import sys
import requests

from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from pymongo import MongoClient
from datetime import datetime, timedelta
from pytz import UTC, timezone
from qa_python_utils.default_logger import logger, _logger

args = sys.argv
run_time = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S')
# contracts signed within (run_time - fetch_timedelta) will be pushed
fetch_timedelta = args[1]


def fix_timezone(dt):
    if isinstance(dt, datetime):
        return dt.replace(tzinfo=UTC).astimezone(timezone('America/Sao_Paulo'))


def datetime_converter(dt):
    if isinstance(dt, datetime):
        return dt.strftime('%Y-%m-%d %H:%M:%S')


class ContractDashboard(object):

    @logger
    def __init__(self, exec_time, fetch_delta):
        self.exec_time = exec_time
        self.fixed_exec_time = fix_timezone(self.exec_time).strftime('%Y-%m-%d %H:%M:%S')
        self.power_bi_endpoint = os.environ.get('PWBI_CONTRACT_ENDPOINT')
        self.mongodb_uri = os.environ.get('MONGODB_CRM_URI')
        self.fetch_dt = exec_time - timedelta(minutes=int(fetch_delta))
        print self.exec_time
        print self.fetch_dt
        self.num_daily_contracts = 0

    @logger
    def __get_new_signature_tasks(self):
        signature_tasks = []
        header = ['imovel_id', 'agent_id', 'tenant', 'tenant_id', 'dt_done']
        signature_tasks.append(header)
        client = MongoClient(self.mongodb_uri)
        db = client.tasks
        for row in db.tasks.find({"realizadaEm": {"$gte": self.fetch_dt, "$lt": self.exec_time}, "type": "FollowUpAssinaturas", "resolvida": True}):
            task = list()
            print row['realizadaEm']
            task.append(row['metadata']['imovelId'])
            task.append(row['assigneeId'])
            task.append(row['metadata']['inquilino']['nome'].encode('utf-8'))
            task.append(row['metadata']['inquilino']['id'])
            task.append(row['realizadaEm'])
            signature_tasks.append(task)
        return signature_tasks

    @logger
    def __get_new_signed_contracts(self):
        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='''select 
                        imovel_id
                    from Contrato 
                    where date(DATE(dataAssinado)) = date('{}')
                    and status IN ('Ativo', 'Finalizado')'''.format(self.exec_time))
        # save the number of contracts for later use
        self.num_daily_contracts = len(petl.values(table, 'imovel_id'))
        return table

    @logger
    def __get_assignee_names_from_id(self, id_list):
        concat_list = ','.join(map(str, id_list))
        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='select id as agent_id, nome as agent from Usuario where id in ({})'.format(concat_list))
        return table

    @logger
    def __get_monthly_signed_contracts_number(self):
        # We don't convert dataAssinado to BR timezone because we are querying with UTC
        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='''select 
                        count(imovel_id) as total
                        from Contrato
                    where year(DATE(dataAssinado)) = year(date('{0}'))
                    and month(DATE(dataAssinado)) = month(date('{0}'))
                    and status IN ('Ativo', 'Finalizado')'''.format(self.exec_time))
        return table[1][0]

    @logger
    def __prepare_pwbi_payload(self, data):

        monthly_signed_total = self.__get_monthly_signed_contracts_number()
        prepared_data = []
        for index, contract in data.iterrows():
            payload = dict()
            payload['monthly_contracts'] = monthly_signed_total
            payload['daily_contracts'] = self.num_daily_contracts
            payload['imovel_id'] = str(contract['imovel_id'])
            payload['tenant'] = contract['tenant']
            payload['tenant_id'] = str(contract['tenant_id'])
            payload['agent'] = str(contract['agent'])
            payload['agent_id'] = str(contract['agent_id'])
            payload['dt_done'] = datetime_converter(fix_timezone(contract['dt_done']))
            payload['dt_run'] = self.fixed_exec_time
            prepared_data.append(payload)
            print payload
        return json.dumps(prepared_data)

    # @logger
    def get_new_data(self):
        sign_tasks = self.__get_new_signature_tasks()
        assignee_id_list = list(petl.values(sign_tasks, 'agent_id'))
        assignee_names = self.__get_assignee_names_from_id(assignee_id_list)

        sign_tasks = petl.leftjoin(sign_tasks, assignee_names, key='agent_id')
        signed_contracts = list(petl.values(self.__get_new_signed_contracts(), 'imovel_id'))
        signed_contracts = list([['imovel_id']]) + map(lambda x: [x], signed_contracts)

        signed_contracts = petl.rightjoin(
                                signed_contracts,
                                sign_tasks,
                                key='imovel_id'
                            )

        return petl.todataframe(signed_contracts)

    @logger
    def push_updated_data(self, new_data):
        payload = self.__prepare_pwbi_payload(new_data)
        resp = requests.post(self.power_bi_endpoint, payload, timeout=30)
        return resp


if __name__ == '__main__':
    _logger.info('m=__main__, msg=starting execution fetch={0} run={1}'.format(fetch_timedelta, run_time))
    contract_dashboard = ContractDashboard(run_time, fetch_timedelta)
    updated_data = contract_dashboard.get_new_data()
    resp = contract_dashboard.push_updated_data(updated_data)
    _logger.info('m=__main__, msg=pwbi response {}'.format(resp))
