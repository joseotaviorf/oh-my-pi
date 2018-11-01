listings as (
  select distinct -- because of house versioning
    ae._year,
    ae._month,
    ae._week,
    ae._day,
    ae.uuid,
    trim(dr.region_code) as region,
    'QuintoAndar' as city,
    ae.partial
  from all_events ae
  join datalake_clean.ods_dim_house_listing dhl
    on ae.house_id = cast(dhl.id_house as integer)
  join datalake_clean.ods_fact_house_listings fhl
    on dhl.sk_house_listing = fhl.sk_house_listing
  left join datalake_clean.ods_dim_region dr
    on fhl.sk_region = cast(dr.sk_region as varchar)
)