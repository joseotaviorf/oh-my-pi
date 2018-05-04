# -*- coding: latin1 -*-
import os
import petl
import json
from datetime import date, timedelta
from jobs.base.base_etl import BaseETL, EnumDb
from facebookads import FacebookAdsApi
from facebookads.adobjects.customaudience import CustomAudience


def create_audience(parent_act_id, name, description=''):
    audience = CustomAudience(parent_id=parent_act_id)
    audience[CustomAudience.Field.subtype] = CustomAudience.Subtype.custom
    audience[CustomAudience.Field.name] = name
    audience[CustomAudience.Field.description] = description
    return audience.remote_create()


def get_facebook_api():
    token_file = json.loads(os.environ['FACEBOOK_KEY'])
    my_app_id = token_file['my_app_id']
    my_app_secret = token_file['my_app_secret']
    my_access_token = token_file['my_access_token']
    return FacebookAdsApi.init(my_app_id, my_app_secret, my_access_token)


if __name__ == '__main__':
    result = BaseETL.from_db_query(EnumDb.QuintoAndar_ebdb, """
        SELECT DISTINCT
            mr.cidadeNome AS city,
            mr.nome AS region,
            u.email
            -- u.id
        FROM
            RespostaAutomatica ra
        LEFT JOIN
            Usuario u ON ra.usuario_id=u.id
        LEFT JOIN
            Imovel i ON ra.imovel_id=i.id
        LEFT JOIN
            MapRegiao mr ON i.regiao_id=mr.id
        LEFT JOIN
            Agendamento ag ON ra.usuario_id=ag.visitante_id AND ra.imovel_id=ag.imovel_id AND ag.tipo='Visita' AND ag.status!='Cancelado'
        WHERE
            ag.visitante_id IS NULL
            AND CONVERT_TZ(ra.recebidaEm, 'UTC', 'America/Sao_Paulo') >= DATE_SUB(CONVERT_TZ(CURRENT_DATE(),'UTC','America/Sao_Paulo'),INTERVAL 45 DAY)
            AND mr.nome IN
            (
                'Vila Carrão',
                'Bela Vista',
                'Moema',
                'Brooklin',
                'Pinheiros',
                'Jardim Paulista',
                'Consolação',
                'Tatuapé',
                'Santana',
                'Vila Mariana',
                'Centro'
            )
        ORDER BY
            1, 2
    """)

    table = petl.aggregate(result, key=('city', 'region'), aggregation=list, value=('email'))

    api = get_facebook_api()

    for line in table:
        if line != table[0]:
            dt = date.today() - timedelta(days=1)
            city = 'spo' if line[0].startswith('S') else 'cps'
            region = line[1]
            users = line[2]
            audience = create_audience(
                parent_act_id='act_994644903935458',
                name='{}_cf_{}_{}'.format(
                    dt.strftime('%Y%m%d'),
                    city,
                    region))
            audience.add_users(CustomAudience.Schema.email_hash, users)
