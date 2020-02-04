with all_events as (
      select
        true as partial,
        extract(year from ts_event) as _year,
        extract(month from ts_event) as _month,
        extract(week from ts_event) as _week,
        extract(day from ts_event) as _day,
        coalesce(cast(id_amplitude as varchar), '') as amplitude_id,
        'QuintoAndar' as region,
        'QuintoAndar' as city
      from datalake_amplitude_clean_prod."183047_landing_page_viewed_events"
      where ep_ub_page_variant in ('bv','cj','co')
        and ep_ub_page_name = 'Proprietário'
		and extract(year from ts_event) = extract(year from (now() - interval '1' month))
        and extract(month from ts_event) = extract(month from (now() - interval '1' month))
        and extract(day from ts_event) < extract(day from now())
        and date(ts_event) >= date('2018-05-07')
)
