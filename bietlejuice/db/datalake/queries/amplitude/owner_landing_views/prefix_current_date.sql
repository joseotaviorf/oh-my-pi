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
      where ym >= '2017-01'
            and et in (
              'landing_page_viewed',
              'Owner_Landing-Views_register_form'
            )
            and ((trim(app) = '183047' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
              or (trim(app) = '160023' and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
            and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
            and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
            and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
            and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-01-01' as date)
            and not(trim(e_ub_page_variant) in ('bv','cj','co') and trim(e_ub_page_name) = 'Proprietário')
    union
        select
            true as partial,
            extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _year,
            extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _month,
            extract(week from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _week,
            extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) as _day,
            coalesce(cast(amplitude_id as varchar), '') as amplitude_id,
            'QuintoAndar' as region,
            'QuintoAndar' as city
        from datalake_amplitude_clean_prod.events
        where year >= 2019
            and event_type in (
              'landing_page_viewed',
              'Owner_Landing-Views_register_form'
            )
            and ((app = 183047 and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-08-23' as date))
              or (app = 160023 and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) < cast('2017-08-23' as date)))
            and extract(year from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(year from (now() - interval '1' month))
            and extract(month from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) = extract(month from (now() - interval '1' month))
            and extract(day from cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date)) < extract(day from now())
            and cast(regexp_extract(trim(event_time), '\d{4}-\d{2}-\d{2}') as date) >= cast('2017-01-01' as date)
            and not(cast(json_extract(event_properties, '$.ub_page_variant') as varchar) in ('bv','cj','co')
                and cast(json_extract(event_properties, '$.ub_page_name') as varchar) = 'Proprietário')
)
