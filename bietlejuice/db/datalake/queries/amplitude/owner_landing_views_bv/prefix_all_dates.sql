with all_events as (
      select
        false as partial,
        extract(year from ts_event) as _year,
        extract(month from ts_event) as _month,
        extract(week from ts_event) as _week,
        extract(day from ts_event) as _day,
        coalesce(cast(id_amplitude as varchar), '') as amplitude_id,
        'QuintoAndar' as region,
        'QuintoAndar' as city
      from {db}."183047_landing_page_viewed_events"
      where ep_ub_page_variant in ('bv', 'cj', 'co')
        and ep_ub_page_name = 'Proprietário'
        and date(ts_event) >= date('2018-05-07')
        and date(ts_event) < date(now())
)
