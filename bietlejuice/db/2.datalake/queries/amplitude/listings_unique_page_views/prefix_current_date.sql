with unique_views_prev as (
  select
    false as partial,
    cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) as dt,
    cast(replace(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}'), '-', '') as bigint) as dt_int,
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    count(distinct trim(amplitude_id)) as unique_amplitude_ids,
    case
      when trim(e_house_id) != '' and regexp_extract(trim(e_house_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_house_id), '\d+')) < 9,
                 892700000 + cast(cast(regexp_extract(trim(e_house_id), '\d+') as double) as integer),
                 if(length(regexp_extract(trim(e_house_id), '\d+')) > 9,
                     null,
                     cast(cast(regexp_extract(trim(e_house_id), '\d+') AS double) AS integer)
                 )
              )
      when trim(e__id__imovel) != '' and regexp_extract(trim(e__id__imovel), '\d+') is not null
        then if(length(regexp_extract(trim(e__id__imovel), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer))
      when trim(e_imovel_id) != '' and regexp_extract(trim(e_imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer))
      when trim(e__imovel_id) != '' and regexp_extract(trim(e__imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e__imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer))
      else -1
    end as house_id
  from datalake_clean.amplitude_events ae
  where ym >= '2017-01'
    and ((trim(app) = '170698' and et = 'listing_page_viewed' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
      or (trim(app) = '157033' and et = 'Listing-View' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '160023' and et = 'Listing-Views_listing' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '156118' and et = 'Listing-View' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
    and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (current_date - interval '1' month))
    and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (current_date - interval '1' month))
    and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from current_date)
  group by 2, 3, 4, 5, 6, 7, 9
),
unique_views as (
  select distinct
    uvp.dt,
    uvp.unique_amplitude_ids,
    uvp.house_id,
    fhs.sk_region
  from unique_views_prev uvp
  join datalake_clean.ods_fact_house_status fhs
    on cast(uvp.house_id as varchar) = substr(fhs.sk_house, 1, 9)
      and fhs.status_history = 'publicado'
      and uvp.dt_int between cast(fhs.sk_min_version_status_date as bigint) and cast(if(fhs.sk_max_status_date = '', date_format(current_date, '%Y%m%d'), fhs.sk_max_status_date) as bigint)
      and date_diff('day', date_parse(fhs.sk_min_version_status_date, '%Y%m%d'), if(fhs.sk_max_status_date = '', current_date, cast(date_parse(fhs.sk_max_status_date, '%Y%m%d') as date))) >= 7
),
date_fill as (
  select
    cast(date_parse(dd."date", '%Y-%m-%d') as date) as dt,
    uv.house_id,
    uv.sk_region
  from unique_views uv
  cross join datalake_clean.ods_dim_date dd
  where dd."date" != ''
  and cast(date_parse(dd."date", '%Y-%m-%d') as date) >= date '2017-01-01'
  and cast(date_parse(dd."date", '%Y-%m-%d') as date) < current_date
  group by 1, 2, 3
),
listing_views as (
  select
    extract(year from df.dt) as _year,
    extract(month from df.dt) as _month,
    extract(week from df.dt) as _week,
    extract(day from df.dt) as _day,
    df.dt,
    df.house_id,
    df.sk_region,
    coalesce(uv.unique_amplitude_ids, 0) as unique_amplitude_ids,
    sum(coalesce(uv.unique_amplitude_ids, 0)) over (partition by df.house_id order by df.dt rows between 6 preceding and current row) as _sum
  from date_fill df
  left join unique_views uv
    on df.house_id = uv.house_id
      and df.dt = uv.dt
),
all_events as (
  select
    _year,
    _month,
    _week,
    _day,
    house_id,
    sk_region,
    true as partial
  from listing_views
  where _sum >= 200
),
