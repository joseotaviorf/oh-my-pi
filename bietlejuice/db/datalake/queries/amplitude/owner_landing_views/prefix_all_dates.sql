with all_events as (
    select
        false as partial,
        extract(year from ts_event) as _year,
        extract(month from ts_event) as _month,
        extract(week from ts_event) as _week,
        extract(day from ts_event) as _day,
        id_amplitude as amplitude_id,
        'QuintoAndar' as region,
        'QuintoAndar' as city
    from {db}.events
    where event_type in (
          'landing_page_viewed',
          'Owner_Landing-Views_register_form'
        )
        and ((id_app = 183047 and date(ts_event) >= cast('2017-08-23' as date))
            or (id_app = 160023 and date(ts_event) < cast('2017-08-23' as date)))
        and date(ts_event) < cast(now() as date)
        and date(ts_event) >= cast('2017-01-01' as date)
        and not(cast(json_extract(event_properties, '$.ub_page_variant') as varchar) in ('bv','cj','co')
            and cast(json_extract(event_properties, '$.ub_page_name') as varchar) = 'Proprietário')
)