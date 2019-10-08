with all_events as (
      select
        false as partial,
        extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
        extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
        extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
        extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
        coalesce(cast(amplitude_id as varchar), '') as amplitude_id,
        'QuintoAndar' as region,
        'QuintoAndar' as city
      from datalake_amplitude_clean_prod.landing_page_viewed_events
      where app = 183047
        and event_ub_page_variant in ('bv','cj','co')
        and event_ub_page_name = 'Proprietário'
        and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2018-05-07' as date)
        and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast(now() as date)
)
