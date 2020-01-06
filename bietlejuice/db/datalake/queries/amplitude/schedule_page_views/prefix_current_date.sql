with all_events as (
      select
        true as partial,
        extract(year from ts_event) as _year,
        extract(month from ts_event) as _month,
        extract(week from ts_event) as _week,
        extract(day from ts_event) as _day,
        coalesce(uuid, '') as uuid,
        if(length(regexp_extract(cast(ep_house_id as varchar), '\d+')) < 9,
                     892700000 + cast(regexp_extract(ep_house_id, '\d+') as integer),
                     cast(regexp_extract(ep_house_id, '\d+') as integer))
        as house_id
      from datalake_amplitude_clean_prod."170698_schedule_page_viewed_events"
      where extract(year from ts_event) = extract(year from (now() - interval '1' month))
		    and extract(month from ts_event) = extract(month from (now() - interval '1' month))
		    and extract(day from ts_event) < extract(day from now())
) ,
