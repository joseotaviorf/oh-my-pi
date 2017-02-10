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

import petl
import sys
import requests
from datetime import datetime
import json
import os
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

    for agent in agents_ids:
        try:
            ret = requests.get(service_endpoint.format(
                agent[0],
                datetime.today().strftime('%Y-%m-%d'))
            )

            content = json.loads(ret.content)
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

    table = petl.addfield(lines, 'timestamp', now)
    table = table.addrownumbers(field='row_number')
    return table


if __name__ == '__main__':
    service_endpoint = os.environ['SCHEDULING_PLANNER_ENDPOINT']

    print('START')

    agents_ids = get_agents_ids()

    table = get_table_agents_planner(agents_ids)

    BaseETL.bulk_insert(
        db_enum=EnumDb.BI_ODS,
        table=table,
        table_name='agents_schedule',
        append=False,
        encoding='UTF8'
    )

    print('END')
    sys.stdout.flush()
