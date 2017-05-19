# http://planner.quintoandar.com.br/schedules/bi/agent/137792/availability/2017-02-09

# DISPONIVEL:
# Available,
# AgentHasAppointment,
# InsufficientTimeWindow,
# InTransit,
# BestAvailable
#
# INDISPONIVEL:
# UnavailableAgent,
# UnavailableProperty
#
# UNKNOWN:
# TooShortNotice

import json
import os
import sys
from datetime import datetime

import petl
import requests
from jobs.base.base_etl import BaseETL, EnumDb


def get_agents_ids():
    agents = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query="""select
                  u.id,
                  da.ativo
                from
                  Usuario u
                inner join
                  DadosAgente da
                  on da.id = u.dadosAgente_id
                where
                  da.ativo;"""
    )[1:]
    return agents  # [137792]


def get_table_agents_planner(agents_ids):
    lines = [['agent_user_id', 'available_date', 'region_id', 'region_name',
              'slot_id', 'slot_start', 'slot_end', 'slot_available', 'slot_status']]
    now = datetime.utcnow()

    agents_list = []
    for agent in agents_ids:
        try:
            ret = requests.get(service_endpoint.format(
                agent[0],
                datetime.today().strftime('%Y-%m-%d'))
            )

            content = json.loads(ret.content)
            if not content:
                agents_list.append(agent[0])

            agent_user_id = content['agentId']
            available_date = content['availabilityDate']
            region_id = region_name = slot_id = slot_start = slot_end = slot_available = slot_status = None
            if content['regions']:
                for region in content['regions']:
                    region_id = region['regionId']
                    region_name = region['name']
                    if region['slots']:
                        for slot in region['slots']:
                            slot_id = slot['id']
                            slot_start = slot['start']
                            slot_end = slot['end']
                            slot_available = slot['available']
                            slot_status = slot['status']
                            lines.append([agent_user_id, available_date, region_id, region_name,
                                          slot_id, slot_start, slot_end, slot_available, slot_status])
                    else:
                        lines.append([agent_user_id, available_date, region_id, region_name,
                                      slot_id, slot_start, slot_end, slot_available, slot_status])
            else:
                lines.append([agent_user_id, available_date, region_id, region_name,
                              slot_id, slot_start, slot_end, slot_available, slot_status])

        except Exception as ex:
            print 'Error: {} - Agent: {}'.format(ex, agent[0])

    if agents_list:
        send_notification_to_slack(agents_list)

    table = petl.addfield(lines, 'timestamp', now)
    table = table.addrownumbers(field='row_number')
    return table


def send_notification_to_slack(agents_list):
    print 'posting notification to slack'
    response = requests.post(url='https://hooks.slack.com/services/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',
                             headers={'Content-type': 'application/json'},
                             data=json.dumps(
                                 {'text': 'Some agents have errors in their schedules! *IDs={}*'.format(agents_list)}))

    if response.status_code != 200:
        print 'error sending agents ids to slack: {}'.format(response.content)


if __name__ == '__main__':
    process_name = BaseETL.get_current_filename()
    service_endpoint = os.environ['SCHEDULING_PLANNER_ENDPOINT']
    bucket_datalake = os.environ['bi-datalake-s3-bucket']


    print('START')

    agents_ids = get_agents_ids()

    table = get_table_agents_planner(agents_ids)

    BaseETL.bulk_insert(
        db_enum=EnumDb.BI_ODS,
        table=table,
        table_name='agents_schedule',
        append=True,
        encoding='UTF8',
        bucket_name='{}/raw/ebdb/{}'.format(bucket_datalake, process_name)
    )

    BaseETL.copy_file_between_s3_buckets(
        bucket_source=bucket_datalake,
        bucket_destination=bucket_datalake,
        full_filename_source='raw/ebdb/{0}/{0}.csv'.format(process_name),
        full_filename_dest='clean/ebdb/{0}/{0}.csv'.format(process_name)
    )

    print('END')
    sys.stdout.flush()
