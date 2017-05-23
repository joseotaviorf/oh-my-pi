import boto3
import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

from jobs.wrappers.amplitude.amplitude_athena_wrapper import AthenaAmplitudeETL


def create_parquet(key, query, null_column=None):
    print("Querying on Athena...")
    print(query)
    data = athena._execute_query(query)
    data = data.where(pd.notnull(data), None)

    if null_column is not None:
        for col, _type in null_column:
            for row in xrange(data[col].shape[0]):
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

# database = "amplitude_prod"
# table_list = ["ev_listing_photo_viewed", "ev_listing_photosphere_opened", "ev_listing_page_viewed",
#               "ev_confirmation_visit_confirmed"]
# for t in table_list:
#     athena.msck_repair_table(database, t)

metrics = {"usability":
               """select 
               platform,
               eventdate,
               count(distinct amplitude_id) as nbr_users,
               count(distinct imovel_id) as nbr_imoveis,
               sum(viewed) as viewed,
               sum(opened) as opened
               
               from (
               
                       select 
                       pv.user_properties.platform,
                       pv.amplitude_id, 
                       pv.event_properties.imovel_id,
                       pv.server_upload_date as eventdate,
                       count (distinct pv.event_type) as viewed,
                       count (distinct po.event_type) as opened
                       from amplitude_prod.ev_listing_photo_viewed pv
                       left join amplitude_prod.ev_listing_photosphere_opened po on po.amplitude_id=pv.amplitude_id and po.event_properties.imovel_id=pv.event_properties.imovel_id
                       where pv.user_properties.ab_photosphere = 'B'
                       and pv.event_properties.imovel_id IN(select distinct cast(house_id as bigint) from amplitude_prod.ab_photosphere_ids where house_id is not null)
                       group by 1,2,3,4
               
               )
               group by 1,2""",

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
               order by 1,2,3"""}

usability_key = 'clean/amplitude/ab_tests/photosphere/usability/tmp.parq'
create_parquet(usability_key, metrics['usability'])

funnel_key = 'clean/amplitude/ab_tests/photosphere/funnel_conversion/tmp.parq'
# null_columns = [('user_id', np.int64)]
schema = [('eventdate', np.str),
          ('ab_photosphere', np.str),
          ('platform', np.str),
          ('amplitude_id', np.int64),
          ('imovel_id', np.int64),
          ('user_id', np.int64)]
create_parquet(funnel_key, metrics['funnel_conversion'], schema)


# funnel_conversion_table =\
# """CREATE EXTERNAL TABLE amplitude.ab_photosphere_funnel_conversion (
#   eventdate STRING,
#   ab_photosphere STRING,
# 	platform STRING,
# 	amplitude_id BIGINT,
# 	imovel_id BIGINT,
# 	user_id BIGINT
# )
# STORED AS PARQUET
# LOCATION 's3://5a-amplitude-events/ab_tests/photosphere/funnel_conversion/'"""

# usability_table =\
# """CREATE EXTERNAL TABLE amplitude.ab_photosphere_usability (
#   	platform STRING,
#   eventdate STRING,
#   nbr_users BIGINT,
#   nbr_imoveis BIGINT,
#   viewed BIGINT,
#   opened BIGINT,
#   conversion DOUBLE
# )
# STORED AS PARQUET
# LOCATION 's3://5a-amplitude-events/ab_tests/photosphere/usability//'"""
