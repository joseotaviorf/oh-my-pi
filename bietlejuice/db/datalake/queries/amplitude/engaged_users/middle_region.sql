listings as (
  select
    ae._year,
    ae._month,
    ae._week,
    ae._day,
    ae.amplitude_id,
    ae.house_id,
    trim(dr.region_code) as region,
    'QuintoAndar' as city,
    ae.partial
  from all_events ae
  join datalake_clean.ods_dim_property ei
    on ae.house_id = cast(ei.id as integer)
  left join datalake_clean.ods_dim_region dr
    on trim(ei.regiao_id) = cast(dr.id as varchar)
),