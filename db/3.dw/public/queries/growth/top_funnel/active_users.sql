with all_events as (
  select
    cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) as _date,
	trim(amplitude_id) as amplitude_id,
    case
      when trim(e_house_id) != '' and regexp_extract(trim(e_house_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_house_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e_house_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e_house_id), '\d+') as double) as integer))
      when trim(e__id__imovel) != '' and regexp_extract(trim(e__id__imovel), '\d+') is not null
        then if(length(regexp_extract(trim(e__id__imovel), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__id__imovel), '\d+') as double) as integer))
      when trim(e_imovel_id) != '' and regexp_extract(trim(e_imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e_imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e_imovel_id), '\d+') as double) as integer))
      when trim(e__imovel_id) != '' and regexp_extract(trim(e__imovel_id), '\d+') is not null
        then if(length(regexp_extract(trim(e__imovel_id), '\d+')) < 9, 892700000 + cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer), cast(cast(regexp_extract(trim(e__imovel_id), '\d+') as double) as integer))
      else -1
    end as house_id
	from datalake_clean.amplitude_events
	where (trim(app) = '170698' and trim(et) = 'listing_page_viewed' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
      or (trim(app) = '157033' and trim(et) = 'Listing-View' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '160023' and trim(et) = 'Listing-Views_listing' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
      or (trim(app) = '156118' and trim(et) = 'Listing-View' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date))
),
listings_all as (
  select
	  _date,
	  amplitude_id,
	  house_id,
      'QuintoAndar' as region,
      'QuintoAndar' as city
	from all_events
),
listings_region as (
	select
	  ae._date,
	  ae.amplitude_id,
	  ae.house_id,
      trim(dr.long_region_name) as region,
      trim(dr.city_name) as city
	from all_events ae
    join datalake_clean.ebdb_property ei
      on ae.house_id = cast(ei.id as integer)
    left join datalake_clean.dim_region dr
      on trim(ei.regiao_id) = cast(dr.id as varchar)
),
listings as (
  select *
  from listings_all
  union all
  select *
  from listings_region
),
count_houses_prev as (
  select
    _date,
    region,
    city,
    amplitude_id,
    count(distinct house_id) as house_id_count
  from listings
  group by _date, amplitude_id, region, city
),
group_count_houses as (
  select
    _date,
    amplitude_id,
    sum(house_id_count) as house_id_count
  from count_houses_prev
  where region = 'QuintoAndar'
    and city = 'QuintoAndar'
  group by _date, amplitude_id
  having sum(house_id_count) >= 3
),
count_houses as (
  select
    chp._date,
    chp.amplitude_id,
    chp.region,
    chp.city,
    chp.house_id_count
  from count_houses_prev chp
  join group_count_houses gch
    on chp._date = gch._date
      and chp.amplitude_id = gch.amplitude_id
),
all_dates as (
  select
    extract(year from _date) as _year,
    extract(month from _date) as _month,
    extract(week from _date) as _week,
    extract(day from _date) as _day,
    region,
    city,
    count(distinct amplitude_id) as active_user_count
  from count_houses
  group by _date, region, city
),