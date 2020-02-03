--refactoring
-- returns listings with more than 200 unique page views from the last 7 days
with unique_views_prev as (
-- get unique amplitude ids from the listing page view event (considering old ones) from last month
        select
            false as partial,
            date(ts_event) as dt,
            cast(replace(regexp_extract(cast(ts_event as varchar), '\d{4}-\d{2}-\d{2}'),'-','') as bigint) as dt_int,
            extract(year from ts_event) as _year,
            extract(month from ts_event) as _month,
            extract(week from ts_event) as _week,
            extract(day from ts_event) as _day,
            coalesce(cast(id_amplitude as varchar), '') as amplitude_id,
            case
              when json_extract(event_properties, '$.house_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') is not null
                then if(length(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+')) < 9,
                         892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') as double) as integer),
                         if(length(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+')) > 9,
                             null,
                             cast(cast(regexp_extract(cast(json_extract(event_properties, '$.house_id') as varchar), '\d+') AS double) AS integer)
                         )
                      )
              when json_extract(event_properties, '$.Id_Imovel') is not null and regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') is not null
                then if(length(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+')) < 9,
                    892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') as double) as integer),
                    cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Id_Imovel') as varchar), '\d+') as double) as integer))
              when json_extract(event_properties, '$.imovel_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') is not null
                then if(length(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+')) < 9,
                    892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') as double) as integer),
                    cast(cast(regexp_extract(cast(json_extract(event_properties, '$.imovel_id') as varchar), '\d+') as double) as integer))
              when json_extract(event_properties, '$.Imovel_id') is not null and regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') is not null
                then if(length(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+')) < 9,
                    892700000 + cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') as double) as integer),
                    cast(cast(regexp_extract(cast(json_extract(event_properties, '$.Imovel_id') as varchar), '\d+') as double) as integer))
            else -1
            end as house_id
        from {db}.events
        where ((id_app = 170698 and event_type = 'listing_page_viewed' and date(ts_event)  >= cast('2017-08-23' as date))
              or (id_app = 157033 and event_type = 'Listing-View' and date(ts_event) < cast('2017-08-23' as date))
              or (id_app = 160023 and event_type = 'Listing-Views_listing' and date(ts_event) < cast('2017-08-23' as date))
              or (id_app = 156118 and event_type = 'Listing-View' and date(ts_event) < cast('2017-08-23' as date)))
              and extract(year from ts_event) = extract(year from (now() - interval '1' month))
              and extract(month from ts_event) = extract(month from (now() - interval '1' month))
              and extract(day from ts_event) < extract(day from now())
      )
      select
        partial,
        dt,
        dt_int,
        _year,
        _month,
        _week,
        _day,
       count(distinct amplitude_id) as unique_amplitude_ids,
       house_id
      from amplitude
      group by 1, 2, 3, 4, 5, 6, 7, 9
),
unique_views as (
-- get house region and filter only published houses at the time of the event
  select distinct
    uvp.dt,
    uvp.unique_amplitude_ids,
    uvp.house_id,
    fhs.sk_region
  from unique_views_prev uvp
  join datalake_clean.fact_house_listingstatus fhs
    on cast(uvp.house_id as varchar) = substr(fhs.sk_house_listing, 1, 9)
      and fhs.status_history = 'publicado'
      and uvp.dt_int between cast(fhs.sk_status_start_date as bigint) and cast(if(fhs.sk_status_end_date = '', date_format(current_date, '%Y%m%d'), fhs.sk_status_end_date) as bigint)
      and date_diff('day', date_parse(fhs.sk_status_start_date, '%Y%m%d'), if(fhs.sk_status_end_date = '', current_date, cast(date_parse(fhs.sk_status_end_date, '%Y%m%d') as date))) >= 7
),
date_fill as (
-- fill date gaps with null unique views
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
-- get remaining columns to compose the date gap fill cte and summing unique page views per house from the last 7 days
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
-- filter 200 unique page views per house
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
