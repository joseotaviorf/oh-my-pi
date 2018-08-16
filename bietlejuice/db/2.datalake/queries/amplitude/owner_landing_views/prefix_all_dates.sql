with all_events as (
  select
    false as partial,
    extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
    extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
    extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
    extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
    trim(amplitude_id) as amplitude_id,
    'QuintoAndar' as region,
    'QuintoAndar' as city
  from datalake_clean.amplitude_events
  where ym >= '2017-01'
    and et in (
      'landing_page_viewed',
      'Owner_Landing-Views_register_form'
    )
    and ((trim(app) = '183047' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
      or (trim(app) = '160023' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
    and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast(now() as date)
    and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-01-01' as date)
    and not(trim(e_ub_page_variant) in ('bv','cj') and trim(e_ub_page_name) = 'Proprietário')
)
