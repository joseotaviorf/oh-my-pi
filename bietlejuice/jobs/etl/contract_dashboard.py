import petl
import json
import os
import sys
import requests

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
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
    else:
        return None


def datetime_converter(dt):
    if isinstance(dt, datetime):
        return dt.strftime('%Y-%m-%d %H:%M:%S')
    else:
        return None


class ContractDashboard(object):

    @logger
    def __init__(self, exec_time, fetch_delta):
        self.exec_time = exec_time
        self.power_bi_endpoint = os.environ.get('PWBI_CONTRACT_ENDPOINT')
        self.mongodb_uri = os.environ.get('MONGODB_CRM_URI')
        self.fetch_dt = exec_time - timedelta(minutes=int(fetch_delta))
        self.num_daily_contracts = self.__get_daily_signed_contracts_number()
        self.monthly_signed_total = self.__get_monthly_signed_contracts_number()

    @logger
    def __get_new_signature_tasks(self, imovel_id_list):
        signature_tasks = []
        header = ['imovel_id', 'agent_id', 'tenant', 'tenant_id', 'dt_done']
        signature_tasks.append(header)
        client = MongoClient(self.mongodb_uri)
        db = client.tasks
        for row in db.tasks.find({
                                    "realizadaEm": {"$gte": self.fetch_dt},
                                    "type": "FollowUpAssinaturas",
                                    "metadata.imovelId": {"$in": imovel_id_list}
                                }):
            task = list()
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
            query='''
            select 
                imovel_id, dataAssinado
            from Contrato 
            where 
                CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo') >= CONVERT_TZ('{0}','UTC','America/Sao_Paulo')
            AND 
                CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo') <= CONVERT_TZ('{1}','UTC','America/Sao_Paulo')
            and status IN ('Ativo', 'Finalizado')'''.format(self.fetch_dt, self.exec_time))
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
                    where 
                        year(
                            DATE(CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo'))
                        ) = year(DATE(CONVERT_TZ('{0}','UTC','America/Sao_Paulo')))
                    and 
                        month(
                            DATE(CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo'))
                        ) = month(DATE(CONVERT_TZ('{0}','UTC','America/Sao_Paulo')))
                    and 
                        DATE(
                            CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo')
                        ) <= DATE(CONVERT_TZ('{0}','UTC','America/Sao_Paulo'))
                    and status IN ('Ativo', 'Finalizado')'''.format(self.exec_time))
        return table[1][0]

    @logger
    def __get_daily_signed_contracts_number(self):
        # We don't convert dataAssinado to BR timezone because we are querying with UTC
        table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query='''select 
                            count(imovel_id) as total
                            from Contrato
                        where
                            DATE(
                                CONVERT_TZ(dataAssinado,'UTC','America/Sao_Paulo')
                            ) = DATE(CONVERT_TZ('{0}','UTC','America/Sao_Paulo'))
                        and status IN ('Ativo', 'Finalizado')'''.format(self.exec_time))
        return table[1][0]

    @logger
    def __prepare_pwbi_payload(self, data):

        prepared_data = []
        for index, contract in data.iterrows():
            payload = dict()
            payload['monthly_contracts'] = self.monthly_signed_total
            payload['daily_contracts'] = self.num_daily_contracts
            payload['imovel_id'] = str(contract['imovel_id'])
            payload['tenant'] = contract['tenant']
            payload['tenant_id'] = str(contract['tenant_id'])
            payload['agent'] = str(contract['agent'])
            payload['agent_id'] = str(contract['agent_id'])
            payload['dt_done'] = datetime_converter(fix_timezone(contract['dt_done']))
            payload['dt_run'] = datetime_converter(fix_timezone(self.exec_time))
            payload['dt_signature'] = datetime_converter(fix_timezone(contract['dataAssinado']))
            prepared_data.append(payload)
            print payload
        print len(prepared_data)
        return json.dumps(prepared_data)

    # @logger
    def get_new_data(self):
        signed_contracts = map(lambda x: [x[0], x[1]], self.__get_new_signed_contracts())
        imovel_id_list = list(petl.values(signed_contracts, 'imovel_id'))
        if len(imovel_id_list) > 0:
            sign_tasks = self.__get_new_signature_tasks(imovel_id_list)
            assignee_id_list = list(petl.values(sign_tasks, 'agent_id'))
            assignee_names = self.__get_assignee_names_from_id(assignee_id_list)

            sign_tasks = petl.leftjoin(sign_tasks, assignee_names, key='agent_id')

            signed_contracts = petl.leftjoin(
                                    signed_contracts,
                                    sign_tasks,
                                    key='imovel_id'
                                )
            return petl.todataframe(signed_contracts)
        else:
            return None

    @logger
    def push_updated_data(self, new_data):
        payload = self.__prepare_pwbi_payload(new_data)
        resp = requests.post(self.power_bi_endpoint, payload, timeout=30)
        return resp


if __name__ == '__main__':
    _logger.info('m=__main__, msg=starting execution fetch={0} run={1}'.format(fetch_timedelta, run_time))
    contract_dashboard = ContractDashboard(run_time, fetch_timedelta)
    updated_data = contract_dashboard.get_new_data()
    if updated_data is not None:
        resp = contract_dashboard.push_updated_data(updated_data)
        _logger.info('m=__main__, msg=pwbi response {}'.format(resp))
    else:
        _logger.info('m=__main__, msg=no new contracts')