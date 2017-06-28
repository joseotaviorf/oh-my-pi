# coding=utf-8
from collections import OrderedDict

from qa_python_utils.aws.athena import AthenaClient

athena = AthenaClient(staging_dir='5a-datalake')

database = 'amplitude_prod'
table_list = [
    'ev_listing_photo_viewed',
    'ev_listing_photosphere_opened',
    'ev_listing_page_viewed',
    'ev_confirmation_visit_confirmed',
    'ev_schedule_page_viewed'
]
for t in table_list:
    athena.msck_repair_table(database, t)

metrics = {
    'usability':
        {
            'query':
                """select 
                     pv.server_upload_date as eventdate,
                     pv.user_properties.platform,
                     pv.amplitude_id, 
                     pv.user_id,
                     pv.event_properties.imovel_id,
                     pv.event_properties.photosphere_id,
                     count (distinct pv.event_type) as viewed,
                     count (distinct po.event_type) as opened
                     from amplitude_prod.ev_listing_photo_viewed pv
                     left join amplitude_prod.ev_listing_photosphere_opened po 
                         on po.amplitude_id=pv.amplitude_id 
                         and po.event_properties.imovel_id=pv.event_properties.imovel_id
                         and po.event_properties.photosphere_id=pv.event_properties.photosphere_id
                     where pv.user_properties.ab_photosphere = 'B'
                     and pv.event_properties.imovel_id IN(select distinct cast(house_id as bigint) from amplitude_prod.ab_photosphere_ids where house_id is not null)
                     group by 1,2,3,4,5,6""",
            'key': 'clean/amplitude/ab_tests/photosphere/usability/usability.parq',
            'schema': OrderedDict([
                ('eventdate', str),
                ('platform', str),
                ('amplitude_id', long),
                ('user_id', long),
                ('imovel_id', long),
                ('photosphere_id', str),
                ('viewed', int),
                ('opened', int)
            ])
        },

    'funnel_conversion':
        {
            'query':
                """select 
                  min(event_time) as listing_viewed_dt, 
                  min(photosphere_open_dt) as photosphere_open_dt,
                  case when avg(if(ab_photosphere='A',10,20)) = 10 then 'A' 
                        when avg(if(ab_photosphere='A',10,20)) = 20 then 'B' else 'E' end as ab_photosphere,
                  min(amplitude_id) as amplitude_id,
                  imovel_id,
                  min(user_id) as user_id,      
                  avg(platform) as platform 
                  from (
                      select
                      a.amplitude_id, 
                      a.event_properties.imovel_id,     
                      a.event_time,     
                      a.user_properties.ab_photosphere,
                      usr.user_id,
                          case when a.user_properties.platform = 'web_mobile' then 0    
                          when a.user_properties.platform = 'web_desktop' then 1 end as platform,
                      b.event_time as photosphere_open_dt   
                      from amplitude_prod.ev_listing_page_viewed a
                      left join amplitude_prod.ev_confirmation_visit_confirmed usr on usr.amplitude_id = a.amplitude_id
                      left join amplitude_prod.ev_listing_photosphere_opened b on b.amplitude_id=a.amplitude_id and b.event_properties.imovel_id=a.event_properties.imovel_id
                      where a.user_properties.ab_photosphere in ('A','B')
                      and a.event_properties.imovel_id IN(select distinct cast(house_id as bigint) from amplitude_prod.ab_photosphere_ids where house_id is not null)
                  ) x 
                group by coalesce(user_id, amplitude_id), imovel_id having avg(if(ab_photosphere='A',10,20)) in (10,20)""",
            'key': 'clean/amplitude/ab_tests/photosphere/funnel_conversion/funnel_conversion.parq',
            'schema': OrderedDict([
                ('listing_viewed_dt', str),
                ('photosphere_open_dt', str),
                ('ab_photosphere', str),
                ('amplitude_id', long),
                ('imovel_id', long),
                ('user_id', long),
                ('platform', int)
            ])
        },

    'conversion_views':
        {
            'query':
                """select 
                     eventdate,
                     neighborhood,
                     count(distinct inq.imovel_id) as count_imovel,
                     count(distinct inq.schedule_viewed) as schedule_viewed,
                     count(distinct inq.visit_scheduled) as visit_scheduled
                     from (
                         select
                         sv.server_upload_date as eventdate,
                         sv.event_properties.neighborhood,
                         sv.event_properties.imovel_id,
                         sv.amplitude_id as schedule_viewed, 
                         vc.amplitude_id as visit_scheduled
                         
                         from amplitude_prod.ev_schedule_page_viewed sv
                         left join amplitude_prod.ev_confirmation_visit_confirmed vc 
                             on vc.amplitude_id = sv.amplitude_id and vc.event_properties.imovel_id = sv.event_properties.imovel_id
                         
                         where sv.server_upload_date >= cast('2017-05-23' as date)
                         group by 1,2,3,4,5
                     ) inq
                     group by 1,2
                     order by 1 desc, 2 asc""",
            'key': 'clean/amplitude/ab_tests/poolvisit/conv_scheduleviewed_to_confirmed/conversion_viewschedule_to_scheduled.parq',
            'schema': OrderedDict([
                ('eventdate', str),
                ('neighborhood', str),
                ('count_imovel', long),
                ('schedule_viewed', long),
                ('visit_scheduled', long)
            ])
        },
}

athena.create_parquet(key=metrics['usability']['key'],
                      query=metrics['usability']['query'],
                      raw_columns=metrics['usability']['schema'])
athena.create_parquet(key=metrics['funnel_conversion']['key'],
                      query=metrics['funnel_conversion']['query'],
                      raw_columns=metrics['funnel_conversion']['schema'])
athena.create_parquet(key=metrics['conversion_views']['key'],
                      query=metrics['conversion_views']['query'],
                      raw_columns=metrics['conversion_views']['schema'])
