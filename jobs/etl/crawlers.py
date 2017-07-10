import logging
import os
import sys
from collections import OrderedDict
from datetime import datetime

from dateutil.relativedelta import relativedelta
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

args = sys.argv

today = datetime.strptime(args[2], '%Y-%m-%d %H:%M:%S').date()
from_date_only = today - relativedelta(days=1)
to_date_only = today + relativedelta(days=1)

bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename()
tmp_dir = '/tmp'


class Crawlers(object):
    def __init__(self):
        self.athena_client = AthenaClient(bucket_datalake)

    def transform_data(self):
        _logger.info('m=transform_data')
        query = """select id, lower(website) as website, url, http_status, crawled_on, updated_on, 
                    lower(business) as business, 
                    case 
                      when regexp_like(lower(type), '(casa.*condom.nio)|(condom.nio.*casa)') then 'CasaCondominio'
                      when regexp_like(lower(type), '(loft)|(kitnet)|(studio)|(kitchenette)') then 'StudioOuKitchenette'
                      when regexp_like(lower(type), '(casa)|(sobrado)') then 'Casa'
                      when regexp_like(lower(type), '(apartamento)|(flat)|(cobertura)') then 'Apartamento'
                      else lower(type)
                    end as type, 
                    advertiser_name,
                    case 
                      when lower(advertiser_type) = 'inmobiliaria' then 'imobiliaria'
                      when lower(advertiser_type) = 'propietario' then 'proprietario'
                      else lower(advertiser_type)
                    end as advertiser_type, 
                    phones, price, rent, condominium, iptu, total_area, useful_area, 
                    cast(bedrooms as bigint) as bedrooms, cast(suites as bigint) as suites, 
                    cast(toilets as bigint) as toilets, cast(garages as bigint) as garages, photos, description, 
                    unit_features, common_features, complementary_info,
                    case
                      when year_building < 1900 then null
                      else cast(year_building as smallint)
                    end year_building,
                    regexp_replace(cep, '\D', '') as cep, lat, lng, street, neighborhood, city, state, crawl_timestamp
                    from datalake_raw.crawlers
                    where crawled_on between '{0}' and '{1}'""".format(from_date_only, to_date_only)

        self.athena_client.create_parquet(
            key='clean/crawlers/{0}_{1}.parq'.format(process_name, today),
            query=query,
            raw_columns=OrderedDict([
                ('id', long),
                ('website', str),
                ('url', str),
                ('http_status', int),
                ('crawled_on', str),
                ('updated_on', str),
                ('business', str),
                ('type', str),
                ('advertiser_name', str),
                ('advertiser_type', str),
                ('phones', str),
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
                ('crawled_on', str),
                ('updated_on', str),
                ('business', str),
                ('type', str),
                ('advertiser_name', str),
                ('advertiser_type', str),
                ('phones', str),
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

    def deduplicate(self):
        _logger.info('m=deduplicate')
        query = """select id, lower(website) as website, url, http_status, crawled_on, updated_on, 
                            lower(business) as business, 
                            case 
                              when regexp_like(lower(type), '(casa.*condom.nio)|(condom.nio.*casa)') then 'CasaCondominio'
                              when regexp_like(lower(type), '(loft)|(kitnet)|(studio)|(kitchenette)') then 'StudioOuKitchenette'
                              when regexp_like(lower(type), '(casa)|(sobrado)') then 'Casa'
                              when regexp_like(lower(type), '(apartamento)|(flat)|(cobertura)') then 'Apartamento'
                              else type
                            end as type, 
                            advertiser_name,
                            case 
                              when regexp_like(lower(advertiser_type), 'i.mobiliaria') then 'imobiliaria'
                              else lower(advertiser_type)
                            end as advertiser_type, 
                            phones, price, rent, condominium, iptu, total_area, useful_area, bedrooms, suites, toilets, 
                            garages, photos, description, unit_features, common_features, complementary_info,
                            case
                              when year_building < 1900 then null
                              else year_building
                            end year_building,
                            cep, lat, lng, street, neighborhood, city, state, crawl_timestamp
                            from datalake_raw.crawlers limit 10"""

        dataframe = self.athena_client.execute_query_and_return_dataframe(query)
        # TODO

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
                        from datalake_clean.crawlers cr
                          right join dim_external_property dep
                            on cr.id = dep.id and cr.website = dep.source
                               and (
                                 (coalesce(cr.business, '') != coalesce(dep.business, ''))
                                 or (coalesce(cr.price, 0) != coalesce(dep.price, 0))
                                 or (coalesce(cr.rent, 0) != coalesce(dep.rent, 0))
                                 or (coalesce(cr.condominium, 0) != coalesce(dep.condominium, 0))
                                 or (coalesce(cr.iptu, 0) != coalesce(cr.iptu, 0))
                                 or (coalesce(cr.total_area, 0) != coalesce(dep.total_area, 0))
                                 or (coalesce(cr.useful_area, 0) != coalesce(dep.useful_area, 0))
                                 or (coalesce(cr.bedrooms, 0) != coalesce(dep.bedrooms, 0))
                                 or (coalesce(cr.suites, 0) != coalesce(dep.suites, 0))
                                 or (coalesce(cr.toilets, 0) != coalesce(dep.toilets, 0))
                                 or (coalesce(cr.garages, 0) != coalesce(dep.garages, 0))
                                 or (coalesce(cr.year_building, 0) != coalesce(dep.year_building, 0))
                                 or (coalesce(cr.cep, '') != coalesce(dep.cep, ''))
                                 or (coalesce(trunc(cr.lat, 7), 0) != coalesce(dep.lat, 0))
                                 or (coalesce(trunc(cr.lng, 7), 0) != coalesce(dep.lng, 0))
                                 or (coalesce(cr.street, '') != coalesce(dep.street, ''))
                                 or (coalesce(cr.neighborhood, '') != coalesce(dep.neighborhood, ''))
                                 or (coalesce(cr.city, '') != coalesce(dep.city, ''))
                                 or (coalesce(cr.state, '') != coalesce(dep.state, ''))
                               )
                        where dep.end_date is null
                    ) and end_date is null""".format(today),
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
                        join datalake_clean.crawlers cr
                          on cr.id = dep.id and cr.website = dep.source and cr.business = dep.business and cr.type = dep.type
                            and (coalesce(cr.primary_phone_number, '') = coalesce(dep.primary_phone_number, ''))
                            and (coalesce(cr.secondary_phone_number, '') = coalesce(dep.secondary_phone_number, ''))
                            and (coalesce(cr.price, 0) = coalesce(dep.price, 0))
                            and (coalesce(cr.rent, 0) = coalesce(dep.rent, 0))
                            and (coalesce(cr.condominium, 0) = coalesce(dep.condominium, 0))
                            and (coalesce(cr.iptu, 0) = coalesce(dep.iptu, 0))
                            and (coalesce(cr.total_area, 0) = coalesce(dep.total_area, 0))
                            and (coalesce(cr.useful_area, 0) = coalesce(dep.useful_area, 0))
                            and (coalesce(cr.bedrooms, 0) = coalesce(dep.bedrooms, 0))
                            and (coalesce(cr.suites, 0) = coalesce(dep.suites, 0))
                            and (coalesce(cr.toilets, 0) = coalesce(dep.toilets, 0))
                            and (coalesce(cr.garages, 0) = coalesce(dep.garages, 0))
                            and (coalesce(cr.year_building, 0) = coalesce(dep.year_building, 0))
                            and (coalesce(cr.cep, '') = coalesce(dep.cep, ''))
                            and (coalesce(trunc(cr.lat, 7), 0) = coalesce(dep.lat, 0))
                            and (coalesce(trunc(cr.lng, 7), 0) = coalesce(dep.lng, 0))
                            and (coalesce(cr.street, '') = coalesce(dep.street, ''))
                            and (coalesce(cr.neighborhood, '') = coalesce(dep.neighborhood, ''))
                            and (coalesce(cr.city, '') = coalesce(dep.city, ''))
                            and (coalesce(cr.state, '') = coalesce(dep.state, ''))
                        where cr.crawled_on between '{0}' and '{1}'
                        and dep.end_date is null
                      ),
                      entries_changed as (
                        select dep.id, dep.source, right(sk_external_property, 3) as version
                        from dim_external_property dep
                        join datalake_clean.crawlers cr
                          on cr.id = dep.id and cr.website = dep.source
                             and (
                               (coalesce(cr.business, '') != coalesce(dep.business, ''))
                               or (coalesce(cr.price, 0) != coalesce(dep.price, 0))
                               or (coalesce(cr.rent, 0) != coalesce(dep.rent, 0))
                               or (coalesce(cr.condominium, 0) != coalesce(dep.condominium, 0))
                               or (coalesce(cr.iptu, 0) != coalesce(cr.iptu, 0))
                               or (coalesce(cr.total_area, 0) != coalesce(dep.total_area, 0))
                               or (coalesce(cr.useful_area, 0) != coalesce(dep.useful_area, 0))
                               or (coalesce(cr.bedrooms, 0) != coalesce(dep.bedrooms, 0))
                               or (coalesce(cr.suites, 0) != coalesce(dep.suites, 0))
                               or (coalesce(cr.toilets, 0) != coalesce(dep.toilets, 0))
                               or (coalesce(cr.garages, 0) != coalesce(dep.garages, 0))
                               or (coalesce(cr.year_building, 0) != coalesce(dep.year_building, 0))
                               or (coalesce(cr.cep, '') != coalesce(dep.cep, ''))
                               or (coalesce(trunc(cr.lat, 7), 0) != coalesce(dep.lat, 0))
                               or (coalesce(trunc(cr.lng, 7), 0) != coalesce(dep.lng, 0))
                               or (coalesce(cr.street, '') != coalesce(dep.street, ''))
                               or (coalesce(cr.neighborhood, '') != coalesce(dep.neighborhood, ''))
                               or (coalesce(cr.city, '') != coalesce(dep.city, ''))
                               or (coalesce(cr.state, '') != coalesce(dep.state, ''))
                            )
                      )
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
                        cr.id, cr.website, cr.business, cr.type, cr.primary_phone_number, cr.secondary_phone_number,
                        cr.price, cr.rent, cr.condominium, cr.iptu, cr.total_area, cr.useful_area, cr.bedrooms::smallint,
                        cr.suites::smallint, cr.toilets::smallint, cr.garages::smallint,
                        cr.year_building::smallint, cr.cep, round(cr.lat, 7), round(cr.lng, 7), cr.street, cr.neighborhood,
                        cr.city, cr.state, '{2}' as start_date, null as end_date
                      from datalake_clean.crawlers cr
                      left join entries_changed ec on cr.id = ec.id and cr.website = ec.source
                        where cr.id not in (select id from entries_not_changed)
            """.format(from_date_only, to_date_only, today))

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
                          select dp.*, du.nome
                          from datalake_clean.property_status_full_history psfh
                            join dim_property dp
                            on psfh.id = dp.id
                            join dim_user du
                            on dp.usuario_id = du.id
                          where psfh.date = '{0}'
                        ),
                        ext_property_crawler as (
                            select dep.*, cr.updated_on, cr.advertiser_name, cr.advertiser_type
                              from dim_external_property dep
                              join datalake_clean.crawlers cr
                                on dep.id = cr.id
                                   and dep.source = cr.website
                                   and dep.start_date::date between cr.crawled_on::date - 1 and cr.crawled_on::date + 1
                        )
                        select
                          pu.sk_property,
                          epc.sk_external_property,
                          replace('{0}', '-', '')::integer as sk_snapshot_date,
                          case
                            when pu.sk_property is not null
                              then to_char(pu.atualizado_em, 'yyyymmdd')::integer
                            else to_char(epc.updated_on::TIMESTAMP without time zone, 'yyyymmdd')::integer
                          end as sk_updated_on_date,
                          case
                            when pu.sk_property is not null
                              then 'aluguel'
                            else epc.business
                          end as business,
                          case
                            when pu.sk_property is not null
                              then pu.nome
                            else epc.advertiser_name
                          end as advertiser_name,
                          case
                            when pu.sk_property is not null
                              then 'proprietario'
                            else epc.advertiser_type
                          end as advertiser_type
                        from ext_property_crawler epc
                            full outer join property_user pu
                            on epc.type = pu.tipo
                              and epc.bedrooms = pu.numero_quartos
                              and epc.suites = pu.numero_suites
                              and epc.toilets = pu.numero_banheiros
                              and epc.garages = pu.numero_vagas
                              and epc.lat between pu.lat-.0002 and pu.lat+.0002
                              and epc.lng between pu.lng-.0002 and pu.lng+.0002""".format(today)

        BaseETL.execute_command(
            command=query_insert,
            db_enum=EnumDb.BI_DW,
            encoding='UTF8',
            commit=True
        )


if __name__ == '__main__':
    crawlers = Crawlers()

    if args[1] == 'transform':
        crawlers.transform_data()
    elif args[1] == 'deduplicate':
        crawlers.deduplicate()
    elif args[1] == 'load_dim_external_property':
        crawlers.load_dim_external_property()
    elif args[1] == 'load_fact_market_index':
        crawlers.load_fact_market_index()
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
