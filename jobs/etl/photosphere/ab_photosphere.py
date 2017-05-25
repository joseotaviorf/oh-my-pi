# coding=utf-8

import os
import sys

import boto3
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

here = os.path.dirname(os.path.realpath(__file__))
sys.path.append(os.path.join(here, '../../../'))
from jobs.wrappers.amplitude.amplitude_athena_wrapper import AthenaAmplitudeETL


def create_parquet(key, query, null_column=None):
    print("Querying on Athena...")
    print(query)
    data = athena._execute_query(query)
    data = data.where(pd.notnull(data), None)

    if null_column is not None:
        for col, _type in null_column:
            for row in xrange(data[col].shape[0]):
                if type(data.loc[row, col]) == unicode:
                    data.loc[row, col] = data.loc[row, col].encode('utf-8')
                data.loc[row, col] = _type(data.loc[row, col]) if data.loc[row, col] is not None else None
    # fake numbers for test with DW
    # data['imovel_id'] = [892765889, 892779318, 892777560, 892765889, 892785924, 892790924, 892799294, 892797389, 892782345,
    #                      892790306, 892782498, 892776230]
    # data['user_id'] = [587, -1, 129667, 130359, 587, 3274, 3274, 181860, 92716, -1, 154104, -1]
    # data['amplitude_id'] = data['user_id']

    print("Creating parquet file...")

    table = pa.Table.from_pandas(df=data)
    file_handler = pa.InMemoryOutputStream()
    pq.write_table(table, file_handler)

    print("Saving to s3...")
    s3_bucket = boto3.resource('s3').Bucket('5a-datalake')
    s3_bucket.put_object(Key=key, Body=file_handler.get_result().to_pybytes())

    print("{} ready!".format(key))


athena = AthenaAmplitudeETL()

database = "amplitude_prod"
table_list = ["ev_listing_photo_viewed", "ev_listing_photosphere_opened", "ev_listing_page_viewed",
              "ev_confirmation_visit_confirmed"]
for t in table_list:
    athena.msck_repair_table(database, t)

metrics = {"usability":
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

           "funnel_conversion":
               """select 
               cast (eventdate as varchar) eventdate,
               ab_photosphere,
               platform,
               amplitude_id,
               imovel_id,
               user_id
               from
               (
                       select
                       pav.user_properties.ab_photosphere,
                       pav.user_properties.platform,
                       pav.amplitude_id, 
                       pav.event_properties.imovel_id,
                       pav.server_upload_date as eventdate,
                       vc.user_id
                       from amplitude_prod.ev_listing_page_viewed pav
                       left join amplitude_prod.ev_listing_photosphere_opened po on po.amplitude_id=pav.amplitude_id and po.event_properties.imovel_id=pav.event_properties.imovel_id
                       left join amplitude_prod.ev_confirmation_visit_confirmed vc on vc.amplitude_id = pav.amplitude_id and vc.user_id is not null
                       where (
                           (pav.user_properties.ab_photosphere = 'A' and po.event_type is null) or 
                           (pav.user_properties.ab_photosphere = 'B' and po.event_type is not null))
                       and pav.event_properties.imovel_id IN(select distinct cast(house_id as bigint) from amplitude_prod.ab_photosphere_ids where house_id is not null)
               )
               group by 1,2,3,4,5,6
               order by 1,2,3""",

           "conversion_views":
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
                    order by 1 desc, 2 asc"""
           }

usability_key = 'clean/amplitude/ab_tests/photosphere/usability/usability.parq'
usability_schema = [('eventdate', np.str),
                    ('platform', np.str),
                    ('amplitude_id', np.int64),
                    ('user_id', np.int64),
                    ('imovel_id', np.int64),
                    ('photosphere_id', np.str),
                    ('viewed', np.int8),
                    ('opened', np.int8)]
create_parquet(usability_key, metrics['usability'], usability_schema)

funnel_key = 'clean/amplitude/ab_tests/photosphere/funnel_conversion/funnel_conversion.parq'
funnel_schema = [('eventdate', np.str),
                 ('ab_photosphere', np.str),
                 ('platform', np.str),
                 ('amplitude_id', np.int64),
                 ('imovel_id', np.int64),
                 ('user_id', np.int64)]
create_parquet(funnel_key, metrics['funnel_conversion'], funnel_schema)

scheduled_key = 'clean/amplitude/ab_tests/poolvisit/conv_scheduleviewed_to_confirmed/conversion_viewschedule_to_scheduled.parq'
scheduled_schema = [('eventdate', np.str),
                    ('neighborhood', np.str),
                    ('count_imovel', np.int64),
                    ('schedule_viewed', np.int64),
                    ('visit_scheduled', np.int64)]
create_parquet(scheduled_key, metrics['conversion_views'], scheduled_schema)
