with all_events as (
  select
    true as partial,
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    trim(amplitude_id) as amplitude_id,
    'QuintoAndar' as region,
    'QuintoAndar' as city
  from datalake_clean.amplitude_events
  where ym >= '2018-01'
    and et = 'landing_page_viewed'
    and trim(app) = '183047'
    and trim(e_ub_page_variant) in ('bv','cj', 'co')
    and trim(e_ub_page_name) = 'Proprietário'
    and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
    and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
    and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
    and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2018-05-07' as date)
)
