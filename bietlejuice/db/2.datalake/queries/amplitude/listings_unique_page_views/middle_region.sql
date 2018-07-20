listings as (
  select
    ae._year,
    ae._month,
    ae._week,
    ae._day,
    dr.region_code as region,
    'QuintoAndar' as city,
    ae.partial,
    ae.house_id
  from all_events ae
  left join datalake_clean.ods_dim_region dr
    on ae.sk_region = dr.id
)