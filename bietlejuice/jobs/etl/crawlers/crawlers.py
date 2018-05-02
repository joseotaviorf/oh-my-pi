import logging
import os
import sys
from collections import OrderedDict
from datetime import datetime

import requests
from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

args = sys.argv
today = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S').date()

bucket_datalake = os.environ['bi-datalake-s3-bucket']
tmp_dir = '/tmp'


class Crawlers(object):
    def __init__(self):
        self.athena_client = AthenaClient(bucket_datalake)

    def fill_neighs_cities_from_google(self, df_crawlers, df_neighs_cities):
        gmaps_url_prefix = 'https://maps.googleapis.com/maps/api/geocode/json?address={}'
        count_full = count_real = 0

        for row in df_neighs_cities.iterrows():
            count_full += 1
            if row[1].lat and row[1].lng and float(row[1].lat) != 0 and float(row[1].lng) != 0:
                float_lat = float(row[1].lat)
                float_lng = float(row[1].lng)
                lat = -float_lat if float_lat > 0 else float_lat
                lng = -float_lng if float_lng > 0 else float_lng
                gmaps_url = gmaps_url_prefix.format('{},{}'.format(lat, lng))
            else:
                gmaps_url = gmaps_url_prefix.format(row[1].cep)

            full_response = requests.get(url=gmaps_url)
            if full_response.status_code != 200:
                _logger.warn(
                    'm=fill_neighs_cities_from_google, status_code={}, gmaps_url={}'.format(full_response.status_code,
                                                                                            gmaps_url))
                continue

            gmaps_response = full_response.json()['results']
            if len(gmaps_response) == 0 \
                    or 'address_components' not in gmaps_response[0] \
                    or len(gmaps_response[0]['address_components']) == 0:
                if row[1].lat and row[1].lng and row[1].lat != 0 and row[1].lng != 0 and row[1].cep:
                    gmaps_url = gmaps_url_prefix.format(row[1].cep)
                    full_response = requests.get(url=gmaps_url)
                    if full_response.status_code != 200:
                        _logger.warn(
                            'm=fill_neighs_cities_from_google, status_code={}, gmaps_url={}'.format(
                                full_response.status_code,
                                gmaps_url))
                        continue

                    gmaps_response = full_response.json()['results']
                    if len(gmaps_response) == 0 \
                            or 'address_components' not in gmaps_response[0] \
                            or len(gmaps_response[0]['address_components']) == 0:
                        continue
                else:
                    continue

            new_neighborhood, new_city = None, None
            for comp in gmaps_response[0]['address_components']:
                if 'types' not in comp:
                    continue

                if 'political' in comp['types'] and 'sublocality' in comp['types']:
                    new_neighborhood = comp['long_name']

                if 'political' in comp['types'] and 'locality' in comp['types']:
                    new_city = comp['long_name']

                if new_neighborhood and new_city:
                    break

            if new_neighborhood and new_city:
                df_crawlers.loc[
                    (df_crawlers.cep == row[1].cep) |
                    ((df_crawlers.lat == row[1].lat) & (df_crawlers.lng == row[1].lng)), ['neighborhood', 'city']] = \
                    [new_neighborhood, new_city]
                count_real += 1

        _logger.info('m=fill_neighs_cities_from_google, count_full={}, count_real={}'.format(count_full, count_real))
        return df_crawlers

    def transform_data(self):
        _logger.info('m=transform_data')
        self.athena_client.msck_repair_table(
            database='datalake_raw',
            table_name='crawlers'
        )

        query_crawlers = './bietlejuice/db/2.datalake/queries/crawlers/transform_raw.sql'
        df_crawlers = self.athena_client.execute_file_query_and_return_dataframe(query_crawlers, today)

        neighs_cities_query = './bietlejuice/db/2.datalake/queries/crawlers/neighs_cities.sql'
        df_neighs_cities = self.athena_client.execute_file_query_and_return_dataframe(neighs_cities_query, today)

        df_crawlers = self.fill_neighs_cities_from_google(df_crawlers=df_crawlers, df_neighs_cities=df_neighs_cities)
        self.athena_client.create_parquet_from_df(
            key='clean/{0}/started_on={1}/{0}.parq'.format('external_property', today),
            df=df_crawlers,
            raw_columns=OrderedDict([
                ('id', long),
                ('website', str),
                ('url', str),
                ('http_status', int),
                ('started_on', str),
                ('updated_on', str),
                ('business', str),
                ('type', str),
                ('advertiser_name', str),
                ('advertiser_type', str),
                ('primary_phone_number', str),
                ('secondary_phone_number', str),
                ('price', float),
                ('rent', float),
                ('condominium', float),
                ('iptu', float),
                ('total_area', float),
                ('useful_area', float),
                ('bedrooms', int),
                ('suites', int),
                ('toilets', int),
                ('garages', int),
                ('photos', str),
                ('description', str),
                ('year_building', float),
                ('unit_features', str),
                ('common_features', str),
                ('complementary_info', str),
                ('cep', str),
                ('lat', float),
                ('lng', float),
                ('street', str),
                ('neighborhood', str),
                ('city', str),
                ('state', str),
                ('crawl_timestamp', float)
            ]),
            clean_columns=OrderedDict([
                ('id', long),
                ('website', str),
                ('url', str),
                ('http_status', int),
                ('started_on', str),
                ('updated_on', str),
                ('business', str),
                ('type', str),
                ('advertiser_name', str),
                ('advertiser_type', str),
                ('primary_phone_number', str),
                ('secondary_phone_number', str),
                ('price', float),
                ('rent', float),
                ('condominium', float),
                ('iptu', float),
                ('total_area', float),
                ('useful_area', float),
                ('bedrooms', int),
                ('suites', int),
                ('toilets', int),
                ('garages', int),
                ('photos', str),
                ('description', str),
                ('year_building', int),
                ('unit_features', str),
                ('common_features', str),
                ('complementary_info', str),
                ('cep', str),
                ('lat', float),
                ('lng', float),
                ('street', str),
                ('neighborhood', str),
                ('city', str),
                ('state', str),
                ('crawl_timestamp', float)
            ])
        )

        self.athena_client.msck_repair_table(
            database='datalake_clean',
            table_name='external_property'
        )

    def load_dim_external_property(self):
        _logger.info('m=load_dim_external_property, msg=cleaning dim_external_property at {}'.format(today))
        BaseETL.execute_command(
            command="""delete from dim_external_property where start_date = '{0}'""".format(today),
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            commit=True
        )

        _logger.info('m=load_dim_external_property, msg=updating end_date columns in dim_external_property')
        BaseETL.execute_command(
            command="""update dim_external_property set end_date = '{0}' where sk_external_property in (
                          select
                            dep.sk_external_property
                            from datalake_clean.external_property cr
                              right join dim_external_property dep
                                on cr.id = dep.id and cr.website = dep.source and cr.business = dep.business
                                   and (
                                     (coalesce(cr.price, 0) != coalesce(dep.price, 0))
                                     or (coalesce(cr.type, '') != coalesce(dep.type, ''))
                                     or (coalesce(cr.primary_phone_number, '') != coalesce(dep.primary_phone_number, ''))
                                     or (coalesce(cr.secondary_phone_number, '') != coalesce(dep.secondary_phone_number, ''))
                                     or (coalesce(cr.rent, 0) != coalesce(dep.rent, 0))
                                     or (coalesce(cr.condominium, 0) != coalesce(dep.condominium, 0))
                                     or (coalesce(left(cr.iptu, 12)::numeric(14,2), 0) != coalesce(left(dep.iptu, 12)::numeric(14,2), 0))
                                     or (coalesce(cr.total_area, 0) != coalesce(dep.total_area, 0))
                                     or (coalesce(cr.useful_area, 0) != coalesce(dep.useful_area, 0))
                                     or (coalesce(cr.bedrooms, 0) != coalesce(dep.bedrooms, 0))
                                     or (coalesce(cr.suites, 0) != coalesce(dep.suites, 0))
                                     or (coalesce(cr.toilets, 0) != coalesce(dep.toilets, 0))
                                     or (coalesce(cr.garages, 0) != coalesce(dep.garages, 0))
                                     or (coalesce(cr.year_building, 0) != coalesce(dep.year_building, 0))
                                     or (coalesce(cr.cep, '') != coalesce(dep.cep, ''))
                                     or (coalesce(trunc(cr.lat, 5), 0) != coalesce(trunc(dep.lat, 5), 0))
                                     or (coalesce(trunc(cr.lng, 5), 0) != coalesce(trunc(dep.lng, 5), 0))
                                     or (coalesce(cr.street, '') != coalesce(dep.street, ''))
                                     or (coalesce(cr.neighborhood, '') != coalesce(dep.neighborhood, ''))
                                     or (coalesce(cr.city, '') != coalesce(dep.city, ''))
                                     or (coalesce(cr.state, '') != coalesce(dep.state, ''))
                                   )
                            where dep.end_date is null
                              and dep.start_date < '{0}'
                              and cr.started_on = '{0}'
                      ) and end_date is null and start_date < '{0}'""".format(today),
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            commit=True
        )

        _logger.info('m=load_dim_external_property, msg=inserting into dim_external_property')
        insert_table = BaseETL.from_db_query(
            db_enum=EnumDb.BI_DW,
            query="""with entries_not_changed as  (
                        select dep.id
                        from dim_external_property dep
                        join datalake_clean.external_property cr
                        on cr.id = dep.id
                          and cr.website = dep.source
                          and cr.business = dep.business
                          and cr.type = dep.type
                          and (coalesce(cr.primary_phone_number, '') = coalesce(dep.primary_phone_number, ''))
                          and (coalesce(cr.secondary_phone_number, '') = coalesce(dep.secondary_phone_number, ''))
                          and (coalesce(cr.price, 0) = coalesce(dep.price, 0))
                          and (coalesce(cr.rent, 0) = coalesce(dep.rent, 0))
                          and (coalesce(cr.condominium, 0) = coalesce(dep.condominium, 0))
                          and (coalesce(left(cr.iptu, 12)::numeric(14,2), 0) = coalesce(left(dep.iptu, 12)::numeric(14,2), 0))
                          and (coalesce(cr.total_area, 0) = coalesce(dep.total_area, 0))
                          and (coalesce(cr.useful_area, 0) = coalesce(dep.useful_area, 0))
                          and (coalesce(cr.bedrooms, 0) = coalesce(dep.bedrooms, 0))
                          and (coalesce(cr.suites, 0) = coalesce(dep.suites, 0))
                          and (coalesce(cr.toilets, 0) = coalesce(dep.toilets, 0))
                          and (coalesce(cr.garages, 0) = coalesce(dep.garages, 0))
                          and (coalesce(cr.year_building, 0) = coalesce(dep.year_building, 0))
                          and (coalesce(cr.cep, '') = coalesce(dep.cep, ''))
                          and (coalesce(trunc(cr.lat, 5), 0) = coalesce(trunc(dep.lat, 5), 0))
                          and (coalesce(trunc(cr.lng, 5), 0) = coalesce(trunc(dep.lng, 5), 0))
                          and (coalesce(cr.street, '') = coalesce(dep.street, ''))
                          and (coalesce(cr.neighborhood, '') = coalesce(dep.neighborhood, ''))
                          and (coalesce(cr.city, '') = coalesce(dep.city, ''))
                          and (coalesce(cr.state, '') = coalesce(dep.state, ''))
                        where cr.started_on = '{0}'
                          and dep.end_date is null
                    ),
                    entries_changed as (
                        select dep.id, dep.source, right(sk_external_property, 3) as version
                        from dim_external_property dep
                        join datalake_clean.external_property cr
                        on cr.id = dep.id and cr.website = dep.source
                           and (
                             (coalesce(cr.business, '') != coalesce(dep.business, ''))
                             or (coalesce(cr.type, '') != coalesce(dep.type, ''))
                             or (coalesce(cr.primary_phone_number, '') != coalesce(dep.primary_phone_number, ''))
                             or (coalesce(cr.secondary_phone_number, '') != coalesce(dep.secondary_phone_number, ''))
                             or (coalesce(cr.price, 0) != coalesce(dep.price, 0))
                             or (coalesce(cr.rent, 0) != coalesce(dep.rent, 0))
                             or (coalesce(cr.condominium, 0) != coalesce(dep.condominium, 0))
                             or (coalesce(left(cr.iptu, 12)::numeric(14,2), 0) != coalesce(left(dep.iptu, 12)::numeric(14,2), 0))
                             or (coalesce(cr.total_area, 0) != coalesce(dep.total_area, 0))
                             or (coalesce(cr.useful_area, 0) != coalesce(dep.useful_area, 0))
                             or (coalesce(cr.bedrooms, 0) != coalesce(dep.bedrooms, 0))
                             or (coalesce(cr.suites, 0) != coalesce(dep.suites, 0))
                             or (coalesce(cr.toilets, 0) != coalesce(dep.toilets, 0))
                             or (coalesce(cr.garages, 0) != coalesce(dep.garages, 0))
                             or (coalesce(cr.year_building, 0) != coalesce(dep.year_building, 0))
                             or (coalesce(cr.cep, '') != coalesce(dep.cep, ''))
                             or (coalesce(trunc(cr.lat, 5), 0) != coalesce(trunc(dep.lat, 5), 0))
                             or (coalesce(trunc(cr.lng, 5), 0) != coalesce(trunc(dep.lng, 5), 0))
                             or (coalesce(cr.street, '') != coalesce(dep.street, ''))
                             or (coalesce(cr.neighborhood, '') != coalesce(dep.neighborhood, ''))
                             or (coalesce(cr.city, '') != coalesce(dep.city, ''))
                             or (coalesce(cr.state, '') != coalesce(dep.state, ''))
                          )
                        and cr.started_on = '{0}'
                    ),
                    end_dates as (
                      select id, source, min(start_date) over (partition by id, source) as end_date
                        from dim_external_property
                      where start_date > '{0}'
                    ),
                    transformed_data as (
                        select
                        cast(
                        cast(cr.id as varchar) +
                          case
                            when website = 'olx' then '01'
                            when website = 'vivareal' then '02'
                            when website = 'zapimoveis' then '03'
                            when website = 'imovelweb' then '04'
                          end
                          + coalesce(right('000' + ((ec.version::smallint) + 1)::varchar, 3), '001')
                        as bigint) as sk_external_property,
                        cr.id, cr.website as source, cr.business, cr.type, cr.primary_phone_number as primary_phone_number,
                        cr.secondary_phone_number as secondary_phone_number, cr.price, cr.rent, cr.condominium,
                        left(cr.iptu, 12)::numeric(14, 2) as iptu, cr.total_area, cr.useful_area, cr.bedrooms::smallint, cr.suites::smallint,
                        cr.toilets::smallint, cr.garages::smallint, cr.year_building::smallint,
                        cr.cep, trunc(cr.lat, 7) as lat, trunc(cr.lng, 7) as lng, cr.street, cr.neighborhood, cr.city,
                        cr.state, '{0}' as start_date, ed.end_date as end_date
                        from datalake_clean.external_property cr
                          left join end_dates ed
                          on cr.id = ed.id = cr.website = ed.source
                          left join entries_changed ec on cr.id = ec.id and cr.website = ec.source
                        where cr.id not in (select id from entries_not_changed)
                          and cr.started_on = '{0}'
                    )
                    select
                        sk_external_property,
                        id,
                        coalesce(
                          (select int_td.sk_external_property
                              from transformed_data int_td
                              where ext_td.type = int_td.type
                                and ext_td.bedrooms = int_td.bedrooms
                                and ext_td.rent between int_td.rent*0.8 and int_td.rent*1.2
                                and ext_td.suites = int_td.suites
                                and ext_td.toilets = int_td.toilets
                                and ext_td.garages = int_td.garages
                                and ext_td.lat between int_td.lat-.0002 and int_td.lat+.0002
                                and ext_td.lng between int_td.lng-.0002 and int_td.lng+.0002
                              order by int_td.sk_external_property asc
                              limit 1
                          ), sk_external_property) as common_id,
                        source, business, type, primary_phone_number, secondary_phone_number, price, rent, condominium,
                        iptu, total_area, useful_area, bedrooms, suites, toilets, garages, year_building, cep, lat, lng,
                        street, neighborhood, city, state, start_date, end_date
                        from transformed_data ext_td""".format(today))

        BaseETL.to_s3(
            filename='dim_external_property_{}'.format(today),
            data_table=insert_table,
            bucket_folder_path='bi-etl-ejuice-tmpfiles',
        )

        BaseETL.bulk_insert_from_s3_to_dw(
            bucket_name='bi-etl-ejuice-tmpfiles',
            filename='dim_external_property_{}'.format(today),
            enum_db_dest=EnumDb.BI_DW,
            table_name='dim_external_property',
            append=True,
            encoding='UTF8'
        )

    def load_fact_market_index(self):
        _logger.info('m=load_fact_market_index, msg=deleting data at {}'.format(today))
        query_clean = """delete from fact_market_index
                          where sk_snapshot_date = replace('{0}', '-', '')::integer""".format(today)
        BaseETL.execute_command(
            command=query_clean,
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            commit=True
        )

        _logger.info('m=load_fact_market_index, msg=inserting data at {}'.format(today))
        query_insert = """insert into fact_market_index (sk_property, sk_external_property, sk_snapshot_date,
                            sk_updated_on_date, business, advertiser_name, advertiser_type)
                                with property_user as (
                                  select
                                    dp.sk_property,
                                    dp.id,
                                    dp.tipo,
                                    dp.aluguel,
                                    dp.cep,
                                    dp.numero_quartos,
                                    dp.numero_suites,
                                    dp.numero_banheiros,
                                    dp.numero_vagas,
                                    dp.lat,
                                    dp.lng,
                                    dp.atualizado_em,
                                    du.nome
                                  from datalake_clean.property_status_full_history psfh
                                      join dim_property dp
                                        on psfh.id = dp.id
                                      join dim_user du
                                        on dp.usuario_id = du.id
                                    where psfh.date = '{0}'
                                      and psfh.date between coalesce(dp.min_version_time::date, '1900-01-01') and coalesce(dp.max_version_time::date, getdate())
                                      and lower(psfh.status_history) = 'publicado'
                                ),
                                ext_property_crawler as (
                                    select dep.*, cr.updated_on, cr.advertiser_name, cr.advertiser_type, cr.description
                                      from dim_external_property dep
                                      join datalake_clean.external_property cr
                                        on dep.id = cr.id
                                           and dep.source = cr.website
                                           and (dep.start_date::date = cr.started_on::date
                                                  or dep.end_date is null)
                                      where cr.started_on = '{0}'
                                ),
                                external_properties_5a as (
                                  select
                                      case
                                        when regexp_instr(description, '(\\d+)[.]') = 1
                                            and length(regexp_replace(regexp_substr(epc.description, '(\\d+)[.]'), '\\D', '')) <= 9
                                          then regexp_replace(regexp_substr(description, '(\\d+)[.]'), '\\D', '')
                                        when regexp_instr(lower(description), '(c.digo do im.vel:) (\\d+)') > 0
                                          then regexp_substr(lower(epc.description), '\\d+', regexp_instr(lower(epc.description), '(c.digo do im.vel(.?)+:(.?)+)(\\d+)'))
                                        else null
                                      end as id,
                                      epc.id as ext_id
                                  from ext_property_crawler epc
                                    where lower(replace(epc.advertiser_name, ' ', '')) in ('5a', 'quintoandar')
                                ),
                                property_with_external_id as (
                                  select pu.*, ep5a.ext_id
                                    from property_user pu
                                    left join external_properties_5a ep5a
                                      on pu.id = 892700000 + ep5a.id::int
                                ),
                                left_join as (
                                    select
                                      coalesce(pwei.sk_property, -1) as sk_property,
                                      coalesce(epc.sk_external_property, -1) as sk_external_property,
                                      coalesce(replace('{0}', '-', '')::integer, -1) as sk_snapshot_date,
                                      case
                                        when pwei.sk_property is not null
                                          then coalesce(to_char(pwei.atualizado_em, 'yyyymmdd')::integer, -1)
                                        else coalesce(to_char(epc.updated_on::TIMESTAMP without time zone, 'yyyymmdd')::integer, -1)
                                      end as sk_updated_on_date,
                                      case
                                        when pwei.sk_property is not null
                                          then 'aluguel'
                                        else epc.business
                                      end as business,
                                      case
                                        when pwei.sk_property is not null
                                          then pwei.nome
                                        else epc.advertiser_name
                                      end as advertiser_name,
                                      case
                                        when pwei.sk_property is not null
                                          then 'proprietario'
                                        else epc.advertiser_type
                                      end as advertiser_type
                                    from ext_property_crawler epc
                                        left join property_with_external_id pwei
                                        on (epc.id = pwei.ext_id)
                                          or (epc.type = pwei.tipo
                                              and coalesce(epc.rent, 0) between pwei.aluguel*0.8 and pwei.aluguel*1.2
                                              and coalesce(epc.bedrooms, 0) = coalesce(pwei.numero_quartos, 0)
                                              and coalesce(epc.bedrooms, 0) = coalesce(pwei.numero_quartos, 0)
                                              and coalesce(epc.suites, 0) = coalesce(pwei.numero_suites, 0)
                                              and coalesce(epc.toilets, 0) = coalesce(pwei.numero_banheiros, 0)
                                              and coalesce(epc.garages, 0) = coalesce(pwei.numero_vagas, 0)
                                              and ((coalesce(epc.lat, 0) between pwei.lat-.0002 and pwei.lat+.0002
                                              and coalesce(epc.lng, 0) between pwei.lng-.0002 and pwei.lng+.0002)
                                                  or coalesce(regexp_replace(epc.cep, '\D', ''), '') = coalesce(regexp_replace(pwei.cep, '\D', ''), ''))
                                           )
                                ),
                                right_join as (
                                   select
                                      coalesce(pwei.sk_property, -1) as sk_property,
                                      coalesce(epc.sk_external_property, -1) as sk_external_property,
                                      coalesce(replace('{0}', '-', '')::integer, -1) as sk_snapshot_date,
                                      case
                                        when pwei.sk_property is not null
                                          then coalesce(to_char(pwei.atualizado_em, 'yyyymmdd')::integer, -1)
                                        else coalesce(to_char(epc.updated_on::TIMESTAMP without time zone, 'yyyymmdd')::integer, -1)
                                      end as sk_updated_on_date,
                                      case
                                        when pwei.sk_property is not null
                                          then 'aluguel'
                                        else epc.business
                                      end as business,
                                      case
                                        when pwei.sk_property is not null
                                          then pwei.nome
                                        else epc.advertiser_name
                                      end as advertiser_name,
                                      case
                                        when pwei.sk_property is not null
                                          then 'proprietario'
                                        else epc.advertiser_type
                                      end as advertiser_type
                                    from ext_property_crawler epc
                                        right join property_with_external_id pwei
                                        on (epc.id = pwei.ext_id)
                                          or (epc.type = pwei.tipo
                                              and coalesce(epc.rent, 0) between pwei.aluguel*0.8 and pwei.aluguel*1.2
                                              and coalesce(epc.bedrooms, 0) = coalesce(pwei.numero_quartos, 0)
                                              and coalesce(epc.suites, 0) = coalesce(pwei.numero_suites, 0)
                                              and coalesce(epc.toilets, 0) = coalesce(pwei.numero_banheiros, 0)
                                              and coalesce(epc.garages, 0) = coalesce(pwei.numero_vagas, 0)
                                              and ((coalesce(epc.lat, 0) between pwei.lat-.0002 and pwei.lat+.0002
                                              and coalesce(epc.lng, 0) between pwei.lng-.0002 and pwei.lng+.0002)
                                                  or coalesce(regexp_replace(epc.cep, '\D', ''), '') = coalesce(regexp_replace(pwei.cep, '\D', ''), ''))
                                           )
                                )
                                select *
                                  from left_join l

                                union

                                select *
                                  from right_join r""".format(today)

        BaseETL.execute_command(
            command=query_insert,
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            commit=True
        )


if __name__ == '__main__':
    crawlers = Crawlers()

    if args[1] == 'transform_data':
        crawlers.transform_data()
    elif args[1] == 'load_dim_external_property':
        crawlers.load_dim_external_property()
    elif args[1] == 'load_fact_market_index':
        crawlers.load_fact_market_index()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
